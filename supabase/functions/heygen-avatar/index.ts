// Marion County Adventures — Story Production System's HeyGen avatar video
// generation. Reuses the SAME "server-side secret, service-role writes,
// public storage bucket" pattern discover-narration already established for
// ElevenLabs — this is a second API integration following the same shape,
// not a new architecture. The HEYGEN_API_KEY never reaches the Flutter app;
// it only ever lives in this function's environment.
//
// HeyGen's video generation is asynchronous (often 1-5 minutes) and can
// outlive a single edge function invocation, so this is a two-step,
// client-polled flow rather than one blocking call:
//   action "generate" -- submits the render job, stores the returned
//     heygen_video_id on the story step, returns immediately.
//   action "status"   -- checks HeyGen's render status for that step; once
//     complete, downloads the finished video and re-uploads it into OUR
//     OWN `videos` storage bucket (the same bucket other video content in
//     this app already uses) so the app never depends on a third-party
//     URL's long-term availability -- exactly how voiceLine() in
//     discover-narration mirrors ElevenLabs audio into `voiceovers`.
//
// Deploy: supabase functions deploy heygen-avatar
// Secrets: HEYGEN_API_KEY (new), SUPABASE_SERVICE_ROLE_KEY / SUPABASE_URL (reused)

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
const HEYGEN_KEY = Deno.env.get("HEYGEN_API_KEY") ?? "";
const VIDEOS_BUCKET = "videos";
const HEYGEN_BASE = "https://api.heygen.com";

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

interface GenerateRequest {
  action: "generate";
  stepId: string;
  avatarId: string;
  // "avatar" (HeyGen stock/studio avatar_id) or "talking_photo" (a custom
  // photo avatar an admin trained in HeyGen directly, e.g. mission_characters
  // seeded with a real person's photo) -- these are DIFFERENT shapes in
  // HeyGen's own API, not just a label. Sending the wrong one either errors
  // or silently renders the wrong/default character.
  avatarType: "avatar" | "talking_photo";
  // The character's ALREADY-GENERATED ElevenLabs narration for this step
  // (mission_story_steps.audio_url) -- HeyGen lip-syncs to this audio track
  // directly (voice type "audio") rather than re-speaking the script with
  // one of HeyGen's own, unrelated voice IDs. This is what makes a
  // character's avatar video sound EXACTLY like their audio-only scenes,
  // not just "a similar HeyGen voice" -- true consistency, not an
  // approximation. Generate Voice must run before Generate Avatar.
  audioUrl: string;
}

interface StatusRequest {
  action: "status";
  stepId: string;
}

type HeygenRequest = GenerateRequest | StatusRequest;

async function updateStep(stepId: string, fields: Record<string, unknown>): Promise<void> {
  await fetch(buildSupabaseUrl(`rest/v1/mission_story_steps?id=eq.${encodeURIComponent(stepId)}`), {
    method: "PATCH",
    headers: { ...SB, "Content-Type": "application/json", Prefer: "return=minimal" },
    body: JSON.stringify(fields),
  });
}

async function getStep(stepId: string): Promise<{ heygen_video_id: string | null } | null> {
  const r = await fetch(
    buildSupabaseUrl(
      `rest/v1/mission_story_steps?select=heygen_video_id&id=eq.${encodeURIComponent(stepId)}&limit=1`,
    ),
    { headers: SB },
  );
  if (!r.ok) return null;
  const rows = await r.json();
  return rows[0] ?? null;
}

async function generate(body: GenerateRequest): Promise<Response> {
  if (!body.audioUrl?.trim()) {
    return json({ error: "audioUrl is required -- generate this step's voice narration first" }, 400);
  }
  if (!body.avatarId?.trim()) return json({ error: "avatarId is required" }, 400);

  const character = body.avatarType !== "avatar"
    ? { type: "talking_photo", talking_photo_id: body.avatarId.trim() }
    : { type: "avatar", avatar_id: body.avatarId.trim(), avatar_style: "normal" };

  const payload: Record<string, unknown> = {
    title: `mission-story-step-${body.stepId}`,
    dimension: { width: 720, height: 1280 }, // portrait, matches the mobile player
    video_inputs: [{
      character,
      voice: { type: "audio", audio_url: body.audioUrl.trim() },
    }],
  };

  const r = await fetch(`${HEYGEN_BASE}/v2/video/generate`, {
    method: "POST",
    headers: { "X-Api-Key": HEYGEN_KEY, "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  const data = await r.json().catch(() => null);
  if (!r.ok || !data?.data?.video_id) {
    return json({ error: `HeyGen ${r.status}: ${JSON.stringify(data)?.slice(0, 300)}` }, 502);
  }

  const videoId = data.data.video_id as string;
  await updateStep(body.stepId, {
    heygen_video_id: videoId,
    production_status: "video_generated", // "generating" isn't in the status vocabulary; the client's own UI shows a spinner while polling
  });
  return json({ status: "processing", heygenVideoId: videoId });
}

async function checkStatus(body: StatusRequest): Promise<Response> {
  const step = await getStep(body.stepId);
  if (!step?.heygen_video_id) {
    return json({ error: "No HeyGen render has been started for this step." }, 400);
  }

  // v3, not the legacy v1/video_status.get -- HeyGen flags v1 for removal
  // 2026-10-31 and points integrations built now at this endpoint instead.
  const r = await fetch(
    `${HEYGEN_BASE}/v3/videos/${encodeURIComponent(step.heygen_video_id)}`,
    { headers: { "X-Api-Key": HEYGEN_KEY } },
  );
  const data = await r.json().catch(() => null);
  const status = data?.data?.status as string | undefined;
  if (!r.ok || !status) {
    return json({ error: `HeyGen ${r.status}: ${JSON.stringify(data)?.slice(0, 300)}` }, 502);
  }

  if (status === "failed") {
    return json({ status: "failed", error: data?.data?.failure_message ?? "Unknown HeyGen failure" });
  }
  if (status !== "completed") {
    return json({ status: "processing" });
  }

  const sourceUrl = data.data.video_url as string | undefined;
  if (!sourceUrl) return json({ status: "failed", error: "HeyGen reported completed with no video_url" });

  // Mirror into our own storage rather than trusting HeyGen's URL to stay
  // valid indefinitely -- the same discipline discover-narration already
  // applies to ElevenLabs audio.
  const videoBytes = await (await fetch(sourceUrl)).arrayBuffer();
  const path = `avatars/${crypto.randomUUID()}.mp4`;
  const up = await fetch(buildSupabaseUrl(`storage/v1/object/${VIDEOS_BUCKET}/${path}`), {
    method: "POST",
    headers: { ...SB, "x-upsert": "true", "Content-Type": "video/mp4" },
    body: videoBytes,
  });
  if (!up.ok) {
    return json({ status: "failed", error: `storage upload ${up.status}` });
  }
  const videoUrl = buildSupabaseUrl(`storage/v1/object/public/${VIDEOS_BUCKET}/${path}`);

  await updateStep(body.stepId, { avatar_video_url: videoUrl, production_status: "video_generated" });
  return json({ status: "completed", videoUrl });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Only POST supported" }, 405);
  if (!HEYGEN_KEY) return json({ error: "HEYGEN_API_KEY not set" }, 500);
  if (!SERVICE_KEY) return json({ error: "SUPABASE_SERVICE_ROLE_KEY not set" }, 500);

  const body = await req.json().catch(() => null) as HeygenRequest | null;
  if (!body?.stepId || (body.action !== "generate" && body.action !== "status")) {
    return json({ error: "stepId and a valid action ('generate' | 'status') are required" }, 400);
  }

  try {
    return body.action === "generate" ? await generate(body) : await checkStatus(body);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
