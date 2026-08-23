// Ocala Forest Explorer — ElevenLabs Trail Audio Tour introduction.
//
// Generates (once, then caches) a short spoken introduction for one trail
// in `forest_trails`, using ONLY the trail's own verified official fields
// -- never inventing difficulty, scenery, or facts the source doesn't
// provide. Reuses the SAME OpenAI-text + ElevenLabs-TTS + `voiceovers`-
// bucket pattern copilot-line/forest-discovery already established -- this
// is not a second ElevenLabs integration, just a third caller of the same
// API with the same secrets.
//
// Idempotent by design: if the trail's audio_status is already 'ready',
// this returns the existing audio immediately without calling OpenAI/
// ElevenLabs again -- pressing "Start Trail Audio" a second time (or a
// second visitor opening the same trail) never re-generates or re-bills.
//
// Deploy:
//   supabase functions deploy forest-trail-audio
// Deployed WITH JWT verification (same as copilot-line/forest-discovery).
// Reuses the SAME secrets those already have configured: OPENAI_API_KEY,
// ELEVENLABS_API_KEY, SUPABASE_SERVICE_ROLE_KEY / SUPABASE_URL

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
const LOCATION_VOICE_FALLBACK = "kPzsL2i3teMYv0FxEYQ6"; // DJ Brittney
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

async function sbGet(path: string): Promise<any[]> {
  const r = await fetch(buildSupabaseUrl(`rest/v1/${path}`), { headers: SB });
  if (!r.ok) throw new Error(`GET ${path} -> ${r.status}: ${(await r.text()).slice(0, 300)}`);
  return r.json();
}

async function sbPatch(path: string, body: Record<string, unknown>): Promise<void> {
  const r = await fetch(buildSupabaseUrl(`rest/v1/${path}`), {
    method: "PATCH",
    headers: { ...SB, "Content-Type": "application/json", Prefer: "return=minimal" },
    body: JSON.stringify(body),
  });
  if (!r.ok) throw new Error(`PATCH ${path} -> ${r.status}: ${(await r.text()).slice(0, 300)}`);
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

// The only two ranger-district admin org codes this dataset uses (verified
// against the same USFS source the trail import itself uses -- Region 08 /
// Forest 05 / District 02 = Lake George, District 05 = Seminole). Anything
// else is left unlabeled rather than guessed.
const MANAGING_ORG_LABELS: Record<string, string> = {
  "080502": "the Lake George Ranger District",
  "080505": "the Seminole Ranger District",
};

interface ForestTrailRow {
  id: string;
  trail_no: string;
  trail_name: string | null;
  trail_type: string | null;
  trail_class: string | null;
  trail_surface: string | null;
  accessibility_status: string | null;
  national_trail_designation: number | null;
  managing_org: string | null;
  length_miles: number | null;
  audio_status: string;
  audio_url: string | null;
  audio_script: string | null;
  audio_voice_id: string | null;
  audio_duration_seconds: number | null;
}

const SYSTEM_PROMPT = `You are a friendly, knowledgeable forest guide speaking to a visitor who is about to start hiking a trail in Ocala National Forest, Florida. Write a short, warm, SPOKEN introduction -- like a ranger chatting with someone at the trailhead, never like a database record being read aloud.

Rules, all critical:
- Use ONLY the verified facts you are given. Never invent trail difficulty, scenery, wildlife, history, or any detail not explicitly provided.
- If a fact (e.g. length) is not given, simply don't mention it -- do not guess or approximate.
- Cover, briefly and naturally, whatever of these IS available: a welcome, the trail's name, its length, its official trail number if it adds character, what kind of trail it officially is (hiking/multi-use/equestrian/etc per trail_type), any accessibility note given, and a brief, generic reminder to bring water and watch the weather (Florida heat/rain) is acceptable general safety advice, not a fabricated fact about this specific trail.
- 3-5 short sentences. Spoken tone, not a list.`;

function buildUserPrompt(t: ForestTrailRow): string {
  const name = (t.trail_name?.trim() || `Trail ${t.trail_no}`);
  const facts: string[] = [`Trail name: ${name}`, `Official trail number: ${t.trail_no}`];
  if (t.length_miles != null) facts.push(`Length: ${t.length_miles} miles`);
  if (t.trail_type) facts.push(`Official trail type/use: ${t.trail_type}`);
  if (t.trail_surface) facts.push(`Surface: ${t.trail_surface}`);
  if (t.accessibility_status) facts.push(`Accessibility status: ${t.accessibility_status}`);
  if (t.national_trail_designation === 3) {
    facts.push("This segment is officially part of the Florida National Scenic Trail.");
  }
  const orgLabel = t.managing_org ? MANAGING_ORG_LABELS[t.managing_org] : null;
  if (orgLabel) facts.push(`Managed by ${orgLabel} of Ocala National Forest.`);
  return `Verified facts about this trail:\n- ${facts.join("\n- ")}\n\nWrite the spoken introduction now.`;
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
  path: string,
): Promise<{ url: string; voiceId: string; durationSeconds: number }> {
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
    throw new Error(`ElevenLabs ${tts.status}: ${(await tts.text()).slice(0, 300)}`);
  }
  const bytes = new Uint8Array(await tts.arrayBuffer());
  // Computed from the known constant-bitrate encode this app always
  // requests (mp3_44100_128) -- a derived fact, not an estimate/guess.
  const durationSeconds = Math.round((bytes.length * 8) / MP3_BITRATE_BPS);
  const up = await fetch(buildSupabaseUrl(`storage/v1/object/${VOICEOVERS_BUCKET}/${path}`), {
    method: "POST",
    headers: { ...SB, "x-upsert": "true", "Content-Type": "audio/mpeg" },
    body: bytes,
  });
  if (!up.ok) throw new Error(`upload ${up.status}: ${(await up.text()).slice(0, 300)}`);
  return {
    url: buildSupabaseUrl(`storage/v1/object/public/${VOICEOVERS_BUCKET}/${path}`),
    voiceId,
    durationSeconds,
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Only POST supported" }, 405);
  if (!SERVICE_KEY) return json({ error: "SUPABASE_SERVICE_ROLE_KEY not set" }, 500);
  if (!OPENAI_KEY) return json({ error: "OPENAI_API_KEY not set" }, 500);
  if (!ELEVEN_KEY) return json({ error: "ELEVENLABS_API_KEY not set" }, 500);

  const body = await req.json().catch(() => null) as { trailId?: string } | null;
  const trailId = body?.trailId?.trim();
  if (!trailId) return json({ error: "trailId is required" }, 400);

  try {
    const rows = await sbGet(`forest_trails?id=eq.${trailId}&select=*`);
    const trail = rows[0] as ForestTrailRow | undefined;
    if (!trail) return json({ error: "trail not found" }, 404);

    if (trail.audio_status === "ready" && trail.audio_url) {
      return json({
        audioUrl: trail.audio_url,
        script: trail.audio_script,
        durationSeconds: trail.audio_duration_seconds,
        cached: true,
      });
    }

    await sbPatch(`forest_trails?id=eq.${trailId}`, { audio_status: "generating" });

    let script: string;
    try {
      script = await openaiText(SYSTEM_PROMPT, buildUserPrompt(trail));
    } catch (err) {
      await sbPatch(`forest_trails?id=eq.${trailId}`, { audio_status: "error" });
      throw err;
    }
    if (!script) {
      await sbPatch(`forest_trails?id=eq.${trailId}`, { audio_status: "error" });
      return json({ error: "empty_response" }, 502);
    }

    let voiced;
    try {
      voiced = await voiceLine(script, `forest_trails/${trailId}.mp3`);
    } catch (err) {
      await sbPatch(`forest_trails?id=eq.${trailId}`, { audio_status: "error" });
      throw err;
    }

    await sbPatch(`forest_trails?id=eq.${trailId}`, {
      audio_script: script,
      audio_voice_id: voiced.voiceId,
      audio_url: voiced.url,
      audio_duration_seconds: voiced.durationSeconds,
      audio_generated_at: new Date().toISOString(),
      audio_status: "ready",
    });

    return json({
      audioUrl: voiced.url,
      script,
      durationSeconds: voiced.durationSeconds,
      cached: false,
    });
  } catch (err) {
    console.error("forest-trail-audio error", err);
    return json(
      { error: "internal_server_error", detail: String((err as Error)?.message ?? err) },
      500,
    );
  }
});
