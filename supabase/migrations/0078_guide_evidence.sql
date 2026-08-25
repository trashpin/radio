alter table guide_steps
  add column evidence_type text
    check (evidence_type is null or evidence_type in
      ('video','audio','photograph','document','map','object','character_recording'));

comment on column guide_steps.evidence_type is
  'Marks this step as HISTORICAL EVIDENCE delivered by an adventure character '
  '(character_id), not the Guide''s own modern presentation. Orthogonal to '
  'content_type, which still decides which UI component renders it (video/'
  'audio/image). Non-null drives the archived/period visual treatment.';
