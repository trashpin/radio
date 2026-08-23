// Ocala Forest Explorer — DISCOVER: AI photo identification + spoken
// explanation.
//
// The first image/vision AI call and the first true species/feature
// identification capability in this codebase (every existing OpenAI call
// here -- copilot-line, narration-worker -- is text-only). Two synchronous
// actions, called directly from the Flutter client the same way
// copilot-line is (a real-time request/response, not a queued job):
//
//   action: "identify" -- vision call on a freshly-taken/picked photo,
//     BEFORE it's uploaded anywhere. Returns a suggestion the client shows
//     as exactly that -- a suggestion, never a fact (spec §4). A field the
//     model can't determine is returned null/empty, never guessed to fill
//     the shape.
//   action: "narrate" -- reuses the SAME OpenAI-text + ElevenLabs-TTS +
//     `voiceovers`-bucket pattern copilot-line already established, to
//     generate the "Tell Me About It" spoken explanation (spec §7) for
//     whatever the visitor ultimately confirmed -- never re-runs vision,
//     never second-guesses the visitor's confirmed identification.
//
// Deploy:
//   supabase functions deploy forest-discovery
// Deployed WITH JWT verification (same as copilot-line) -- the Flutter
// client's `functions.invoke()` call already sends a valid Supabase key.
// Reuses the SAME secrets copilot-line/narration-worker already have
// configured: OPENAI_API_KEY, ELEVENLABS_API_KEY, SUPABASE_SERVICE_ROLE_KEY / SUPABASE_URL

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

const MODEL = "gpt-4o-mini"; // vision-capable
const VOICEOVERS_BUCKET = "voiceovers"; // existing bucket, same as copilot-line
const LOCATION_VOICE_FALLBACK = "kPzsL2i3teMYv0FxEYQ6"; // DJ Brittney

const SB = { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` };

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

const IDENTIFY_CATEGORY_LABELS: Record<string, string> = {
  wildlife: "an animal, its tracks/signs, a reptile, amphibian, or insect",
  birds: "a bird",
  plants_nature: "a tree, plant, flower, wildflower, mushroom, or other natural feature",
  water: "a spring, lake, creek, water feature, or sinkhole",
  geology: "a rock, geological formation, or terrain feature",
  history: "a historic location, structure, or archaeological feature",
  other: "something that doesn't fit a typical nature-guide category",
};

const IDENTIFY_SYSTEM_PROMPT = `You are a careful field naturalist helping identify something a visitor photographed in Ocala National Forest, Florida. You are NOT a certain, authoritative database -- you are giving your best-effort suggestion from a single photo.

Rules, all critical:
- NEVER state an identification as a certain fact. Always express it as your best guess.
- If you are not confident, SAY SO explicitly and set confidence to "low" -- do not round up your confidence to sound more helpful.
- If the photo is blurry, too distant, ambiguous, or could plausibly be several different things, say that in "caveats" and lower your confidence accordingly.
- Never invent a scientific name you are not reasonably sure of -- return null/empty instead of guessing a plausible-sounding one.
- Stay grounded in Florida/southeastern-US central Florida scrub/forest species and features -- Ocala National Forest is longleaf pine sandhill, scrub, and spring-fed waterways.
- Respond with ONLY a JSON object, no other text, in exactly this shape:
{"identification": string or null, "scientificName": string or null, "confidence": "high"|"medium"|"low", "explanation": string, "caveats": string}
"explanation" is 1-3 short sentences on why you think this. "caveats" is empty string "" only if you have none -- otherwise a short, honest statement of what could make this wrong.`;

interface IdentifyRequest {
  action: "identify";
  imageBase64?: string;
  mimeType?: string;
  category?: string;
  subtype?: string;
}

interface IdentifyResult {
  identification: string | null;
  scientificName: string | null;
  confidence: "high" | "medium" | "low";
  explanation: string;
  caveats: string;
}

function parseIdentifyResult(raw: string): IdentifyResult {
  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(raw);
  } catch {
    // A non-JSON reply is treated as a low-confidence, mostly-empty result
    // rather than crashing the request -- still never inventing a name.
    return {
      identification: null,
      scientificName: null,
      confidence: "low",
      explanation: raw.trim().slice(0, 500),
      caveats: "The identification service returned an unexpected response format.",
    };
  }
  const confidence = parsed.confidence;
  return {
    identification: typeof parsed.identification === "string" && parsed.identification.trim()
      ? parsed.identification.trim()
      : null,
    scientificName: typeof parsed.scientificName === "string" && parsed.scientificName.trim()
      ? parsed.scientificName.trim()
      : null,
    confidence: confidence === "high" || confidence === "medium" || confidence === "low"
      ? confidence
      : "low",
    explanation: typeof parsed.explanation === "string" ? parsed.explanation.trim() : "",
    caveats: typeof parsed.caveats === "string" ? parsed.caveats.trim() : "",
  };
}

async function identify(body: IdentifyRequest): Promise<Response> {
  if (!OPENAI_KEY) return json({ error: "OPENAI_API_KEY not set" }, 500);
  const imageBase64 = (body.imageBase64 ?? "").trim();
  if (!imageBase64) return json({ error: "imageBase64 is required" }, 400);
  const mimeType = body.mimeType?.trim() || "image/jpeg";
  const categoryHint = IDENTIFY_CATEGORY_LABELS[body.category ?? ""] ??
    "something in a natural or historic setting";

  const userText =
    `The visitor categorized this as: ${categoryHint}` +
    (body.subtype ? ` (specifically: ${body.subtype})` : "") +
    `. What do you think this is?`;

  const r = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${OPENAI_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: MODEL,
      temperature: 0.3,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: IDENTIFY_SYSTEM_PROMPT },
        {
          role: "user",
          content: [
            { type: "text", text: userText },
            { type: "image_url", image_url: { url: `data:${mimeType};base64,${imageBase64}` } },
          ],
        },
      ],
    }),
  });
  if (!r.ok) {
    const errText = (await r.text()).slice(0, 300);
    console.error(`forest-discovery identify OpenAI ${r.status}: ${errText}`);
    return json({ error: "identification_failed", detail: errText }, 502);
  }
  const data = await r.json();
  const raw = String(data.choices?.[0]?.message?.content ?? "").trim();
  if (!raw) return json({ error: "empty_response" }, 502);
  return json(parseIdentifyResult(raw));
}

interface NarrateRequest {
  action: "narrate";
  identification?: string;
  scientificName?: string;
  category?: string;
  aiExplanation?: string;
  userNotes?: string;
}

const NARRATE_SYSTEM_PROMPT = `You are a friendly, knowledgeable forest guide talking to a visitor who just found something in Ocala National Forest. Give a short, warm, conversational explanation of what they found -- like a ranger chatting with someone on a trail, not a database entry or field-guide printout. 2-4 sentences, spoken out loud. Never claim the identification is certain if it wasn't -- speak naturally about it as what it likely is. If given very little to go on, keep it general and still warm and encouraging.`;

async function openaiText(system: string, user: string): Promise<string> {
  const r = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${OPENAI_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: MODEL,
      temperature: 0.8,
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

/// Voices [text] into the existing `voiceovers` bucket -- identical
/// upload/return shape to copilot-line's own voiceLine, just a different
/// storage path prefix.
async function voiceLine(text: string): Promise<{ url: string | null; err?: string }> {
  if (!ELEVEN_KEY) return { url: null, err: "ELEVENLABS_API_KEY not set" };
  if (!SERVICE_KEY) return { url: null, err: "SUPABASE_SERVICE_ROLE_KEY not set" };
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
      const errText = `ElevenLabs ${tts.status}: ${(await tts.text()).slice(0, 300)}`;
      console.error(`forest-discovery ${errText}`);
      return { url: null, err: errText };
    }
    const bytes = new Uint8Array(await tts.arrayBuffer());
    const path = `forest_discovery/${crypto.randomUUID()}.mp3`;
    const up = await fetch(
      buildSupabaseUrl(`storage/v1/object/${VOICEOVERS_BUCKET}/${path}`),
      {
        method: "POST",
        headers: { ...SB, "x-upsert": "true", "Content-Type": "audio/mpeg" },
        body: bytes,
      },
    );
    if (!up.ok) {
      const errText = `upload ${up.status}: ${(await up.text()).slice(0, 300)}`;
      console.error(`forest-discovery ${errText}`);
      return { url: null, err: errText };
    }
    return {
      url: buildSupabaseUrl(`storage/v1/object/public/${VOICEOVERS_BUCKET}/${path}`),
    };
  } catch (err) {
    console.error("forest-discovery voiceLine error", err);
    return { url: null, err: String((err as Error)?.message ?? err) };
  }
}

async function narrate(body: NarrateRequest): Promise<Response> {
  if (!OPENAI_KEY) return json({ error: "OPENAI_API_KEY not set" }, 500);
  const identification = (body.identification ?? "").trim();
  const userPrompt = [
    identification
      ? `The visitor confirmed this identification: ${identification}${
        body.scientificName ? ` (${body.scientificName})` : ""
      }.`
      : "The visitor could not confirm an identification -- they are marking this as an unknown discovery.",
    body.category ? `Category: ${body.category}.` : "",
    body.aiExplanation ? `Earlier AI note on the photo: ${body.aiExplanation}` : "",
    body.userNotes ? `Visitor's own notes: ${body.userNotes}` : "",
  ].filter(Boolean).join("\n");

  let text: string;
  try {
    text = await openaiText(NARRATE_SYSTEM_PROMPT, userPrompt);
  } catch (err) {
    console.error("forest-discovery narrate OpenAI error", err);
    return json({ error: "narration_failed", detail: String((err as Error)?.message ?? err) }, 502);
  }
  if (!text) return json({ error: "empty_response" }, 502);
  const voice = await voiceLine(text);
  return json({ text, audioUrl: voice.url, audioError: voice.err });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") return json({ error: "Only POST supported" }, 405);

  const body = await req.json().catch(() => null) as
    | (IdentifyRequest | NarrateRequest)
    | null;
  if (!body) return json({ error: "Invalid JSON" }, 400);

  try {
    if (body.action === "identify") return await identify(body);
    if (body.action === "narrate") return await narrate(body);
    return json({ error: "action must be 'identify' or 'narrate'" }, 400);
  } catch (err) {
    console.error("forest-discovery error", err);
    return json(
      { error: "internal_server_error", detail: String((err as Error)?.message ?? err) },
      500,
    );
  }
});
