// CLI runner for CI (GitHub Actions): drains the generation_jobs queue in a few
// bounded batches and exits — same logic as the Edge Function, no deploy needed.
// Run: deno run --allow-net --allow-env supabase/functions/narration-worker/run.ts
import { drainQueue } from "./worker.ts";

const MAX_ITERS = 8; // enough for resumable jobs to finish across batches
let total = 0;
for (let i = 0; i < MAX_ITERS; i++) {
  const r = await drainQueue(4);
  total += r.processed;
  console.log(`batch ${i + 1}: processed ${r.processed}`);
  if (r.processed === 0) break;
}
console.log(`done — processed ${total} job(s) across batches`);
Deno.exit(0);
