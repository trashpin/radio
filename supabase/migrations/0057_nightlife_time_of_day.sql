-- Nightlife/evening-entertainment expansion of the event system.
--
-- time_of_day is derived from the event's OWN start/end time -- never
-- assumed from category (spec: "A 2 PM concert should not automatically
-- be classified as nightlife"). experience_tags are descriptive-only
-- (comedy/karaoke/dancing/date_night/etc.) and are DELIBERATELY separate
-- from interest_tags: interest_tags must only ever contain tokens from the
-- fixed 22-item Discover interest taxonomy (what a user can actually pick
-- and what the matching/notification engine intersects against), while
-- experience_tags is a richer, admin/display-facing vocabulary that isn't
-- constrained to that list. Keeping them separate means experience tagging
-- can grow freely without ever silently breaking personalization matching.
alter table public.events
  add column if not exists time_of_day text
    check (time_of_day is null or time_of_day in ('morning','afternoon','evening','late_night','all_day')),
  add column if not exists experience_tags text[] not null default '{}';

alter table public.discovered_events
  add column if not exists time_of_day text
    check (time_of_day is null or time_of_day in ('morning','afternoon','evening','late_night','all_day')),
  add column if not exists experience_tags text[] not null default '{}';

create index if not exists events_time_of_day_idx on public.events(time_of_day);
