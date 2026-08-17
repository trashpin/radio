// supabase/functions/program-next/index.ts
// Edge Function entrypoint for Program Next (Phase 1). Read-only.

import { handleProgramNext } from "./worker.ts";

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: 'Only POST supported' }), {
        status: 405,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const body = await req.json().catch(() => null);
    if (!body) {
      return new Response(JSON.stringify({ error: 'Invalid JSON' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    try {
      const res = await handleProgramNext(body);
      return new Response(JSON.stringify(res), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    } catch (err) {
      if (String(err.message).includes('invalid_location')) {
        return new Response(JSON.stringify({ error: 'invalid_location' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' },
        });
      }
      console.error('program-next handler error', err);
      return new Response(JSON.stringify({ error: 'internal_server_error' }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });
    }
  } catch (e) {
    console.error('program-next unexpected error', e);
    return new Response(JSON.stringify({ error: 'internal_server_error' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
