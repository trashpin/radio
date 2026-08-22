// Travel Copilot's live personality-line generator — the first SYNCHRONOUS
// OpenAI + ElevenLabs call in this app (everything in narration-worker is an
// async job-queue drain: insert a row, trigger the worker, poll). One
// request in, one response out: a fresh sarcastic line (OpenAI) voiced in
// the existing DJ Sunny/Brittney voice (ElevenLabs), uploaded to the
// existing `voiceovers` bucket, both returned in the same HTTP response so
// the Flutter client can play it immediately.
//
// Deploy:
//   supabase functions deploy copilot-line
// Deployed WITH JWT verification (unlike narration-worker, which is invoked
// from a cron/workflow with no user session) -- the Flutter client's
// `functions.invoke()` call already sends a valid Supabase key (anon/
// publishable, or the current session) as its bearer token.
// Reuses the SAME secrets narration-worker already has configured:
//   OPENAI_API_KEY, ELEVENLABS_API_KEY, SUPABASE_SERVICE_ROLE_KEY / SUPABASE_URL
//
// Safety note: the copilot's ACTUAL safety/navigation instruction text is
// never generated here — the Flutter client already speaks it immediately,
// with zero network dependency, using the deterministic `coreText` it sends
// as part of the request. This function only ever adds a short, optional,
// personality-flavored remark — see the system prompt below.

const DEFAULT_SUPABASE_URL = "https://qqeyvhcgirmfokoftiuz.supabase.co";

function resolveBaseUrl(): string {
  const raw = (Deno.env.get("SUPABASE_URL") ?? "").trim();
  const url = raw.length > 0 ? raw : DEFAULT_SUPABASE_URL;
  return url.replace(/\/+$/, "");
}

function buildSupabaseUrl(path: string): string {
  return `${resolveBaseUrl()}/${path.replace(/^\/+/, "")}`;
}

// Edge Functions inject SUPABASE_SERVICE_ROLE_KEY; CI passes SUPABASE_SERVICE_KEY.
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  Deno.env.get("SUPABASE_SERVICE_KEY") ?? "";
const OPENAI_KEY = Deno.env.get("OPENAI_API_KEY") ?? "";
const ELEVEN_KEY = Deno.env.get("ELEVENLABS_API_KEY") ?? "";

const MODEL = "gpt-4o-mini";
const VOICEOVERS_BUCKET = "voiceovers";
const LOCATION_VOICE_FALLBACK = "kPzsL2i3teMYv0FxEYQ6"; // DJ Brittney

const SB = { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` };

// First function in this repo called directly from the client (every other
// function is invoked from a workflow/cron) — needs its own CORS handling,
// which nothing else here has needed before.
const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

async function globalDefaultVoiceId(): Promise<string | null> {
  try {
    const r = await fetch(
      buildSupabaseUrl(
        "rest/v1/narration_settings?select=default_voice_id&limit=1",
      ),
      { headers: SB },
    );
    if (!r.ok) return null;
    const rows = await r.json();
    return rows[0]?.default_voice_id ?? null;
  } catch {
    return null;
  }
}

const SYSTEM_PROMPT = `You are the Travel Copilot for Sunshine Travel Radio -- a smart, sarcastic, funny, observant, helpful, slightly smart-ass travel companion riding in the passenger seat. You are NEVER annoying, and you are DEAD SERIOUS the instant safety is involved.

Style examples (match this voice, never repeat these verbatim):
- "You missed the turn. Impressive. I literally just told you about it."
- "Fine. We'll do it your way. Recalculating."
- "Slow down. Stop sign ahead. Damn, apparently I have to remind you."
- "Well, we made it. Against several odds."
- "We're approaching a restaurant. Choose wisely. Your digestive system is counting on you."
- "Welcome to town. Let's see what kind of trouble we can find."
- "There's something interesting coming up. And yes, this time I'm actually going to teach you something."

Rules:
- Generate a NEW line every time -- never reuse the example lines verbatim, and never repeat any of the "recently said" lines you're given.
- Only use the verified facts you're given. If none are given, stay observational/personality-only -- never invent history, businesses, distances, or facts.
- If a "core instruction" is provided, it is ALREADY BEING SPOKEN SEPARATELY, exactly as given, with zero room for reinterpretation -- your job is ONLY to add a short remark alongside it, never to restate, replace, or obscure it.
- For safety/navigation events, keep any remark brief and never confusing -- the instruction itself is what matters.
- Keep it to one or two short sentences, spoken out loud, in character.`;

interface CopilotLineRequest {
  eventType?: string;
  priorityTier?: string;
  placeName?: string;
  typeLabel?: string;
  coreText?: string;
  facts?: string[];
  recentLines?: string[];
  profile?: { sarcasm?: string; talkAmount?: string };
  maxWords?: number;
}

function buildUserPrompt(body: CopilotLineRequest): string {
  const lines: string[] = [];
  lines.push(
    `Event: ${body.eventType ?? "unknown"} (priority: ${body.priorityTier ?? "personality"})`,
  );
  if (body.placeName) {
    lines.push(
      `Place: ${body.placeName}${body.typeLabel ? ` (${body.typeLabel})` : ""}`,
    );
  }
  if (body.coreText) {
    lines.push(
      `Core instruction already being spoken separately: "${body.coreText}"`,
    );
  }
  const facts = (body.facts ?? []).filter((f) => (f ?? "").trim().length > 0);
  lines.push(
    facts.length > 0
      ? `Verified facts you may use:\n- ${facts.join("\n- ")}`
      : "No verified facts are available for this moment -- stay observational/personality-only.",
  );
  const recent = (body.recentLines ?? []).filter((l) =>
    (l ?? "").trim().length > 0
  );
  if (recent.length > 0) {
    lines.push(
      `Lines you've already said this trip (do NOT repeat these or anything too similar):\n- ${
        recent.join("\n- ")
      }`,
    );
  }
  const sarcasm = body.profile?.sarcasm ?? "high";
  const talk = body.profile?.talkAmount ?? "medium";
  lines.push(
    `Traveler's sarcasm tolerance: ${sarcasm}. Talk amount preference: ${talk}.`,
  );
  const maxWords = body.maxWords ?? 40;
  lines.push(`Keep it under ${maxWords} words.`);
  return lines.join("\n");
}

async function openaiText(system: string, user: string): Promise<string> {
  if (!OPENAI_KEY) throw new Error("OPENAI_API_KEY not set");
  const r = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${OPENAI_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: MODEL,
      temperature: 0.9,
      messages: [
        { role: "system", content: system },
        { role: "user", content: user },
      ],
    }),
  });
  if (!r.ok) {
    throw new Error(`OpenAI ${r.status}: ${(await r.text()).slice(0, 200)}`);
  }
  const data = await r.json();
  return String(data.choices?.[0]?.message?.content ?? "").trim();
}

/// Voices [text] and uploads it to the existing `voiceovers` bucket —
/// mirrors narration-worker's exact TTS-fetch-upload pattern (never a
/// raw-bytes response to the client). Returns null on any failure — a
/// missing audioUrl is never fatal for this endpoint; the client falls back
/// to on-device TTS of the returned text.
async function voiceLine(text: string): Promise<string | null> {
  if (!ELEVEN_KEY || !SERVICE_KEY) return null;
  try {
    const voiceId = (await globalDefaultVoiceId()) || LOCATION_VOICE_FALLBACK;
    const tts = await fetch(
      `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}?output_format=mp3_44100_128`,
      {
        method: "POST",
        headers: {
          "xi-api-key": ELEVEN_KEY,
          accept: "audio/mpeg",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ text, model_id: "eleven_multilingual_v2" }),
      },
    );
    if (!tts.ok) {
      console.error(
        `copilot-line ElevenLabs ${tts.status}: ${(await tts.text()).slice(0, 300)}`,
      );
      return null;
    }
    const bytes = new Uint8Array(await tts.arrayBuffer());
    const path = `copilot/${crypto.randomUUID()}.mp3`;
    const up = await fetch(
      buildSupabaseUrl(`storage/v1/object/${VOICEOVERS_BUCKET}/${path}`),
      {
        method: "POST",
        headers: { ...SB, "x-upsert": "true", "Content-Type": "audio/mpeg" },
        body: bytes,
      },
    );
    if (!up.ok) {
      console.error(
        `copilot-line upload ${up.status}: ${(await up.text()).slice(0, 300)}`,
      );
      return null;
    }
    return buildSupabaseUrl(
      `storage/v1/object/public/${VOICEOVERS_BUCKET}/${path}`,
    );
  } catch (err) {
    console.error("copilot-line voiceLine error", err);
    return null;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") return json({ error: "Only POST supported" }, 405);

  const body = await req.json().catch(() => null) as CopilotLineRequest | null;
  if (!body) return json({ error: "Invalid JSON" }, 400);

  try {
    const text = await openaiText(SYSTEM_PROMPT, buildUserPrompt(body));
    if (!text) return json({ error: "empty_response" }, 500);
    const audioUrl = await voiceLine(text);
    return json({ text, audioUrl });
  } catch (err) {
    console.error("copilot-line error", err);
    return json({ error: "internal_server_error", detail: String((err as Error)?.message ?? err) }, 500);
  }
});
