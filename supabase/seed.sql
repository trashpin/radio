-- ExplorerOS — demo seed data
--
-- A small, self-consistent dataset so the app has live content out of the box:
-- destinations for Explore, a full Florida → Ocala hierarchy, and an Explorer
-- Radio station with real, publicly-hosted sample audio so the
-- GPS → Producer → Radio → audio loop actually plays.
--
-- Audio uses SoundHelix public sample tracks as placeholders for real music/
-- narration. `on conflict do nothing` makes this re-runnable.

-- Destinations (Explore list) -------------------------------------------------
insert into destinations (id, name, description, image_url, location, category, featured, distance_label) values
  ('dest_florida', 'Florida Explorer', 'Springs, trails, and coastal parks across the Sunshine State.', 'https://picsum.photos/seed/florida/900/600', 'Florida', 'park', true, null),
  ('dest_yellowstone', 'Yellowstone National Park', 'Geysers, canyons, and wildlife.', 'https://picsum.photos/seed/yellowstone/900/600', 'Wyoming, Montana, Idaho', 'park', false, null),
  ('dest_route66', 'Historic Route 66', 'The Mother Road, coast to heartland.', 'https://picsum.photos/seed/route66/900/600', 'Illinois to California', 'scenic', false, null)
on conflict (id) do nothing;

-- Parks -----------------------------------------------------------------------
insert into parks (id, destination_id, name, description, image_url, location) values
  ('park_ocala', 'dest_florida', 'Ocala National Forest', 'Springs, sand pine scrub, and paddling runs.', 'https://picsum.photos/seed/ocala/800/500', 'Ocala, Florida')
on conflict (id) do nothing;

-- Stops -----------------------------------------------------------------------
insert into stops (id, park_id, name, description, image_url, latitude, longitude, order_index) values
  ('stop_juniper', 'park_ocala', 'Juniper Springs', 'Historic recreation area and scenic run.', 'https://picsum.photos/seed/juniper/600/400', 29.183, -81.712, 1),
  ('stop_silver', 'park_ocala', 'Silver Glen Springs', 'Crystal-clear swimming spring.', 'https://picsum.photos/seed/silverglen/600/400', 29.246, -81.643, 2)
on conflict (id) do nothing;

-- Stories + narration ---------------------------------------------------------
insert into stories (id, park_id, stop_id, title, body, image_url) values
  ('story_juniper', 'park_ocala', 'stop_juniper', 'The History of Juniper Springs', 'Built by the CCC in the 1930s...', 'https://picsum.photos/seed/juniperstory/600/400')
on conflict (id) do nothing;

insert into narrations (id, story_id, stop_id, title, audio_url, duration_seconds, transcript) values
  ('narr_juniper', 'story_juniper', 'stop_juniper', 'Ranger Tale: Juniper Springs', 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3', 210, 'Welcome to Juniper Springs...')
on conflict (id) do nothing;

-- Wildlife + plants -----------------------------------------------------------
insert into wildlife (id, park_id, name, scientific_name, description, image_url) values
  ('wild_gator', 'park_ocala', 'American Alligator', 'Alligator mississippiensis', 'Keep a safe distance.', 'https://picsum.photos/seed/gator/600/400')
on conflict (id) do nothing;

insert into plants (id, park_id, name, scientific_name, description, image_url) values
  ('plant_cypress', 'park_ocala', 'Bald Cypress', 'Taxodium distichum', 'Wetland conifer with knees.', 'https://picsum.photos/seed/cypress/600/400')
on conflict (id) do nothing;

-- Radio: station, profile, rules ---------------------------------------------
insert into radio_stations (id, name, destination_id, description, image_url, stream_url) values
  ('station_explorer', 'Explorer Radio', 'dest_florida', 'Music, ranger stories, and location audio.', 'https://picsum.photos/seed/explorerradio/600/400', null)
on conflict (id) do nothing;

insert into station_profiles (id, station_id, name, description, genre, mood, target_audience, tags) values
  ('prof_explorer', 'station_explorer', 'Explorer Radio', 'The flagship ExplorerOS station.', 'Variety', 'Adventurous', 'All explorers', '{"flagship"}')
on conflict (id) do nothing;

insert into station_rules (id, station_id, station_id_every_tracks, announcement_every_tracks, story_every_tracks, allow_ambient, shuffle_music) values
  ('rule_explorer', 'station_explorer', 5, 4, 3, true, true)
on conflict (id) do nothing;

-- Songs (real sample audio) ---------------------------------------------------
insert into songs (id, station_id, title, artist, audio_url, duration_seconds) values
  ('song_1', 'station_explorer', 'Trail Opener', 'ExplorerOS', 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3', 372),
  ('song_2', 'station_explorer', 'Open Road', 'ExplorerOS', 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3', 425),
  ('song_3', 'station_explorer', 'Sunset Drive', 'ExplorerOS', 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3', 348)
on conflict (id) do nothing;

-- Announcements (station ID) --------------------------------------------------
insert into announcements (id, title, kind, station_id, audio_url, duration_seconds, interval_minutes, park_id, state, tags) values
  ('ann_stationid', 'You are listening to Explorer Radio', 'station_identification', 'station_explorer', 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3', 8, 20, null, 'FL', '{}')
on conflict (id) do nothing;

-- GPS audio trigger -----------------------------------------------------------
insert into gps_audio_triggers (id, title, latitude, longitude, radius_meters, narration_id, audio_url, duration_seconds, park_id, state, one_shot, tags) values
  ('trig_juniper', 'Approaching Juniper Springs', 29.183, -81.712, 400, 'narr_juniper', 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3', 210, 'park_ocala', 'FL', true, '{}')
on conflict (id) do nothing;

-- GPS geometry ----------------------------------------------------------------
insert into park_boundaries (id, destination_id, park_id, name, latitude, longitude, radius_meters, approach_radius_meters) values
  ('bnd_ocala', 'dest_florida', 'park_ocala', 'Ocala National Forest', 29.2, -81.8, 40000, 60000)
on conflict (id) do nothing;

insert into state_boundaries (id, code, name, min_latitude, max_latitude, min_longitude, max_longitude) values
  ('st_fl', 'FL', 'Florida', 24.5, 31.0, -87.6, -80.0)
on conflict (id) do nothing;

insert into county_boundaries (id, name, state_code, min_latitude, max_latitude, min_longitude, max_longitude) values
  ('cty_marion', 'Marion', 'FL', 28.9, 29.5, -82.3, -81.6)
on conflict (id) do nothing;
