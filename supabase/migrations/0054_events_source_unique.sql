-- Enables a safe upsert for external event imports (e.g. marion-events-import)
-- keyed by (source, source_id) — re-running an import updates existing rows
-- instead of duplicating them. NULLs (all manually-created events today)
-- never conflict with each other under a standard unique constraint, so
-- this is purely additive and touches no existing row.
alter table public.events
  add constraint events_source_source_id_unique unique (source, source_id);
