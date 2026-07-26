-- Give stories a playable narration URL so they can be scheduled on the radio.
-- Run in the Supabase SQL editor for project qqeyvhcgirmfokoftiuz.
alter table public.stories add column if not exists audio_url text;

-- Allow signed-in admins to write stories (needed by the admin Stories editor).
alter table public.stories enable row level security;
drop policy if exists "read_stories" on public.stories;
create policy "read_stories" on public.stories for select to anon, authenticated using (true);
drop policy if exists "write_stories" on public.stories;
create policy "write_stories" on public.stories for all to authenticated using (true) with check (true);
