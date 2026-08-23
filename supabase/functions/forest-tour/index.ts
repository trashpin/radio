// Ocala Forest Explorer -- "Take Me On A Tour" narration generation.
//
// Turns a structured, ALREADY-ASSEMBLED context (GPS/geofence-derived
// nearby subject, real verified attributes, and a data-driven content
// classification -- see forest_tour_engine.dart / TourStoryType) into one
// spoken tour segment. Reuses the SAME OpenAI-text + ElevenLabs-TTS +
// `voiceovers`-bucket pattern copilot-line/forest-discovery/
// forest-trail-audio already established -- this is the fourth caller of
// the same two APIs with the same secrets, not a new integration of
// either.
//
// This function does NOT decide what to talk about (that's
// ForestTourEngine/TourSubjectSelector, entirely client-side, reusing the
// existing LocationTriggerEngine/nearestTrailId -- no duplicate geofence/
// location system) and it does NOT decide whether something is verified
// history vs. folklore (that classification comes from the data itself --
// forest_locations.story_category -- and is passed in, then echoed back
// unchanged in the response; the AI's only job is phrasing, never
// reclassifying).
//
// Deploy:
//   supabase functions deploy forest-tour
// Deployed WITH JWT verification (same as copilot-line/forest-discovery/
// forest-trail-audio). Reuses the SAME secrets those already have
// configured: OPENAI_API_KEY, ELEVENLABS_API_KEY,
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

type SegmentKind = "intro" | "location" | "trail" | "general";

interface ForestIdentity {
  name?: string;
  acres?: number;
}

interface LocationSubject {
  name: string;
  category?: string;
  description?: string;
  narrationShort?: string;
  storyType: string; // TourStoryType.id, e.g. 'folklore'
}

interface TrailSubject {
  name: string;
  trailNo?: string;
  lengthMiles?: number;
  trailType?: string;
  trailSurface?: string;
  accessibilityStatus?: string;
  nationalTrailDesignation?: number;
  managingOrgLabel?: string;
}

interface TourRequest {
  segmentKind: SegmentKind;
  tourType?: string;
  forestIdentity?: ForestIdentity;
  locationSubject?: LocationSubject;
  trailSubject?: TrailSubject;
  nearbySummary?: string[]; // short "Name (category, 0.3mi)" strings, for color/context only
  recentlyMentionedNames?: string[]; // avoid re-covering these in the same phrasing
}

// The only two ranger-district admin org codes this dataset uses --
// resolved client-side the same way forest-trail-audio already does, so
// this function just receives the human label, never a raw code to guess
// at.

const STORY_TYPE_LABELS: Record<string, string> = {
  verified_history: "verified history",
  nature: "nature",
  wildlife: "wildlife",
  geology: "geology",
  local_story: "a local story",
  folklore: "folklore",
  legend: "a legend",
  unverified: "unverified/uncertain information",
  general: "general forest information",
};

const SYSTEM_PROMPT = `You are a warm, knowledgeable, live tour guide for Ocala National Forest, Florida, speaking to a visitor during a GPS-guided audio tour as they explore. This is ONE short spoken segment of an ongoing tour -- not a whole tour, not a database read-out.

Rules, all critical:
- Use ONLY the verified facts given to you below. Never invent history, wildlife behavior, geology, distances, difficulty, or any specific detail not provided.
- You will be told this segment's content classification (verified history / nature / wildlife / geology / a local story / folklore / a legend / unverified information / general forest information). If it is folklore, a legend, or unverified, you MUST make that explicit in your own words (e.g. "local folklore holds that..." / "as the story goes..." / "this hasn't been verified, but..."). NEVER phrase folklore or a legend as established fact.
- Do NOT mention trail closures, wildlife warnings, fire restrictions, road closures, or any current safety/emergency advisory of any kind unless it is explicitly given to you in the verified facts. If none is given, say nothing about it -- never speculate or invent a warning.
- Sound like a real person talking, warm and a little conversational -- never like a list, a spec sheet, or a database record read aloud.
- Keep it tight: 2-5 sentences for a location/trail/general segment. The tour introduction may run a little longer (per its own instructions below).
- Never repeat, word-for-word, something already covered this tour (you'll be told what's already been mentioned) -- vary your phrasing and angle if the same subject comes up again.`;

function buildUserPrompt(req: TourRequest): string {
  const lines: string[] = [];
  const identity = req.forestIdentity;
  if (identity?.name) {
    lines.push(
      `Forest identity: ${identity.name}` +
        (identity.acres ? ` (${Math.round(identity.acres).toLocaleString()} acres)` : ""),
    );
  }

  if (req.segmentKind === "intro") {
    lines.push(
      "This is the TOUR INTRODUCTION -- the very first thing the visitor hears when they press " +
        '"Take Me On A Tour". Welcome them warmly, briefly say what you\'ll do for them as their guide ' +
        "(point out interesting places, share stories connected to the forest, let them know when " +
        "there's something worth looking for), and keep it inviting. 3-5 sentences.",
    );
  } else if (req.segmentKind === "trail" && req.trailSubject) {
    const t = req.trailSubject;
    const facts = [`Trail name: ${t.name}`];
    if (t.trailNo) facts.push(`Official trail number: ${t.trailNo}`);
    if (t.lengthMiles != null) facts.push(`Length: ${t.lengthMiles} miles`);
    if (t.trailType) facts.push(`Official trail type/use: ${t.trailType}`);
    if (t.trailSurface) facts.push(`Surface: ${t.trailSurface}`);
    if (t.accessibilityStatus) facts.push(`Accessibility: ${t.accessibilityStatus}`);
    if (t.nationalTrailDesignation === 3) {
      facts.push("This segment is officially part of the Florida National Scenic Trail.");
    }
    if (t.managingOrgLabel) facts.push(`Managed by ${t.managingOrgLabel}.`);
    lines.push("The visitor is on or near this trail. Verified facts:\n- " + facts.join("\n- "));
    lines.push("Content classification: verified history/nature (official USFS trail data).");
  } else if (req.segmentKind === "location" && req.locationSubject) {
    const l = req.locationSubject;
    const facts = [`Name: ${l.name}`];
    if (l.category) facts.push(`Category: ${l.category}`);
    if (l.description) facts.push(`Description: ${l.description}`);
    if (l.narrationShort) facts.push(`Additional verified detail: ${l.narrationShort}`);
    lines.push("The visitor is near this location. Verified facts:\n- " + facts.join("\n- "));
    lines.push(
      `Content classification: ${STORY_TYPE_LABELS[l.storyType] ?? "general forest information"}.`,
    );
  } else {
    // general fallback -- no specific nearby subject (spec: never an error).
    lines.push(
      "No specific nearby location or trail is available right now. Using only the forest " +
        "identity facts above (and nothing else), give the visitor a short, genuine, general " +
        "Ocala National Forest moment -- never invent a specific place, species, or story that " +
        "wasn't given to you.",
    );
  }

  if (req.nearbySummary?.length) {
    lines.push(`Other things nearby, for color only (do not narrate these directly unless relevant): ${req.nearbySummary.join("; ")}`);
  }
  if (req.recentlyMentionedNames?.length) {
    lines.push(`Already covered earlier this tour (vary your phrasing if revisiting): ${req.recentlyMentionedNames.join(", ")}`);
  }

  lines.push("Write the spoken segment now.");
  return lines.join("\n\n");
}

async function openaiText(system: string, user: string): Promise<string> {
  const r = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { Authorization: `Bearer ${OPENAI_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: MODEL,
      temperature: 0.85,
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
  const durationSeconds = Math.round((bytes.length * 8) / MP3_BITRATE_BPS);
  const path = `forest_tour/${crypto.randomUUID()}.mp3`;
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
  if (!OPENAI_KEY) return json({ error: "OPENAI_API_KEY not set" }, 500);
  if (!ELEVEN_KEY) return json({ error: "ELEVENLABS_API_KEY not set" }, 500);
  if (!SERVICE_KEY) return json({ error: "SUPABASE_SERVICE_ROLE_KEY not set" }, 500);

  const body = await req.json().catch(() => null) as TourRequest | null;
  if (!body || !body.segmentKind) return json({ error: "segmentKind is required" }, 400);

  try {
    const script = await openaiText(SYSTEM_PROMPT, buildUserPrompt(body));
    if (!script) return json({ error: "empty_response" }, 502);

    const voiced = await voiceLine(script);

    // The classification is echoed back exactly as given -- never
    // re-derived from the AI's own output, so a folklore/legend label can
    // never quietly be upgraded (or downgraded) by the model.
    const storyType = body.segmentKind === "trail"
      ? "nature"
      : body.segmentKind === "location"
      ? (body.locationSubject?.storyType ?? "general")
      : "general";

    return json({
      text: script,
      storyType,
      audioUrl: voiced.url,
      durationSeconds: voiced.durationSeconds,
    });
  } catch (err) {
    console.error("forest-tour error", err);
    return json(
      { error: "internal_server_error", detail: String((err as Error)?.message ?? err) },
      500,
    );
  }
});
