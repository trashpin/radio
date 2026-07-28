-- ExplorerOS — Audio Recall System
--
-- Makes `audio_assets` the canonical audio index so ExplorerOS never loses
-- track of a file. Adds the recall fields the Audio Recall System needs. The
-- unified cross-catalog inventory (songs, dj_banter_clips, radio_segments,
-- destination_narrations, story_library, media) is assembled read-only in the
-- app, so NO existing catalog is changed or duplicated.
--
-- Idempotent: safe to re-run.

alter table public.audio_assets
  add column if not exists title       text,
  add column if not exists used_by     text[] default '{}',
  add column if not exists play_count   integer not null default 0,
  add column if not exists tags        text[] default '{}',
  add column if not exists last_used    timestamptz;

create index if not exists audio_assets_tags_idx
  on public.audio_assets using gin (tags);

-- Records a play: increments the counter, stamps last_used, and (optionally)
-- remembers which system used it — without ever overwriting existing content.
create or replace function public.audio_asset_record_play(
  p_id uuid,
  p_used_by text default null
) returns void language plpgsql as $$
begin
  update public.audio_assets
     set play_count = coalesce(play_count, 0) + 1,
         last_used  = now(),
         used_by    = case
                        when p_used_by is null then used_by
                        when p_used_by = any(coalesce(used_by, '{}')) then used_by
                        else array_append(coalesce(used_by, '{}'), p_used_by)
                      end
   where id = p_id;
end $$;
