-- The discovery engine has always upserted discovered_events on
-- (source_id, source_event_id) (see marion-event-discovery/index.ts), but
-- 0055 only created a PARTIAL unique index for that pair (excluding rows
-- with a null source_event_id). Postgres will not use a partial index as
-- an ON CONFLICT arbiter unless the conflict clause repeats its exact WHERE
-- predicate, which PostgREST's `on_conflict=` query param cannot express --
-- so every non-dry-run discovery write has been failing with 42P10
-- ("no unique or exclusion constraint matching the ON CONFLICT
-- specification"). This adds the plain (non-partial) constraint the code
-- has been asking for since 0055.
alter table discovered_events
  add constraint discovered_events_source_event_unique unique (source_id, source_event_id);
