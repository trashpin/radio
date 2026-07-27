// Edge Function entrypoint — HTTP-triggered (schedule/manual). Reuses the shared
// worker logic in worker.ts. Deploy: `supabase functions deploy narration-worker
// --no-verify-jwt`; see README.md.
import { drainQueue, MAX_JOBS } from "./worker.ts";

Deno.serve(async (req) => {
  let limit = MAX_JOBS;
  try {
    const body = await req.json();
    if (typeof body?.limit === "number") limit = body.limit;
  } catch (_) { /* no body */ }
  const res = await drainQueue(limit);
  return new Response(JSON.stringify(res), {
    headers: { "Content-Type": "application/json" },
  });
});
