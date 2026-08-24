-- Marion County Adventures — Phase 6 proof-of-concept: "The First Discovery."
-- 3 real stops (real, existing Ocala-area `locations` rows, real
-- coordinates) so GPS/geofence testing is meaningful. The Old World content
-- is deliberately, explicitly marked is_fictional = true — this is test
-- content for proving the DRIVE -> STORY -> ARRIVE -> QR -> OLD WORLD ->
-- NEXT STOP loop, not researched Marion County history. Real historical
-- missions come later, written from verified sources.

insert into public.missions (
  id, title, description, category, difficulty, estimated_duration_minutes,
  published, starting_location_id, opening_narration_text, completion_reward_xp,
  completion_badge
) values (
  '11111111-1111-1111-1111-111111111101',
  'The First Discovery',
  'Your first Marion County Adventure. Follow the road, listen for the stories, and see what''s waiting at each stop.',
  'history', 'easy', 45,
  true,
  'caae83c2-4175-413b-b305-f1e0c844c71a',
  'Welcome, traveler. Somewhere in Marion County, a story has been waiting a long time to be found. Start driving toward Ritterhoff Park, and let the road tell you the rest.',
  100,
  'First Discovery'
) on conflict (id) do nothing;

-- STOP 1: Ritterhoff Park (real location)
insert into public.mission_stops (
  id, mission_id, sequence, title, location_id, latitude, longitude,
  arrival_radius_meters, arrival_narration_text, requires_qr
) values (
  '11111111-1111-1111-1111-111111111111',
  '11111111-1111-1111-1111-111111111101',
  1, 'Ritterhoff Park', 'caae83c2-4175-413b-b305-f1e0c844c71a',
  29.1713753, -82.1201706, 150,
  'You''ve arrived at Ritterhoff Park. Somewhere nearby is a small marker, easy to miss unless you''re looking for it — a QR code that opens the next part of the story.',
  true
) on conflict (id) do nothing;

-- STOP 2: Appleton Museum (real location, ~4.3 mi from stop 1)
insert into public.mission_stops (
  id, mission_id, sequence, title, location_id, latitude, longitude,
  arrival_radius_meters, arrival_narration_text, requires_qr
) values (
  '11111111-1111-1111-1111-111111111112',
  '11111111-1111-1111-1111-111111111101',
  2, 'Appleton Museum', '53f9d590-6426-416f-8eb8-05e7a2abf252',
  29.20663, -82.07713, 150,
  'You''ve reached the Appleton Museum. Look around the grounds for the next marker.',
  true
) on conflict (id) do nothing;

-- STOP 3: Silver Springs State Park (real location, ~2 mi from stop 2) — final stop
insert into public.mission_stops (
  id, mission_id, sequence, title, location_id, latitude, longitude,
  arrival_radius_meters, arrival_narration_text, requires_qr
) values (
  '11111111-1111-1111-1111-111111111113',
  '11111111-1111-1111-1111-111111111101',
  3, 'Silver Springs State Park', '098b3f81-1b49-4de7-a758-475c577aa767',
  29.2178579, -82.0553756, 150,
  'You''ve arrived at Silver Springs. This is the last stop — find the final marker to finish the adventure.',
  true
) on conflict (id) do nothing;

-- Travel + approach stories per stop (mile markers configurable per spec).
insert into public.mission_travel_stories (mission_id, stop_id, trigger_type, trigger_distance_meters, text, priority) values
  ('11111111-1111-1111-1111-111111111101','11111111-1111-1111-1111-111111111111','travel', 8047,
   'Somewhere ahead, part of Ocala''s past is still waiting to be found. Keep driving — the story continues as the miles go by.', 0),
  ('11111111-1111-1111-1111-111111111101','11111111-1111-1111-1111-111111111111','travel', 4828,
   'Marion County''s parks have long been gathering places — quiet ground with more history under the surface than most people passing through ever notice.', 0),
  ('11111111-1111-1111-1111-111111111101','11111111-1111-1111-1111-111111111111','approach', 3219,
   'You are getting closer.', 0),
  ('11111111-1111-1111-1111-111111111101','11111111-1111-1111-1111-111111111111','approach', 1609,
   'Something from the past is waiting for you.', 0),
  ('11111111-1111-1111-1111-111111111101','11111111-1111-1111-1111-111111111111','approach', 152,
   'You''re very close now. When you arrive, look around.', 1),

  ('11111111-1111-1111-1111-111111111101','11111111-1111-1111-1111-111111111112','travel', 6437,
   'The road ahead leads toward a place built to hold onto things worth remembering.', 0),
  ('11111111-1111-1111-1111-111111111101','11111111-1111-1111-1111-111111111112','approach', 3219,
   'You are getting closer.', 0),
  ('11111111-1111-1111-1111-111111111101','11111111-1111-1111-1111-111111111112','approach', 1609,
   'Something from the past is waiting for you.', 0),
  ('11111111-1111-1111-1111-111111111101','11111111-1111-1111-1111-111111111112','approach', 152,
   'You''re very close now. When you arrive, look around.', 1),

  ('11111111-1111-1111-1111-111111111101','11111111-1111-1111-1111-111111111113','travel', 3219,
   'Water has always drawn people to this part of Marion County — travelers, settlers, and now you.', 0),
  ('11111111-1111-1111-1111-111111111101','11111111-1111-1111-1111-111111111113','approach', 1609,
   'Something from the past is waiting for you.', 0),
  ('11111111-1111-1111-1111-111111111101','11111111-1111-1111-1111-111111111113','approach', 152,
   'You''re very close now. This is the last stop — look around when you arrive.', 1)
on conflict do nothing;

-- Old World content — explicitly fictional test content.
insert into public.old_worlds (
  id, title, historical_period, is_fictional, narration_text, narrator_name,
  characters, clue_text, next_stop_id
) values (
  '11111111-1111-1111-1111-111111111121',
  'The Founding Bell', 'Fictional — 1880s (test content)', true,
  'This is a fictional test story, not verified history. In this telling, a traveling peddler named Amos Ritter is said to have rung a hand bell on this ground each evening to call the small settlement together — the same ground that carries his name today. Whether the story is true or simply grew in the retelling, nobody living can say for certain.',
  'Old Amos (fictional character)',
  '[{"name": "Amos Ritter", "description": "A fictional traveling peddler said to have rung the evening bell.", "image_url": null}]',
  'Look for the place where the past is kept behind glass, not far from where the road bends north.',
  '11111111-1111-1111-1111-111111111112'
) on conflict (id) do nothing;

insert into public.old_worlds (
  id, title, historical_period, is_fictional, narration_text, narrator_name,
  characters, clue_text, next_stop_id
) values (
  '11111111-1111-1111-1111-111111111122',
  'The Collector''s Secret', 'Fictional — 1930s (test content)', true,
  'This is a fictional test story, not verified history. In this telling, an early museum caretaker is said to have kept one item out of the public collection — something she believed belonged closer to the water it came from. She never told anyone exactly where she returned it.',
  'The Caretaker (fictional character)',
  '[{"name": "The Caretaker", "description": "A fictional museum caretaker with one untold secret.", "image_url": null}]',
  'Follow the water to where it rises from the ground. That is where this story ends — for now.',
  '11111111-1111-1111-1111-111111111113'
) on conflict (id) do nothing;

insert into public.old_worlds (
  id, title, historical_period, is_fictional, narration_text, narrator_name,
  characters, clue_text, next_stop_id
) values (
  '11111111-1111-1111-1111-111111111123',
  'The Source', 'Fictional (test content)', true,
  'This is a fictional test story, not verified history. Every telling of Marion County''s past seems to lead back to water, one way or another. Whatever the Caretaker returned to this spring, the spring itself has kept it — and kept its silence — ever since. Your first discovery ends here. There will be more.',
  null,
  '[]',
  null,
  null
) on conflict (id) do nothing;

-- QR portals — one physical marker per stop. `code` is the exact string an
-- admin encodes into a printed QR image (any QR generator); scanning it
-- never opens a webpage, only this game (spec Phase 4).
insert into public.qr_portals (id, code, mission_stop_id, old_world_id, is_global, requires_gps_proximity, active) values
  ('11111111-1111-1111-1111-111111111131', 'MCA-FIRSTDISCOVERY-STOP1', '11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111121', false, true, true),
  ('11111111-1111-1111-1111-111111111132', 'MCA-FIRSTDISCOVERY-STOP2', '11111111-1111-1111-1111-111111111112', '11111111-1111-1111-1111-111111111122', false, true, true),
  ('11111111-1111-1111-1111-111111111133', 'MCA-FIRSTDISCOVERY-STOP3', '11111111-1111-1111-1111-111111111113', '11111111-1111-1111-1111-111111111123', false, true, true)
on conflict (id) do nothing;

-- Link each stop to its QR portal, Old World, and the next stop in sequence.
update public.mission_stops set qr_portal_id = '11111111-1111-1111-1111-111111111131', old_world_id = '11111111-1111-1111-1111-111111111121', next_stop_id = '11111111-1111-1111-1111-111111111112' where id = '11111111-1111-1111-1111-111111111111';
update public.mission_stops set qr_portal_id = '11111111-1111-1111-1111-111111111132', old_world_id = '11111111-1111-1111-1111-111111111122', next_stop_id = '11111111-1111-1111-1111-111111111113' where id = '11111111-1111-1111-1111-111111111112';
update public.mission_stops set qr_portal_id = '11111111-1111-1111-1111-111111111133', old_world_id = '11111111-1111-1111-1111-111111111123', next_stop_id = null where id = '11111111-1111-1111-1111-111111111113';
