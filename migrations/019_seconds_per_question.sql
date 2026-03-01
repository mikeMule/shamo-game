-- Game rule: seconds per question (admin sets in Settings; mini-app uses for timer)
-- Default 4 seconds if not already set
INSERT INTO platform_config (key, value, description, updated_at)
VALUES (
  'seconds_per_question',
  '4',
  'Seconds allowed per question (mini-app timer). Set in Admin → Settings.',
  NOW()
)
ON CONFLICT (key) DO NOTHING;
