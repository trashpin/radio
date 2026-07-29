-- ExplorerOS — User profiles (extends the auth profiles for the mobile app)
--
-- Builds on public.profiles (0019) with the fields the mobile app stores per
-- user: name/email/photo, subscription, favorites, trip history, achievements,
-- preferences, downloads, and settings. Idempotent.

alter table public.profiles
  add column if not exists first_name          text,
  add column if not exists last_name           text,
  add column if not exists email               text,
  add column if not exists subscription_level  text not null default 'free',
  add column if not exists favorite_parks      text[] default '{}',
  add column if not exists favorite_counties   text[] default '{}',
  add column if not exists trip_history        jsonb  default '[]'::jsonb,
  add column if not exists achievements        text[] default '{}',
  add column if not exists preferred_narrator  text,
  add column if not exists preferred_music_style text,
  add column if not exists downloaded_audio    text[] default '{}',
  add column if not exists settings            jsonb  default '{}'::jsonb;

-- Populate name/email from auth metadata when a user signs up (extends the
-- 0019 trigger function; keeps the display_name fallback).
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, first_name, last_name, display_name, avatar_url)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data ->> 'first_name',
    new.raw_user_meta_data ->> 'last_name',
    coalesce(
      nullif(new.raw_user_meta_data ->> 'full_name', ''),
      nullif(trim(concat_ws(' ',
        new.raw_user_meta_data ->> 'first_name',
        new.raw_user_meta_data ->> 'last_name')), ''),
      split_part(coalesce(new.email, 'explorer'), '@', 1)
    ),
    new.raw_user_meta_data ->> 'avatar_url'
  )
  on conflict (id) do update
    set email = excluded.email,
        first_name = coalesce(public.profiles.first_name, excluded.first_name),
        last_name  = coalesce(public.profiles.last_name, excluded.last_name);
  return new;
end $$;
