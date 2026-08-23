// DEPRECATED as of the Marion County Event Discovery Engine.
//
// This function used to write Ticketmaster events directly into
// `public.events`, bypassing review. It has been superseded by
// `marion-event-discovery`, which runs Ticketmaster (and any future source)
// through Discovery -> Verification -> Deduplication -> Admin Approval
// before anything reaches `events`. Kept as a stub (rather than left
// functional) so nothing can accidentally bypass that pipeline.
//
// Use instead: POST {SUPABASE_URL}/functions/v1/marion-event-discovery

Deno.serve(async (_req: Request) => {
  return new Response(
    JSON.stringify({
      error: "deprecated",
      message: "marion-events-import has been replaced by marion-event-discovery, " +
        "which routes Ticketmaster (and future sources) through admin review " +
        "before publishing to events. Call marion-event-discovery instead.",
    }),
    { status: 410, headers: { "Content-Type": "application/json" } },
  );
});
