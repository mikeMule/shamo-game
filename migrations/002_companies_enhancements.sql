-- ═══════════════════════════════════════════════════════════════════════════════
-- Migration 002: Company enhancements
-- ═══════════════════════════════════════════════════════════════════════════════
-- Ensures logo_url, slug, and other useful columns exist on the companies table.
-- Safe to run multiple times (IF NOT EXISTS / ADD COLUMN IF NOT EXISTS).
-- ═══════════════════════════════════════════════════════════════════════════════

-- 1. Ensure logo_url column exists (already in 001 schema but add safety)
ALTER TABLE companies ADD COLUMN IF NOT EXISTS logo_url TEXT;

-- 2. Ensure slug has a unique index (some setups may have missed it)
CREATE UNIQUE INDEX IF NOT EXISTS idx_companies_slug ON companies(slug);

-- 3. Ensure primary_color has a default
ALTER TABLE companies ALTER COLUMN primary_color SET DEFAULT '#E8B84B';

-- 4. Add missing RLS policy for game_questions (public read — needed for mini-app)
ALTER TABLE game_questions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "game_questions_select" ON game_questions;
CREATE POLICY "game_questions_select" ON game_questions FOR SELECT USING (TRUE);

-- 5. Fix FK constraints that were missing ON DELETE CASCADE
-- (safe to run even if already fixed — DROP IF EXISTS + re-add)

-- qr_scans.game_id
DO $$ BEGIN
  ALTER TABLE qr_scans DROP CONSTRAINT IF EXISTS qr_scans_game_id_fkey;
  ALTER TABLE qr_scans ADD CONSTRAINT qr_scans_game_id_fkey
    FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- round_answers.user_id
DO $$ BEGIN
  ALTER TABLE round_answers DROP CONSTRAINT IF EXISTS round_answers_user_id_fkey;
  ALTER TABLE round_answers ADD CONSTRAINT round_answers_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- round_answers.game_id
DO $$ BEGIN
  ALTER TABLE round_answers DROP CONSTRAINT IF EXISTS round_answers_game_id_fkey;
  ALTER TABLE round_answers ADD CONSTRAINT round_answers_game_id_fkey
    FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- spin_results.user_id
DO $$ BEGIN
  ALTER TABLE spin_results DROP CONSTRAINT IF EXISTS spin_results_user_id_fkey;
  ALTER TABLE spin_results ADD CONSTRAINT spin_results_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- spin_results.game_id
DO $$ BEGIN
  ALTER TABLE spin_results DROP CONSTRAINT IF EXISTS spin_results_game_id_fkey;
  ALTER TABLE spin_results ADD CONSTRAINT spin_results_game_id_fkey
    FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- transactions.user_id
DO $$ BEGIN
  ALTER TABLE transactions DROP CONSTRAINT IF EXISTS transactions_user_id_fkey;
  ALTER TABLE transactions ADD CONSTRAINT transactions_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- round_answers.question_id
DO $$ BEGIN
  ALTER TABLE round_answers DROP CONSTRAINT IF EXISTS round_answers_question_id_fkey;
  ALTER TABLE round_answers ADD CONSTRAINT round_answers_question_id_fkey
    FOREIGN KEY (question_id) REFERENCES questions(id) ON DELETE CASCADE;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
