// ExplorerOS narration worker (Supabase Edge Function).
//
// Drains the `generation_jobs` queue so the admin's "Generate" clicks actually
// run — without any key ever touching the browser. Handles three job types:
//   - research         -> populate knowledge_base for a destination (OpenAI)
//   - narration        -> generate DRAFT scripts (grounded in knowledge; OpenAI)
//   - narration_audio  -> voice APPROVED scripts -> audio_generated (ElevenLabs)
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
const MAX_JOBS = 4; // jobs per invocation
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
  if (!r.ok) return [];
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
          body: bytes,
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
  const jobs = await sbGet(
    `generation_jobs?status=eq.pending&job_type=in.(research,narration,narration_audio,full)` +
      `&order=created_at.asc&limit=${limit}&select=*`,
  );
  const results: unknown[] = [];
  for (const job of jobs) {
    await processJob(job);
    results.push({ id: job.id, type: job.job_type, destination: job.destination });
  }
  return { processed: jobs.length, jobs: results };
}

export { MAX_JOBS };
