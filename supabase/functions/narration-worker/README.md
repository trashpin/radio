# narration-worker (Supabase Edge Function)

Drains the `generation_jobs` queue so the Narration Studio's **Generate** buttons
run server-side automatically — no API key ever touches the browser.

Handles pending jobs of these `job_type`s:

| job_type | action | result |
|---|---|---|
| `research` | OpenAI → `knowledge_base` | facts for the destination (skipped if it already has some) |
| `narration` | OpenAI → `destination_narrations` | **draft** scripts, grounded in the destination's knowledge (needs_review placeholder if none), with QC (word count, speaking time, readability, duplicate score) |
| `narration_audio` | ElevenLabs → Storage | **approved** scripts get audio → status `audio_generated` (**never publishes**) |

It is idempotent and resumable: it only generates missing script types / voices
approved-without-audio scripts, in bounded batches per run (`TYPE_CAP`,
`AUDIO_CAP`, `MAX_JOBS`), leaving a job `pending` until fully done so a repeated
schedule finishes large jobs across runs. Publishing always stays a manual admin
action.

Files: `worker.ts` holds the shared logic; `index.ts` is the Edge Function
entrypoint (`Deno.serve`); `run.ts` is a CLI batch runner used by CI.

## Easiest setup: GitHub Actions (no Supabase CLI)

`.github/workflows/narration-worker.yml` runs `run.ts` on a schedule (every 15
min) and on demand. **You only add repository secrets** — no CLI, no deploy:

1. GitHub repo → **Settings → Secrets and variables → Actions → New repository
   secret**, add: `OPENAI_API_KEY`, `ELEVENLABS_API_KEY`, `SUPABASE_SERVICE_KEY`
   (and optionally `SUPABASE_URL`).
2. Done — it runs automatically. To run it immediately: **Actions tab → Narration
   Worker → Run workflow**.

## Alternative: deploy as a Supabase Edge Function

## Deploy

```bash
# 1. Deploy (public endpoint so a schedule can call it)
supabase functions deploy narration-worker --no-verify-jwt

# 2. Set the AI keys as function secrets (SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY
#    are injected automatically).
supabase secrets set OPENAI_API_KEY=sk-... ELEVENLABS_API_KEY=...
```

## Schedule it (every minute)

Easiest: **Supabase Dashboard → Edge Functions → narration-worker → Schedules**,
cron `* * * * *`.

Or with pg_cron + pg_net (SQL editor):

```sql
create extension if not exists pg_net;
create extension if not exists pg_cron;
select cron.schedule(
  'narration-worker', '* * * * *',
  $$ select net.http_post(
       url := 'https://<PROJECT_REF>.functions.supabase.co/narration-worker',
       headers := jsonb_build_object('Content-Type','application/json'),
       body := '{}'::jsonb
     ); $$
);
```

## Manual trigger / test

```bash
curl -X POST 'https://<PROJECT_REF>.functions.supabase.co/narration-worker' \
  -H 'Content-Type: application/json' -d '{"limit":5}'
# -> {"processed":N,"jobs":[...]}
```

The endpoint only processes jobs already queued in `generation_jobs`, so the work
(and any AI cost) is bounded by what admins have queued. Add a shared-secret
header check if you want to lock the endpoint down further.
