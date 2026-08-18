// ExplorerOS narration worker (Supabase Edge Function).
//
// Drains the `generation_jobs` queue so the admin's "Generate" clicks actually
// run — without any key ever touching the browser. Handles these job types:
//   - research         -> populate knowledge_base for a destination (OpenAI)
//   - narration        -> generate DRAFT scripts (grounded in knowledge; OpenAI)
//   - narration_audio  -> voice APPROVED scripts -> audio_generated (ElevenLabs)
//   - full             -> research + narration scripts (dashboard button)
//   - audio            -> master-location narration (OpenAI + ElevenLabs) ->
//                         voiceovers bucket + locations.audio_files (PENDING→READY)
//                         OR (notes "nearby_gem:*") voice a Nearby Gem's script
//                         (ElevenLabs) -> voiceovers + nearby_gems.narration_url
//   - wikimedia_import -> find a Commons hero image -> media bucket +
//                         locations.images + media_assets attribution
//
// It NEVER publishes (publishing stays a manual admin action) and never invents
// facts (writes a needs_review placeholder when a destination has no knowledge).
//
// Deploy:
//   supabase functions deploy narration-worker --no-verify-jwt
//   supabase secrets set OPENAI_API_KEY=... ELEVENLABS_API_KEY=...
// Then schedule it every minute (Supabase dashboard → Edge Functions →
// Schedules, or pg_cron calling the function URL). SUPABASE_URL and
// SUPABASE_SERVICE_ROLE_KEY are injected automatically.

// Project URL used when SUPABASE_URL is unset/blank (e.g. an empty GitHub secret).
const DEFAULT_SUPABASE_URL = "https://qqeyvhcgirmfokoftiuz.supabase.co";

/// Resolve the Supabase base URL from the environment. Treats a blank value as
/// missing (an unset GitHub secret is passed as ""), falls back to the project
/// URL, and throws a descriptive error only if the resolved value isn't a valid
/// absolute URL. This guarantees we never build a relative REST path.
function resolveBaseUrl(): string {
  const raw = (Deno.env.get("SUPABASE_URL") ?? "").trim();
  const url = raw.length > 0 ? raw : DEFAULT_SUPABASE_URL;
  if (!/^https?:\/\//i.test(url)) {
    throw new Error(
      `SUPABASE_URL is missing or invalid ("${raw}"). Set the SUPABASE_URL ` +
        `environment variable / GitHub secret to your project URL, e.g. ` +
        `https://<project-ref>.supabase.co`,
    );
  }
  return url.replace(/\/+$/, ""); // strip trailing slash
}

/// Absolute URL for a Supabase path (REST or Storage). [path] may start with or
/// without a leading slash; the result is always fully-qualified.
export function buildSupabaseUrl(path: string): string {
  return `${resolveBaseUrl()}/${path.replace(/^\/+/, "")}`;
}

// Edge Functions inject SUPABASE_SERVICE_ROLE_KEY; CI passes SUPABASE_SERVICE_KEY.
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  Deno.env.get("SUPABASE_SERVICE_KEY") ?? "";
const OPENAI_KEY = Deno.env.get("OPENAI_API_KEY") ?? "";
const ELEVEN_KEY = Deno.env.get("ELEVENLABS_API_KEY") ?? "";

const MODEL = "gpt-4o-mini";
const BUCKET = "narration";
const VOICEOVERS_BUCKET = "voiceovers"; // master-location narration audio
const MEDIA_BUCKET = "media"; // hero images
const LOCATION_VOICE_FALLBACK = "kPzsL2i3teMYv0FxEYQ6"; // DJ Brittney
// Wikimedia importer UA (Commons blocks requests without a descriptive UA).
const WIKI_UA =
  "ExplorerOS-ImageImporter/1.0 (https://exploreros.app; admin@exploreros.app)";
const MAX_JOBS = 10; // jobs per invocation
const TYPE_CAP = 6; // script types generated per narration job per run
const AUDIO_CAP = 4; // clips voiced per audio job per run

const SB = { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` };

// ── Script types: [dbValue, label, targetWords] ──
const TYPES: [string, string, number][] = [
  ["arrival", "Arrival welcome", 110],
  ["quick_intro", "Quick introduction", 90],
  ["main_history", "Main history", 150],
  ["extended_history", "Extended history", 220],
  ["things_to_notice", "Things to notice around you", 130],
  ["architecture", "Architecture", 130],
  ["wildlife", "Wildlife you might see", 130],
  ["plants", "Plants and flora", 130],
  ["trees", "Trees", 120],
  ["birds", "Birds", 120],
  ["geology", "Geology and landscape", 140],
  ["photography_tips", "Photography tips", 110],
  ["fun_facts", "Fun facts", 120],
  ["family_version", "Family-friendly overview", 120],
  ["kids_version", "Version for kids", 100],
  ["accessibility", "Accessibility information", 120],
  ["scenic_highlights", "Scenic highlights", 130],
  ["hidden_gems", "Hidden gems", 120],
  ["nearby_attractions", "Nearby attractions", 120],
  ["departure", "Departure send-off", 100],
  ["night_tour", "Night tour", 130],
  ["sunrise_tour", "Sunrise tour", 120],
  ["sunset_tour", "Sunset tour", 120],
  ["rainy_day", "Rainy day version", 120],
  ["emergency_info", "Emergency information", 110],
];

// ExplorerOS voice catalog (mirror of lib/features/narration/voices.dart).
const VOICES: { id: string; name: string }[] = [
  { id: "pNInz6obpgDQGcFmaJgB", name: "National Park Ranger (Adam)" },
  { id: "ErXwobaYiN019PkySvjV", name: "Friendly Tour Guide (Antoni)" },
  { id: "TxGEqnHWrfWFTfGW9XjX", name: "Campfire Storyteller (Josh)" },
  { id: "MF3mGyEYCl7XYWbV9V6O", name: "Kids Adventure Guide (Elli)" },
  { id: "VR6AewLTigWG4xSOukaG", name: "Southern Storyteller (Arnold)" },
  { id: "kPzsL2i3teMYv0FxEYQ6", name: "DJ Brittney" },
  { id: "21m00Tcm4TlvDq8ikWAM", name: "Rachel" },
  { id: "EXAVITQu4vr4xnSDxMaL", name: "Bella" },
  { id: "AZnzlk1XvdvUeBnXmlld", name: "Domi" },
];
const FALLBACK_VOICE_ID = "pNInz6obpgDQGcFmaJgB";
const voiceName = (id: string) => VOICES.find((v) => v.id === id)?.name ?? id;

async function globalDefaultVoiceId(): Promise<string | null> {
  const r = await sbGet("narration_settings?select=default_voice_id&limit=1");
  return r[0]?.default_voice_id ?? null;
}
async function destDefaultVoiceId(destId: string): Promise<string | null> {
  const r = await sbGet(
    `voice_defaults?scope=eq.destination&scope_value=eq.${destId}&select=voice_id&limit=1`,
  );
  return r[0]?.voice_id ?? null;
}

// ── QC helpers ──
const wordRe = /[a-zA-Z0-9]+/g;
const wordCount = (s: string) => (s.match(wordRe) ?? []).length;
const speakingSeconds = (w: number) => Math.round((w / 150) * 60);
function tokens(s: string) {
  return new Set((s.toLowerCase().match(wordRe) ?? []));
}
function duplicateScore(a: string, b: string) {
  const ta = tokens(a), tb = tokens(b);
  if (ta.size === 0 && tb.size === 0) return 0;
  let inter = 0;
  for (const t of ta) if (tb.has(t)) inter++;
  const union = new Set([...ta, ...tb]).size;
  return union === 0 ? 0 : inter / union;
}
function maxDuplicate(s: string, others: string[]) {
  let m = 0;
  for (const o of others) m = Math.max(m, duplicateScore(s, o));
  return m;
}
function readability(s: string) {
  const text = (s ?? "").trim();
  if (!text) return 0;
  const sentences = text.split(/[.!?]+/).filter((x) => x.trim()).length;
  const words = wordCount(text);
  if (!sentences || !words) return 0;
  return Math.max(0, Math.min(100, 100 - (words / sentences - 14) * 5));
}

// ── PostgREST helpers ──
async function sbGet(path: string): Promise<any[]> {
  const r = await fetch(buildSupabaseUrl(`rest/v1/${path}`), { headers: SB });
  if (!r.ok) {
    console.error(`sbGet ${path} -> ${r.status}: ${(await r.text()).slice(0, 300)}`);
    return [];
  }
  return await r.json();
}
async function sbInsert(table: string, row: unknown) {
  const r = await fetch(buildSupabaseUrl(`rest/v1/${table}`), {
    method: "POST",
    headers: { ...SB, "Content-Type": "application/json", Prefer: "return=minimal" },
    body: JSON.stringify(row),
  });
  if (!r.ok) throw new Error(`insert ${table} ${r.status}: ${await r.text()}`);
}
async function sbPatch(path: string, patch: unknown) {
  const r = await fetch(buildSupabaseUrl(`rest/v1/${path}`), {
    method: "PATCH",
    headers: { ...SB, "Content-Type": "application/json", Prefer: "return=minimal" },
    body: JSON.stringify(patch),
  });
  if (!r.ok) throw new Error(`patch ${path} ${r.status}: ${await r.text()}`);
}
const enc = (s: string) => encodeURIComponent(s);

async function openaiJson(system: string, user: string): Promise<any> {
  if (!OPENAI_KEY) throw new Error("OPENAI_API_KEY not set");
  const r = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { Authorization: `Bearer ${OPENAI_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: MODEL,
      temperature: 0.85,
      response_format: { type: "json_object" },
      messages: [{ role: "system", content: system }, { role: "user", content: user }],
    }),
  });
  if (!r.ok) throw new Error(`OpenAI ${r.status}: ${(await r.text()).slice(0, 200)}`);
  const data = await r.json();
  return JSON.parse(data.choices[0].message.content);
}

async function openaiText(system: string, user: string): Promise<string> {
  if (!OPENAI_KEY) throw new Error("OPENAI_API_KEY not set");
  const r = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { Authorization: `Bearer ${OPENAI_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: MODEL,
      temperature: 0.8,
      messages: [{ role: "system", content: system }, { role: "user", content: user }],
    }),
  });
  if (!r.ok) throw new Error(`OpenAI ${r.status}: ${(await r.text()).slice(0, 200)}`);
  const data = await r.json();
  return String(data.choices?.[0]?.message?.content ?? "").trim();
}

// ── job note parsing: "narration|scope=destination|mode=all" ──
function parseNotes(notes: string | null): Record<string, string> {
  const out: Record<string, string> = {};
  for (const part of (notes ?? "").split("|")) {
    const i = part.indexOf("=");
    if (i > 0) out[part.slice(0, i).trim()] = part.slice(i + 1).trim();
  }
  return out;
}

async function destByName(name: string) {
  const rows = await sbGet(
    `destinations?name=eq.${enc(name)}&select=destination_id,description,destination_type,state_province&limit=1`,
  );
  return rows[0];
}

async function knowledgeFor(name: string, destId: string | null): Promise<string> {
  const facts = await sbGet(
    `knowledge_base?destination=eq.${enc(name)}&select=category,title,description&limit=80`,
  );
  const species = destId
    ? await sbGet(`species?destination_id=eq.${destId}&select=common_name,category,description&limit=60`)
    : [];
  const lines: string[] = [];
  for (const f of facts) lines.push(`- [${f.category}] ${f.title}: ${f.description ?? ""}`);
  for (const s of species) lines.push(`- [species/${s.category}] ${s.common_name}: ${s.description ?? ""}`);
  return lines.join("\n").trim();
}

// ── research: OpenAI -> knowledge_base ──
async function doResearch(job: any): Promise<{ done: boolean; msg: string }> {
  const name = job.destination as string;
  const existing = await sbGet(`knowledge_base?destination=eq.${enc(name)}&select=id&limit=1`);
  if (existing.length > 0) return { done: true, msg: "knowledge already present" };
  const sys = "You are a meticulous park researcher. State only verifiable, widely-documented facts; never invent specifics.";
  const cat = job.destination_category ?? "destination";
  const state = job.state ?? "";
  const user = `Provide structured, categorized facts about "${name}"${state ? `, ${state}` : ""} (type: ${cat}). ` +
    `Cover history, geography, wildlife, plants, geology, and visitor info where known. ` +
    `Return ONLY strict JSON {"facts":[{"category":"History","title":"...","description":"..."}]}.`;
  const out = await openaiJson(sys, user);
  const facts = (out.facts ?? []) as any[];
  let n = 0;
  for (const f of facts) {
    try {
      await sbInsert("knowledge_base", {
        destination: name,
        destination_category: cat,
        category: f.category ?? "General",
        title: f.title ?? "",
        description: f.description ?? "",
        confidence_score: 0.7,
      });
      n++;
    } catch (_) { /* skip bad fact */ }
  }
  return { done: true, msg: `researched ${n} facts` };
}

// ── narration: OpenAI -> destination_narrations (draft) ──
async function doNarration(job: any): Promise<{ done: boolean; msg: string }> {
  const name = job.destination as string;
  const dest = await destByName(name);
  if (!dest) return { done: true, msg: `destination not found: ${name}` };
  const destId = dest.destination_id as string;
  const mode = parseNotes(job.notes).mode ?? "all";

  const have = await sbGet(`destination_narrations?destination_id=eq.${destId}&select=script_type`);
  const haveTypes = new Set(have.map((r: any) => r.script_type));

  let want: [string, string, number][];
  if (mode === "all" || mode === "missing") {
    want = TYPES.filter(([t]) => !haveTypes.has(t));
  } else {
    want = TYPES.filter(([t]) => t === mode && !haveTypes.has(t));
  }
  if (want.length === 0) return { done: true, msg: "all requested scripts exist" };

  const knowledge = await knowledgeFor(name, destId);
  const hasKnowledge = knowledge.length > 40;
  const batch = want.slice(0, TYPE_CAP);

  for (const [type, label, target] of batch) {
    if (!hasKnowledge) {
      await sbInsert("destination_narrations", {
        destination_id: destId,
        script_type: type,
        title: `[Needs info] ${label} — ${name}`,
        script: `Placeholder: no verified ExplorerOS knowledge exists for "${name}" yet. ` +
          `Research this destination before generating ${label} narration.`,
        status: "needs_review",
        needs_review: true,
        fact_confidence: 0,
        ai_model: MODEL,
      });
      continue;
    }
    const sys = "You are an experienced U.S. National Park ranger recording short spoken audio narration. " +
      "Warm, friendly, natural, professional — never robotic, never mention being an AI. Tell a story, " +
      "transition naturally, end with curiosity. Use ONLY the facts provided; do not invent specifics.";
    const user = `Destination: "${name}". Write ONE "${label}" narration script (~${target} words, ` +
      `~${Math.round((target / 150) * 60)}s at 150 wpm).\n\nExplorerOS knowledge (the ONLY facts you may use):\n` +
      `${knowledge}\n\nReturn ONLY strict JSON {"title":"...","script":"..."}.`;
    try {
      const out = await openaiJson(sys, user);
      const script = String(out.script ?? "");
      const w = wordCount(script);
      await sbInsert("destination_narrations", {
        destination_id: destId,
        script_type: type,
        title: String(out.title ?? `${label} — ${name}`),
        script,
        variant: 1,
        status: "draft",
        word_count: w,
        speaking_seconds: speakingSeconds(w),
        readability_score: readability(script),
        fact_confidence: 0.8,
        ai_model: MODEL,
      });
    } catch (e) {
      // leave for a later run
      console.error(`narration ${type} failed: ${e}`);
    }
  }
  const remaining = want.length - batch.length;
  return remaining > 0
    ? { done: false, msg: `generated ${batch.length}, ${remaining} types remaining` }
    : { done: true, msg: `generated ${batch.length} scripts` };
}

// ── narration_audio: ElevenLabs -> audio_generated (never publishes) ──
// Voice resolution per script: narration.voice_id → destination default →
// global default → fallback. No hardcoded default beyond the last-resort.
async function doAudio(job: any): Promise<{ done: boolean; msg: string }> {
  if (!ELEVEN_KEY) return { done: false, msg: "ELEVENLABS_API_KEY not set" };
  const notes = parseNotes(job.notes);

  let filter: string;
  if (notes.id) {
    filter = `id=eq.${notes.id}`;
  } else {
    let destId = job.destination as string;
    if (!/^[0-9a-f-]{36}$/i.test(destId)) {
      const d = await destByName(job.destination);
      destId = d?.destination_id ?? "";
    }
    if (!destId) return { done: true, msg: "destination not found" };
    filter = `destination_id=eq.${destId}&status=eq.approved&audio_url=is.null`;
  }
  const rows = await sbGet(`destination_narrations?select=*&${filter}`);
  const pending = rows.filter((r: any) => !(r.audio_url ?? "").length);
  if (pending.length === 0) return { done: true, msg: "no approved scripts need audio" };

  const globalVoice = await globalDefaultVoiceId();
  const destCache = new Map<string, string | null>();
  const batch = pending.slice(0, AUDIO_CAP);
  let ok = 0;
  for (const r of batch) {
    try {
      let voiceId: string | null = (r.voice_id && String(r.voice_id).length)
        ? String(r.voice_id)
        : null;
      if (!voiceId) {
        const dId = String(r.destination_id ?? "");
        if (dId && !destCache.has(dId)) destCache.set(dId, await destDefaultVoiceId(dId));
        voiceId = (dId ? destCache.get(dId) : null) || globalVoice || FALLBACK_VOICE_ID;
      }
      const vName = voiceName(voiceId);
      const tts = await fetch(
        `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}?output_format=mp3_44100_128`,
        {
          method: "POST",
          headers: { "xi-api-key": ELEVEN_KEY, accept: "audio/mpeg", "Content-Type": "application/json" },
          body: JSON.stringify({ text: r.script, model_id: "eleven_multilingual_v2" }),
        },
      );
      if (!tts.ok) throw new Error(`ElevenLabs ${tts.status}`);
      const bytes = new Uint8Array(await tts.arrayBuffer());
      const path = `destinations/${r.id}.mp3`;
      const up = await fetch(
        buildSupabaseUrl(`storage/v1/object/${BUCKET}/${path}`),
        {
          method: "POST",
          headers: { ...SB, "x-upsert": "true", "Content-Type": "audio/mpeg" },
          body: bytes as BodyInit,
        },
      );
      if (!up.ok) throw new Error(`upload ${up.status}`);
      const words = r.word_count ?? wordCount(r.script ?? "");
      await sbPatch(`destination_narrations?id=eq.${r.id}`, {
        audio_url: buildSupabaseUrl(`storage/v1/object/public/${BUCKET}/${path}`),
        voice: vName,
        voice_id: voiceId,
        duration_seconds: r.speaking_seconds ?? speakingSeconds(words),
        audio_generated_at: new Date().toISOString(),
        status: "audio_generated", // NOT published
      });
      ok++;
    } catch (e) {
      console.error(`audio ${r.id} failed: ${e}`);
    }
  }
  const remaining = pending.length - batch.length;
  return remaining > 0
    ? { done: false, msg: `voiced ${ok}, ${remaining} remaining` }
    : { done: true, msg: `voiced ${ok}` };
}

// Master-location jobs (audio / wikimedia_import) carry the location id in
// their notes as `...;id=<uuid>;...`. Extract it (falls back to null).
function noteLocationId(notes: string | null): string | null {
  const m = /id=([0-9a-fA-F-]{36})/.exec(notes ?? "");
  return m ? m[1] : null;
}

// ── audio: master-location narration -> voiceovers bucket -> audio_files ──
// Mirrors tool/generate_location_audio.py: write a short OpenAI narration, voice
// it (ElevenLabs), upload the MP3, and set the location's audio_files (which
// promotes it PENDING -> READY). Never overwrites existing audio.
export async function doLocationAudio(job: any): Promise<{ done: boolean; msg: string }> {
  if (!ELEVEN_KEY) return { done: false, msg: "ELEVENLABS_API_KEY not set" };
  const id = noteLocationId(job.notes);
  if (!id) return { done: true, msg: "no location id in notes" };
  const rows = await sbGet(
    `locations?id=eq.${id}&select=id,name,category,county,city,description,audio_files,latitude,longitude&limit=1`,
  );
  const loc = rows[0];
  if (!loc) return { done: true, msg: `location not found: ${id}` };
  const hasAudio = (loc.audio_files ?? []).some((u: string) => (u ?? "").trim());
  if (hasAudio) return { done: true, msg: "already has audio" };

  const typ = String(loc.category ?? "point of interest").replace(/_/g, " ");
  const where = loc.county ? ` in ${loc.county} County` : "";
  const desc = String(loc.description ?? "").trim();
  const text = await openaiText(
    "You are a professional Florida travel radio narrator.",
    `Write a warm, factual 45-70 word spoken radio narration introducing ` +
      `${loc.name}, a ${typ}${where}, Florida. ${desc ? "Context: " + desc : ""} ` +
      `Keep it evocative and accurate; do NOT invent specific numbers, dates, or ` +
      `claims. Output only the narration text, no title or quotes.`,
  );
  if (!text) return { done: false, msg: "empty narration text" };

  const voiceId = (await globalDefaultVoiceId()) || LOCATION_VOICE_FALLBACK;
  const tts = await fetch(
    `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}?output_format=mp3_44100_128`,
    {
      method: "POST",
      headers: { "xi-api-key": ELEVEN_KEY, accept: "audio/mpeg", "Content-Type": "application/json" },
      body: JSON.stringify({ text, model_id: "eleven_multilingual_v2" }),
    },
  );
  if (!tts.ok) throw new Error(`ElevenLabs ${tts.status}`);
  const bytes = new Uint8Array(await tts.arrayBuffer());
  const path = `locations/${id}.mp3`;
  const up = await fetch(
    buildSupabaseUrl(`storage/v1/object/${VOICEOVERS_BUCKET}/${path}`),
    { method: "POST", headers: { ...SB, "x-upsert": "true", "Content-Type": "audio/mpeg" }, body: bytes as BodyInit },
  );
  if (!up.ok) throw new Error(`upload ${up.status}`);
  const url = buildSupabaseUrl(`storage/v1/object/public/${VOICEOVERS_BUCKET}/${path}`);
  await sbPatch(`locations?id=eq.${id}`, { audio_files: [url] });
  return { done: true, msg: `voiced ${loc.name} (${Math.round(bytes.length / 1024)} KB)` };
}

// ── content: generate + SAVE short/long description + narration script ──
// For imported/bare master locations (e.g. OpenStreetMap drafts) that have a
// name + type + place but no copy. Generates type-appropriate text and fills
// ONLY the empty fields (never clobbers an admin's writing). Leaves
// content_status untouched, so the location stays a hidden draft until an admin
// reviews the generated copy and publishes it — this produces the text to
// review, it does not publish. Triggered by an `audio` job whose notes contain
// `master_location:content;id=<uuid>`.
export async function doLocationContent(
  job: any,
): Promise<{ done: boolean; msg: string }> {
  const id = noteLocationId(job.notes);
  if (!id) return { done: true, msg: "no location id in notes" };
  const rows = await sbGet(
    `locations?id=eq.${id}&select=id,name,category,county,city,state,description,` +
      `short_description,long_description,narration_script&limit=1`,
  );
  const loc = rows[0];
  if (!loc) return { done: true, msg: `location not found: ${id}` };

  const cur = (v: unknown) => String(v ?? "").trim();
  // Nothing to do if a human already wrote the key fields.
  if (cur(loc.short_description) && cur(loc.long_description) &&
      cur(loc.narration_script)) {
    return { done: true, msg: `content already present for ${loc.name}` };
  }

  const typ = String(loc.category ?? "point of interest").replace(/_/g, " ");
  const place = [
    loc.city,
    loc.county ? `${loc.county} County` : null,
    cur(loc.state) || "Florida",
  ].filter(Boolean).join(", ");

  const gen = await openaiJson(
    "You are a professional travel writer and radio narrator for a US travel " +
      "companion app. Write accurate, evocative copy. Do NOT invent specific " +
      "numbers, dates, prices, phone numbers, hours, or unverifiable claims.",
    `Return JSON with keys "short_description", "long_description", ` +
      `"narration_script" for this place.\n` +
      `Place: ${loc.name}\nType: ${typ}\nLocation: ${place}\n` +
      (cur(loc.description) ? `Known context: ${loc.description}\n` : "") +
      `- short_description: one vivid sentence, max 160 characters.\n` +
      `- long_description: 2-3 short paragraphs a traveler would enjoy, ` +
      `tailored to a ${typ}.\n` +
      `- narration_script: a warm 60-90 word spoken radio narration ` +
      `introducing it (no title, no quotes).\n` +
      `Keep everything factual and non-committal about specifics you cannot verify.`,
  );

  const patch: Record<string, unknown> = {};
  if (!cur(loc.short_description) && gen.short_description) {
    patch.short_description = String(gen.short_description).trim();
  }
  if (!cur(loc.long_description) && gen.long_description) {
    patch.long_description = String(gen.long_description).trim();
  }
  if (!cur(loc.narration_script) && gen.narration_script) {
    patch.narration_script = String(gen.narration_script).trim();
  }
  // `description` is what the map/search/legacy narration read; seed it from
  // the short description when empty so those surfaces improve too.
  if (!cur(loc.description) && gen.short_description) {
    patch.description = String(gen.short_description).trim();
  }
  if (Object.keys(patch).length === 0) {
    return { done: true, msg: `no new content produced for ${loc.name}` };
  }
  await sbPatch(`locations?id=eq.${id}`, patch);
  return {
    done: true,
    msg: `generated content for ${loc.name} (${Object.keys(patch).join(", ")})`,
  };
}

// Extract an ElevenLabs voice id from a job note like "...;voice=<id>".
function noteVoiceId(notes: string | null): string | null {
  const m = /voice=([A-Za-z0-9]+)/.exec(notes ?? "");
  return m ? m[1] : null;
}

// ── audio (nearby_gem): voice a Nearby Gem's script -> voiceovers -> narration_url ──
// Triggered by the admin "Generate Narration" button. Voices the gem's
// narration_script (falling back to long_story, then short_description) with
// ElevenLabs and stores the public URL on nearby_gems.narration_url so the
// traveler's "Local Gems" tap plays a real recording on the radio.
export async function doGemAudio(job: any): Promise<{ done: boolean; msg: string }> {
  if (!ELEVEN_KEY) return { done: false, msg: "ELEVENLABS_API_KEY not set" };
  const id = noteLocationId(job.notes);
  if (!id) return { done: true, msg: "no gem id in notes" };
  const rows = await sbGet(
    `nearby_gems?id=eq.${id}&select=id,name,category,narration_script,long_story,short_description&limit=1`,
  );
  const gem = rows[0];
  if (!gem) return { done: true, msg: `gem not found: ${id}` };

  const text = String(
    gem.narration_script || gem.long_story || gem.short_description || "",
  ).trim();
  if (!text) return { done: true, msg: "no narration text for gem" };

  const voiceId = noteVoiceId(job.notes) ||
    (await globalDefaultVoiceId()) || LOCATION_VOICE_FALLBACK;
  const tts = await fetch(
    `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}?output_format=mp3_44100_128`,
    {
      method: "POST",
      headers: { "xi-api-key": ELEVEN_KEY, accept: "audio/mpeg", "Content-Type": "application/json" },
      body: JSON.stringify({ text, model_id: "eleven_multilingual_v2" }),
    },
  );
  if (!tts.ok) throw new Error(`ElevenLabs ${tts.status}`);
  const bytes = new Uint8Array(await tts.arrayBuffer());
  const path = `gems/${id}.mp3`;
  const up = await fetch(
    buildSupabaseUrl(`storage/v1/object/${VOICEOVERS_BUCKET}/${path}`),
    { method: "POST", headers: { ...SB, "x-upsert": "true", "Content-Type": "audio/mpeg" }, body: bytes as BodyInit },
  );
  if (!up.ok) throw new Error(`upload ${up.status}`);
  const url = buildSupabaseUrl(`storage/v1/object/public/${VOICEOVERS_BUCKET}/${path}`);
  await sbPatch(`nearby_gems?id=eq.${id}`, { narration_url: url });
  return { done: true, msg: `voiced gem ${gem.name} (${Math.round(bytes.length / 1024)} KB)` };
}

// ── wikimedia_import: find a hero image on Commons and attach it ──
// Mirrors tool/wikimedia_import.py: search, filter (name match, >=1200px, real
// photos only), download the best, upload to media/destination-images/, set the
// location hero, and record attribution in media_assets. Never overwrites.
const WIKI_BAD =
  /logo|icon|\bmap\b|flag|coat of arms|\bseal\b|drawing|diagram|chart|\bplan\b|locator|\.svg|\.pdf|signature|blazon|emblem|schematic/i;
const WIKI_ACCEPT_MIME = new Set(["image/jpeg", "image/png", "image/webp"]);
const WIKI_MIN_WIDTH = 1200;
const WIKI_MAX_BYTES = 10 * 1024 * 1024;

function stripHtml(s: string | undefined | null): string {
  return (s ?? "").replace(/<[^>]+>/g, "").trim();
}
function wikiSlug(name: string): string {
  const s = name.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
  return s || "destination";
}
function thumbAt(thumbUrl: string, width: number): string {
  return (thumbUrl ?? "").replace(/\/\d+px-/, `/${width}px-`);
}

async function wikiSearch(query: string): Promise<any[]> {
  const params = new URLSearchParams({
    action: "query", format: "json", generator: "search",
    gsrsearch: `${query} filetype:bitmap`, gsrnamespace: "6", gsrlimit: "20",
    prop: "imageinfo", iiprop: "url|size|mime|extmetadata|dimensions",
    iiurlwidth: "1600",
    iiextmetadatafilter: "Artist|LicenseShortName|LicenseUrl|Credit|Attribution",
  });
  const r = await fetch(`https://commons.wikimedia.org/w/api.php?${params}`, {
    headers: { "User-Agent": WIKI_UA, Accept: "application/json" },
  });
  if (!r.ok) throw new Error(`Commons ${r.status}`);
  const data = await r.json();
  const pages = data?.query?.pages ?? {};
  return Object.values(pages);
}

function wikiPick(pages: any[], name: string, county: string | null) {
  const tokens = (name.toLowerCase().match(/[a-z0-9]+/g) ?? []).filter((t) => t.length > 2);
  const ntokens = tokens.length;
  let best: any = null;
  let bestScore = -1;
  for (const p of pages) {
    const title = String(p.title ?? "");
    const info = (p.imageinfo ?? [null])[0];
    if (!info) continue;
    if (WIKI_BAD.test(title)) continue;
    if (!WIKI_ACCEPT_MIME.has(info.mime ?? "")) continue;
    const w = info.width ?? 0, h = info.height ?? 0;
    if (w < WIKI_MIN_WIDTH) continue;
    const lt = title.toLowerCase();
    const matches = tokens.filter((t) => lt.includes(t)).length;
    const geoOk = lt.includes("florida") || (!!county && lt.includes(county.toLowerCase()));
    const strong = matches >= 3 || matches >= Math.max(2, ntokens);
    const accept = strong || (geoOk && matches >= Math.min(2, ntokens));
    if (!accept) continue;
    let score = matches * 100 + (geoOk ? 300 : 0);
    if (w >= h) score += 500;
    score += Math.min(w, 6000) / 100;
    if (score > bestScore) {
      bestScore = score;
      best = { page: p, info };
    }
  }
  return best;
}

async function wikiDownload(url: string, tries = 3): Promise<Uint8Array | null> {
  for (let i = 0; i < tries; i++) {
    try {
      const r = await fetch(url, { headers: { "User-Agent": WIKI_UA } });
      if (r.ok) return new Uint8Array(await r.arrayBuffer());
    } catch (_) { /* retry */ }
    await new Promise((res) => setTimeout(res, 1000 * (i + 1)));
  }
  return null;
}

export async function doWikimediaImport(job: any): Promise<{ done: boolean; msg: string }> {
  const id = noteLocationId(job.notes);
  if (!id) return { done: true, msg: "no location id in notes" };
  const rows = await sbGet(
    `locations?id=eq.${id}&select=id,name,category,city,county,images&limit=1`,
  );
  const loc = rows[0];
  if (!loc) return { done: true, msg: `location not found: ${id}` };
  const hasHero = (loc.images ?? []).some((u: string) => (u ?? "").trim());
  if (hasHero) return { done: true, msg: "already has hero" };

  const name = String(loc.name ?? "").trim();
  const query = [name, loc.county ? `${loc.county} County` : null, loc.city, "Florida"]
    .filter((p) => p && String(p).trim()).join(" ");
  const pages = await wikiSearch(query);
  const picked = wikiPick(pages, name, loc.county ?? null);
  if (!picked) return { done: true, msg: `no image found for ${name}` };

  const info = picked.info;
  const meta = info.extmetadata ?? {};
  const author = stripHtml(meta.Artist?.value) || "Unknown";
  const license = stripHtml(meta.LicenseShortName?.value) || "See Wikimedia Commons";
  const licenseUrl = stripHtml(meta.LicenseUrl?.value) || null;
  const origUrl = String(info.url ?? "");
  const thumbUrl = String(info.thumburl ?? origUrl);
  const size = info.size ?? 0;
  const mime = info.mime ?? "image/jpeg";
  const ext = ({ "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp" } as Record<string, string>)[mime] ?? "jpg";

  const src = (size && size <= WIKI_MAX_BYTES) ? origUrl : thumbUrl;
  let bytes = await wikiDownload(src);
  if (bytes && bytes.length > WIKI_MAX_BYTES) bytes = await wikiDownload(thumbUrl);
  if (!bytes) bytes = await wikiDownload(thumbUrl);
  if (!bytes) throw new Error("download failed");

  const path = `destination-images/${wikiSlug(name)}.${ext}`;
  const up = await fetch(
    buildSupabaseUrl(`storage/v1/object/${MEDIA_BUCKET}/${path}`),
    { method: "POST", headers: { ...SB, "x-upsert": "true", "Content-Type": mime }, body: bytes as BodyInit },
  );
  if (!up.ok) throw new Error(`upload ${up.status}`);
  const heroUrl = buildSupabaseUrl(`storage/v1/object/public/${MEDIA_BUCKET}/${path}`);

  const imgs = [heroUrl, ...(loc.images ?? []).filter((u: string) => (u ?? "").trim() && u !== heroUrl)];
  await sbPatch(`locations?id=eq.${id}`, { images: imgs });
  await sbInsert("media_assets", {
    record_type: "location",
    record_id: id,
    destination_id: id,
    media_type: "image",
    is_hero: true,
    title: name,
    public_url: heroUrl,
    thumbnail: thumbAt(thumbUrl, 400),
    photographer: author,
    creator: author,
    license,
    license_url: licenseUrl,
    copyright: "Wikimedia Commons",
    source: "wikimedia",
    original_url: origUrl,
    width: info.width ?? null,
    height: info.height ?? null,
    file_size: bytes.length,
    imported_at: new Date().toISOString(),
    tags: ["wikimedia", "hero"],
  }).catch((e) => console.error(`media_assets insert failed: ${e}`));
  return { done: true, msg: `imported hero for ${name} (${license})` };
}

async function processJob(job: any): Promise<void> {
  const id = job.id;
  try {
    await sbPatch(`generation_jobs?id=eq.${id}`, { status: "running" });
    let res: { done: boolean; msg: string };
    switch (job.job_type) {
      case "research":
        res = await doResearch(job);
        break;
      case "narration":
        res = await doNarration(job);
        break;
      case "narration_audio":
        res = await doAudio(job);
        break;
      case "audio": {
        // `audio` jobs are shared by target (from the note prefix):
        //   • `nearby_gem:*`             → voice a Nearby Gem
        //   • `master_location:content*` → generate TEXT content for a location
        //   • `master_location:*`        → voice a master location
        const note = String(job.notes ?? "");
        if (note.startsWith("nearby_gem")) {
          res = await doGemAudio(job);
        } else if (note.includes("master_location:content")) {
          res = await doLocationContent(job);
        } else {
          res = await doLocationAudio(job);
        }
        break;
      }
      case "wikimedia_import":
        res = await doWikimediaImport(job);
        break;
      case "full": {
        // Full pipeline (dashboard button): research, then generate scripts.
        // Audio + publishing remain deliberate manual steps.
        const r1 = await doResearch(job);
        const r2 = await doNarration(job);
        res = { done: r2.done, msg: `${r1.msg}; ${r2.msg}` };
        break;
      }
      default:
        res = { done: true, msg: `unsupported job_type ${job.job_type}` };
    }
    await sbPatch(`generation_jobs?id=eq.${id}`, {
      status: res.done ? "completed" : "pending",
      message: res.msg,
    });
  } catch (e) {
    await sbPatch(`generation_jobs?id=eq.${id}`, {
      status: "failed",
      message: `${e}`.slice(0, 300),
    }).catch(() => {});
  }
}

/// Processes one batch of pending jobs. Shared by the Edge Function (index.ts)
/// and the GitHub Actions runner (run.ts).
export async function drainQueue(
  limit = MAX_JOBS,
): Promise<{ processed: number; jobs: unknown[] }> {
  // Fail loudly (not silently) if the service key wasn't provided.
  if (!SERVICE_KEY.trim()) {
    throw new Error(
      "SUPABASE_SERVICE_ROLE_KEY / SUPABASE_SERVICE_KEY is missing. Add it as a " +
        "GitHub secret (SUPABASE_SERVICE_KEY) or Edge Function secret.",
    );
  }
  // Validate the base URL up front so config errors are obvious.
  buildSupabaseUrl("rest/v1/");
  // Self-heal: reset any jobs stuck in "running" back to pending. The workflow's
  // concurrency group guarantees only one worker runs at a time, so nothing is
  // actively holding a "running" row — a leftover means a prior run timed out.
  await sbPatch(
    `generation_jobs?status=eq.running&job_type=in.(research,narration,narration_audio,full,audio,wikimedia_import)`,
    { status: "pending" },
  ).catch(() => {});
  // Two fetches so we ONLY claim job variants this worker can actually run:
  //   • the narration/knowledge types + wikimedia_import (whole type)
  //   • `audio` jobs that target a master LOCATION (notes start with
  //     "master_location"). Other `audio:*` variants (species records,
  //     dj_banter, batch) belong to their own tooling — we neither run nor
  //     drop them, so they stay pending for that tooling.
  const primary = await sbGet(
    `generation_jobs?status=eq.pending&job_type=in.(research,narration,narration_audio,full,wikimedia_import)` +
      `&order=created_at.asc&limit=${limit}&select=*`,
  );
  // Scoped to Marion County only, matching the app's current curated scope
  // (see active_location_types.dart) — this pool also carries a large
  // pre-seeded statewide backlog (other counties + county=null) that isn't
  // live content yet and shouldn't compete for API budget with real work.
  const locAudio = await sbGet(
    `generation_jobs?status=eq.pending&job_type=eq.audio&notes=like.master_location*` +
      `&county=ilike.marion&order=created_at.asc&limit=${limit}&select=*`,
  );
  // `audio` jobs that target a Nearby Gem (notes start with "nearby_gem").
  const gemAudio = await sbGet(
    `generation_jobs?status=eq.pending&job_type=eq.audio&notes=like.nearby_gem*` +
      `&order=created_at.asc&limit=${limit}&select=*`,
  );
  // Round-robin across the three pools (gem audio, primary knowledge/script
  // types, master-location audio) instead of merging-then-taking-the-globally-
  // oldest-N: a huge, old backlog in ANY one pool (e.g. thousands of
  // wikimedia_import rows) must never fully starve the others for run after
  // run. Within each pool, jobs are still oldest-first (from the queries
  // above).
  const pools = [gemAudio, primary, locAudio];
  const cursors = [0, 0, 0];
  const jobs: any[] = [];
  while (jobs.length < limit) {
    let addedAny = false;
    for (let p = 0; p < pools.length && jobs.length < limit; p++) {
      const job = pools[p][cursors[p]];
      if (job) {
        jobs.push(job);
        cursors[p]++;
        addedAny = true;
      }
    }
    if (!addedAny) break;
  }
  const results: unknown[] = [];
  for (const job of jobs) {
    await processJob(job);
    results.push({ id: job.id, type: job.job_type, destination: job.destination });
  }
  return { processed: jobs.length, jobs: results };
}

export { MAX_JOBS };
