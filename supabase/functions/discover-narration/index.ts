// Discover Marion County — "🎧 Hear About It" / "Tell Me More" narration
// generation.
//
// Reuses the SAME OpenAI-text + ElevenLabs-TTS + storage-bucket pattern
// already established by copilot-line/forest-discovery/forest-trail-audio/
// forest-tour — this is another caller of the same two APIs with the same
// secrets, not a new integration of either.
//
// Generate-once-reuse: results are cached in `discover_narrations` keyed by
// (subject_type, subject_id, kind), so the same event/gem/location is never
// re-synthesized on a second listener or a second tap.
//
// This function does NOT decide what to say beyond phrasing the facts it is
// given — it never invents dates, prices, hours, or details not present in
// the request body.
//
// Deploy: supabase functions deploy discover-narration
// Secrets reused (already configured): OPENAI_API_KEY, ELEVENLABS_API_KEY,
// SUPABASE_SERVICE_ROLE_KEY / SUPABASE_URL

const DEFAULT_SUPABASE_URL = "https://qqeyvhcgirmfokoftiuz.supabase.co";

function resolveBaseUrl(): string {
  const raw = (Deno.env.get("SUPABASE_URL") ?? "").trim();
  const url = raw.length > 0 ? raw : DEFAULT_SUPABASE_URL;
  return url.replace(/\/+$/, "");
}

function buildSupabaseUrl(path: string): string {
  return `${resolveBaseUrl()}/${path.replace(/^\/+/, "")}`;
}

const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  Deno.env.get("SUPABASE_SERVICE_KEY") ?? "";
const OPENAI_KEY = Deno.env.get("OPENAI_API_KEY") ?? "";
const ELEVEN_KEY = Deno.env.get("ELEVENLABS_API_KEY") ?? "";

const MODEL = "gpt-4o-mini";
const VOICEOVERS_BUCKET = "voiceovers";
const VOICE_FALLBACK = "kPzsL2i3teMYv0FxEYQ6"; // DJ Brittney
const MP3_BITRATE_BPS = 128_000; // matches output_format mp3_44100_128 below

const SB = { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` };

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
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
      buildSupabaseUrl("rest/v1/narration_settings?select=default_voice_id&limit=1"),
      { headers: SB },
    );
    if (!r.ok) return null;
    const rows = await r.json();
    return rows[0]?.default_voice_id ?? null;
  } catch {
    return null;
  }
}

type SubjectType = "event" | "gem" | "location";
type Kind = "short" | "long";

interface DiscoverRequest {
  subjectType: SubjectType;
  subjectId: string;
  kind: Kind;
  name: string;
  category?: string;
  description?: string;
  distanceLabel?: string;
  dateLabel?: string;
  timeLabel?: string;
  matchedInterests?: string[]; // interests this item was recommended for, if any
}

function isSubjectType(v: unknown): v is SubjectType {
  return v === "event" || v === "gem" || v === "location";
}
function isKind(v: unknown): v is Kind {
  return v === "short" || v === "long";
}

const SYSTEM_PROMPT = `You are a friendly, knowledgeable local guide for Marion County, Florida, helping a visitor discover things to do — events, parks, springs, trails, museums, historic sites, and local gems.

Rules, all critical:
- Use ONLY the facts given to you below. Never invent dates, prices, hours, addresses, history, or any specific detail not provided.
- Never claim an event is happening "today" or "this weekend" unless you are explicitly told that. If no date/time is given, speak about the place/activity generally rather than implying a specific timing.
- Sound like a real person talking, warm and inviting — never like a listing, an ad, or a database record read aloud.
- Never use exclamation-point-heavy hype or generic marketing language ("Don't miss out!", "Amazing!"). Be genuine and specific to the facts you were given.`;

function buildUserPrompt(req: DiscoverRequest): string {
  const facts: string[] = [`Name: ${req.name}`];
  if (req.category) facts.push(`Category: ${req.category}`);
  if (req.description) facts.push(`Description: ${req.description}`);
  if (req.dateLabel) facts.push(`Date: ${req.dateLabel}`);
  if (req.timeLabel) facts.push(`Time: ${req.timeLabel}`);
  if (req.distanceLabel) facts.push(`Distance from the visitor: ${req.distanceLabel}`);
  if (req.matchedInterests?.length) {
    facts.push(`The visitor has told us they're interested in: ${req.matchedInterests.join(", ")}`);
  }

  const lines = ["Verified facts:\n- " + facts.join("\n- ")];

  if (req.kind === "short") {
    lines.push(
      "Write a SHORT spoken teaser (2-3 sentences) inviting the visitor to check this out — a " +
        '"Hear About It" audio intro. Enticing, warm, specific to the facts given — never a full ' +
        "rundown, just enough to make them want to know more.",
    );
  } else {
    lines.push(
      "Write a FULLER spoken overview (4-7 sentences) for a \"Tell Me More\" deep dive — background, " +
        "what makes it interesting, and what to expect. Still ONLY from the facts given; if the facts " +
        "are sparse, keep it appropriately short rather than padding with invented detail.",
    );
  }

  lines.push("Write the spoken segment now — no headers, no bullet points, just the spoken words.");
  return lines.join("\n\n");
}

async function openaiText(system: string, user: string): Promise<string> {
  const r = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { Authorization: `Bearer ${OPENAI_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: MODEL,
      temperature: 0.8,
      messages: [
        { role: "system", content: system },
        { role: "user", content: user },
      ],
    }),
  });
  if (!r.ok) throw new Error(`OpenAI ${r.status}: ${(await r.text()).slice(0, 200)}`);
  const data = await r.json();
  return String(data.choices?.[0]?.message?.content ?? "").trim();
}

async function voiceLine(
  text: string,
): Promise<{ url: string; durationSeconds: number }> {
  const voiceId = (await globalDefaultVoiceId()) || VOICE_FALLBACK;
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
    throw new Error(`ElevenLabs ${tts.status}: ${(await tts.text()).slice(0, 300)}`);
  }
  const bytes = new Uint8Array(await tts.arrayBuffer());
  const durationSeconds = Math.round((bytes.length * 8) / MP3_BITRATE_BPS);
  const path = `discover/${crypto.randomUUID()}.mp3`;
  const up = await fetch(buildSupabaseUrl(`storage/v1/object/${VOICEOVERS_BUCKET}/${path}`), {
    method: "POST",
    headers: { ...SB, "x-upsert": "true", "Content-Type": "audio/mpeg" },
    body: bytes,
  });
  if (!up.ok) throw new Error(`upload ${up.status}: ${(await up.text()).slice(0, 300)}`);
  return {
    url: buildSupabaseUrl(`storage/v1/object/public/${VOICEOVERS_BUCKET}/${path}`),
    durationSeconds,
  };
}

async function cachedNarration(
  subjectType: SubjectType,
  subjectId: string,
  kind: Kind,
): Promise<{ script: string; audio_url: string | null } | null> {
  const url = buildSupabaseUrl(
    `rest/v1/discover_narrations?select=script,audio_url&subject_type=eq.${
      encodeURIComponent(subjectType)
    }&subject_id=eq.${encodeURIComponent(subjectId)}&kind=eq.${kind}&limit=1`,
  );
  const r = await fetch(url, { headers: SB });
  if (!r.ok) return null;
  const rows = await r.json();
  return rows[0] ?? null;
}

async function storeNarration(
  subjectType: SubjectType,
  subjectId: string,
  kind: Kind,
  script: string,
  audioUrl: string | null,
): Promise<void> {
  await fetch(buildSupabaseUrl("rest/v1/discover_narrations?on_conflict=subject_type,subject_id,kind"), {
    method: "POST",
    headers: { ...SB, "Content-Type": "application/json", Prefer: "resolution=merge-duplicates" },
    body: JSON.stringify([{
      subject_type: subjectType,
      subject_id: subjectId,
      kind,
      script,
      audio_url: audioUrl,
    }]),
  }).catch(() => {});
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Only POST supported" }, 405);
  if (!OPENAI_KEY) return json({ error: "OPENAI_API_KEY not set" }, 500);
  if (!ELEVEN_KEY) return json({ error: "ELEVENLABS_API_KEY not set" }, 500);
  if (!SERVICE_KEY) return json({ error: "SUPABASE_SERVICE_ROLE_KEY not set" }, 500);

  const body = await req.json().catch(() => null) as DiscoverRequest | null;
  if (!body || !isSubjectType(body.subjectType) || !isKind(body.kind) || !body.subjectId || !body.name) {
    return json({ error: "subjectType, subjectId, kind, and name are required" }, 400);
  }

  try {
    const cached = await cachedNarration(body.subjectType, body.subjectId, body.kind);
    if (cached) {
      return json({ text: cached.script, audioUrl: cached.audio_url, cached: true });
    }

    const script = await openaiText(SYSTEM_PROMPT, buildUserPrompt(body));
    if (!script) return json({ error: "empty_response" }, 502);

    let audioUrl: string | null = null;
    try {
      const voiced = await voiceLine(script);
      audioUrl = voiced.url;
    } catch (_e) {
      // Text still returned even if TTS fails — the client can fall back to
      // on-device TTS rather than showing nothing.
      audioUrl = null;
    }

    await storeNarration(body.subjectType, body.subjectId, body.kind, script, audioUrl);

    return json({ text: script, audioUrl, cached: false });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
