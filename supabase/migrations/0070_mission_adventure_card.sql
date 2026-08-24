-- Marion County Adventures — visual Adventure Card redesign of the
-- Adventures page. Purely additive: no existing mission or location
-- records are touched, and none of the existing GPS/mission/trigger logic
-- changes -- this is presentation content only.

alter table public.missions
  -- The "INTRODUCTION IMAGE" -- mystery/story artwork, NOT a photo of the
  -- destination (spec: "Do NOT reveal the locations the player will
  -- visit... the image should represent the mystery"). Deliberately
  -- separate from any location's own photo and from old_worlds.hero_image_url
  -- -- reusable on both the Adventures card and the Mission Introduction
  -- screen, never auto-populated from a location record.
  add column if not exists hero_image_url text,
  -- The short, curiosity-only teaser shown on the Adventure Card itself
  -- ("WHY SHOULD I CARE?", never "WHERE AM I GOING?"). Deliberately
  -- separate from `description` (used elsewhere as a more neutral
  -- narration fallback) so this field can be held to the spec's strict
  -- no-spoiler rule without constraining how `description` is used.
  add column if not exists story_hook text,
  -- Admin-only authoring note: what the hero image secretly represents or
  -- foreshadows (spec: "the data model should eventually support an
  -- optional IMAGE CLUE field"). Never rendered to the player anywhere --
  -- purely a production reference for whoever is writing the story steps,
  -- so a later scene can deliberately pay off what the image was hinting
  -- at without the connection needing to be rediscovered from scratch.
  add column if not exists image_clue_text text;

comment on column public.missions.hero_image_url is
  'Mystery-themed introduction artwork for the Adventure Card and Mission Introduction screen -- never a photo of an actual destination, never auto-derived from a location record.';
comment on column public.missions.story_hook is
  'Short curiosity-only teaser for the Adventure Card. Must never reveal destination names, stops, route, or the answer to the mystery.';
comment on column public.missions.image_clue_text is
  'Admin-only authoring note describing what hero_image_url secretly hints at. Never shown to the player.';
