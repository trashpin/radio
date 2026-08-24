-- Wires "The First Discovery" (migration 0062) into the new mystery/puzzle
-- layer (migration 0063): an Adventure Introduction, a fact revealed mid-
-- story, and a final puzzle that actually tests whether the player was
-- paying attention.

update public.missions set
  intro_character_name = 'Old Amos (fictional)',
  mission_brief_text = 'Find out what Amos Ritter really discovered, and why his bell still '
    'rings through Marion County''s history. Follow the trail from Ritterhoff Park to the '
    'Appleton Museum and Silver Springs -- listen closely, because what you hear along the '
    'way may be the only way to finish the story.',
  final_reveal_text = 'YOU SOLVED IT. You remembered the hand bell Amos rang every evening -- '
    'a small detail, easy to miss, that turned out to be the key to finishing his story. '
    'Your first discovery is complete.'
where id = '11111111-1111-1111-1111-111111111101';

-- The fact the player needs to remember -- revealed inside the Old World
-- narration at stop 1, asked about again at the very end.
insert into public.mission_facts (mission_id, key, label, value) values
  ('11111111-1111-1111-1111-111111111101', 'ritter_bell_object',
   'What did Amos ring every evening?', 'a hand bell')
on conflict (mission_id, key) do nothing;

update public.old_worlds
set reveals_fact_keys = array['ritter_bell_object']
where id = '11111111-1111-1111-1111-111111111121'; -- "The Founding Bell"

-- Attribute the stop-1 travel stories to the same fictional narrator as the
-- introduction, for a consistent voice through the first leg of the trip.
update public.mission_travel_stories
set speaker_name = 'Old Amos (fictional)'
where stop_id = '11111111-1111-1111-1111-111111111111';

-- The final puzzle -- shown after stop 3's Old World, before Mission
-- Complete. A simple, honest string match against what the player actually
-- heard, not an AI grader.
insert into public.mission_puzzles (
  mission_id, stop_id, type, prompt, accepted_answers, hint, success_text,
  related_fact_keys, reward_xp, sequence
) values (
  '11111111-1111-1111-1111-111111111101', null, 'memory',
  'What did Amos Ritter ring every evening to call the settlement together?',
  array['a hand bell', 'hand bell', 'bell'],
  'Something small, carried, and rung by hand.',
  'That''s right -- the hand bell that gave the park its name.',
  array['ritter_bell_object'], 50, 0
);
