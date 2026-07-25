-- Default voice per narration content category + custom voice labels.
-- Run in the Supabase SQL editor for project qqeyvhcgirmfokoftiuz.

create table if not exists public.voice_assignments (
  category text primary key,          -- 'wildlife' | 'birds' | ... | 'explorer_radio'
  default_voice_name text,
  default_voice_id text,
  language text not null default 'English',
  active boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.voice_assignments enable row level security;
drop policy if exists "rw_voice_assignments" on public.voice_assignments;
create policy "rw_voice_assignments" on public.voice_assignments
  for all to anon, authenticated using (true) with check (true);

-- Admin-editable friendly labels for ElevenLabs voices (e.g. "Ranger Jack").
create table if not exists public.voice_labels (
  voice_id text primary key,
  label text not null,
  updated_at timestamptz not null default now()
);
alter table public.voice_labels enable row level security;
drop policy if exists "rw_voice_labels" on public.voice_labels;
create policy "rw_voice_labels" on public.voice_labels
  for all to anon, authenticated using (true) with check (true);

-- Track when a narration's audio was generated.
alter table public.narrations
  add column if not exists generated_at timestamptz;
