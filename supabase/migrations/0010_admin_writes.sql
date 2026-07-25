-- Admin write access: let signed-in admins create/edit species and upload
-- images from the deployed admin (https://.../admin/). Run in the Supabase SQL
-- editor for project qqeyvhcgirmfokoftiuz.
--
-- Security model: the browser admin signs in via Supabase Auth (role
-- `authenticated`); anonymous visitors keep read-only access. Tighten to a
-- specific admin role/allowlist later if you add more users.

-- Species: authenticated users may insert/update/delete; anon still read-only.
alter table public.species enable row level security;
drop policy if exists "species_write_authenticated" on public.species;
create policy "species_write_authenticated" on public.species
  for all to authenticated using (true) with check (true);

-- Storage: the species_images bucket is public-read (bucket flag). Allow
-- authenticated admins to upload/update/delete objects in it.
drop policy if exists "species_images_insert" on storage.objects;
create policy "species_images_insert" on storage.objects
  for insert to authenticated with check (bucket_id = 'species_images');
drop policy if exists "species_images_update" on storage.objects;
create policy "species_images_update" on storage.objects
  for update to authenticated using (bucket_id = 'species_images');
drop policy if exists "species_images_delete" on storage.objects;
create policy "species_images_delete" on storage.objects
  for delete to authenticated using (bucket_id = 'species_images');
