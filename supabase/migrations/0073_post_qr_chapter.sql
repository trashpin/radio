-- Marion County Adventures — the post-QR "next chapter" experience.
-- Purely additive: no existing mission/location/character record touched,
-- no GPS/geofence/QR system replaced. The existing single-active-geofence
-- transition (ActiveMissionController._completeStop) already does exactly
-- what "IMPORTANT GEOFENCE RULE" asks for -- this migration only adds the
-- content fields the post-QR screen needs to show a proper next-chapter
-- ending instead of returning straight to the map.

-- A direct back-reference to the stop an Old World belongs to. Every other
-- per-stop content table in this schema (mission_travel_stories,
-- treasure_discoveries, mission_story_steps) already stores stop_id
-- directly rather than only being pointed-to from mission_stops -- this
-- brings old_worlds in line with that convention, and is what lets the
-- post-QR screen look up "does the stop the player just completed have a
-- test-of-wits question" without needing the CURRENT stop (which has
-- already advanced to the next one by the time this screen shows).
alter table public.old_worlds
  add column if not exists stop_id uuid references public.mission_stops(id) on delete cascade;

update public.old_worlds ow
set stop_id = ms.id
from public.mission_stops ms
where ms.old_world_id = ow.id and ow.stop_id is null;

-- "YOUR NEXT OBJECTIVE" -- a short, non-spoiler teaser about what's ahead,
-- shown after the chapter (and any test-of-wits question) finishes,
-- before the existing journey map opens for the next stop. Deliberately
-- separate from clue_text (shown earlier, mid-chapter) and from the next
-- stop's own travel-story narration (which fires later, while driving).
alter table public.old_worlds
  add column if not exists next_objective_text text;
comment on column public.old_worlds.next_objective_text is
  'Short, non-spoiler teaser about what''s ahead ("YOUR NEXT OBJECTIVE"), shown once this chapter finishes and before the journey map opens for the next stop. Never reveals the destination name or route.';

create index if not exists old_worlds_stop_idx on public.old_worlds(stop_id);
