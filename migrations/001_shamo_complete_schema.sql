CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN CREATE TYPE user_role AS ENUM ('player','company','admin'); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'game_status') THEN CREATE TYPE game_status AS ENUM ('draft','scheduled','active','ended','cancelled'); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'question_status') THEN CREATE TYPE question_status AS ENUM ('pending','approved','rejected'); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'answer_status') THEN CREATE TYPE answer_status AS ENUM ('correct','wrong','timeout'); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'withdrawal_status') THEN CREATE TYPE withdrawal_status AS ENUM ('pending','processing','completed','failed','cancelled'); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'company_status') THEN CREATE TYPE company_status AS ENUM ('pending','active','suspended'); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'qr_status') THEN CREATE TYPE qr_status AS ENUM ('active','revoked','expired'); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'deposit_status') THEN CREATE TYPE deposit_status AS ENUM ('pending','confirmed','rejected'); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'tx_type') THEN CREATE TYPE tx_type AS ENUM ('game_win','withdrawal_request','withdrawal_complete','withdrawal_failed','admin_credit','admin_debit','company_credit','platform_fee','withdrawal_fee'); END IF;
END $$;

CREATE TABLE IF NOT EXISTS users (
  id                UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  telegram_id       BIGINT        UNIQUE NOT NULL,
  telegram_username VARCHAR(64),
  first_name        VARCHAR(64)   NOT NULL,
  last_name         VARCHAR(64),
  phone_number      VARCHAR(20),
  photo_url         TEXT,
  role              user_role     NOT NULL DEFAULT 'player',
  is_active         BOOLEAN       NOT NULL DEFAULT TRUE,
  is_banned         BOOLEAN       NOT NULL DEFAULT FALSE,
  ban_reason        TEXT,
  language_code     VARCHAR(10)   DEFAULT 'en',
  balance           NUMERIC(10,2) NOT NULL DEFAULT 0.00,
  total_earned      NUMERIC(10,2) NOT NULL DEFAULT 0.00,
  total_withdrawn   NUMERIC(10,2) NOT NULL DEFAULT 0.00,
  games_played      INTEGER       NOT NULL DEFAULT 0,
  games_won         INTEGER       NOT NULL DEFAULT 0,
  current_streak    INTEGER       NOT NULL DEFAULT 0,
  best_streak       INTEGER       NOT NULL DEFAULT 0,
  correct_answers   INTEGER       NOT NULL DEFAULT 0,
  wrong_answers     INTEGER       NOT NULL DEFAULT 0,
  last_game_date    DATE,
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

ALTER TABLE users ADD COLUMN IF NOT EXISTS phone_number    VARCHAR(20);
ALTER TABLE users ADD COLUMN IF NOT EXISTS photo_url       TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS correct_answers INTEGER NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS wrong_answers   INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_users_telegram_id ON users(telegram_id);
CREATE INDEX IF NOT EXISTS idx_users_phone       ON users(phone_number);
CREATE INDEX IF NOT EXISTS idx_users_role        ON users(role);
CREATE INDEX IF NOT EXISTS idx_users_balance     ON users(balance DESC);

CREATE TABLE IF NOT EXISTS companies (
  id             UUID           PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner_id       UUID           NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name           VARCHAR(120)   NOT NULL,
  slug           VARCHAR(80)    UNIQUE NOT NULL,
  logo_url       TEXT,
  website        TEXT,
  description    TEXT,
  category       VARCHAR(60),
  contact_email  VARCHAR(120),
  contact_phone  VARCHAR(20),
  status         company_status NOT NULL DEFAULT 'pending',
  credit_balance NUMERIC(10,2)  NOT NULL DEFAULT 0.00,
  total_spent    NUMERIC(10,2)  NOT NULL DEFAULT 0.00,
  primary_color  VARCHAR(7)     DEFAULT '#E8B84B',
  verified_at    TIMESTAMPTZ,
  created_at     TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_companies_owner  ON companies(owner_id);
CREATE INDEX IF NOT EXISTS idx_companies_status ON companies(status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_companies_slug ON companies(slug);

CREATE TABLE IF NOT EXISTS company_deposits (
  id              UUID           PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id      UUID           NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  game_id         UUID,
  amount_etb      NUMERIC(10,2)  NOT NULL CHECK (amount_etb > 0),
  commission_pct  NUMERIC(5,2)   NOT NULL DEFAULT 15.00,
  commission_etb  NUMERIC(10,2)  NOT NULL DEFAULT 0.00,
  prize_pool_etb  NUMERIC(10,2)  NOT NULL DEFAULT 0.00,
  status          deposit_status NOT NULL DEFAULT 'pending',
  payment_method  VARCHAR(40)    DEFAULT 'chapa',
  payment_proof   TEXT,
  chapa_reference VARCHAR(120),
  confirmed_by    UUID           REFERENCES users(id),
  confirmed_at    TIMESTAMPTZ,
  rejected_reason TEXT,
  notes           TEXT,
  created_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_deposits_company ON company_deposits(company_id);
CREATE INDEX IF NOT EXISTS idx_deposits_status  ON company_deposits(status);
CREATE INDEX IF NOT EXISTS idx_deposits_game    ON company_deposits(game_id);

CREATE TABLE IF NOT EXISTS questions (
  id              UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id      UUID            REFERENCES companies(id) ON DELETE CASCADE,
  created_by      UUID            NOT NULL REFERENCES users(id),
  status          question_status NOT NULL DEFAULT 'pending',
  icon            VARCHAR(10)     NOT NULL DEFAULT '🇪🇹',
  question_text   TEXT            NOT NULL,
  category        VARCHAR(60),
  explanation     TEXT,
  is_sponsored    BOOLEAN         NOT NULL DEFAULT FALSE,
  times_shown     INTEGER         NOT NULL DEFAULT 0,
  times_correct   INTEGER         NOT NULL DEFAULT 0,
  times_wrong     INTEGER         NOT NULL DEFAULT 0,
  rejected_reason TEXT,
  reviewed_by     UUID            REFERENCES users(id),
  reviewed_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_questions_status  ON questions(status);
CREATE INDEX IF NOT EXISTS idx_questions_company ON questions(company_id);

CREATE TABLE IF NOT EXISTS answer_options (
  id            UUID     PRIMARY KEY DEFAULT uuid_generate_v4(),
  question_id   UUID     NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
  option_letter CHAR(1)  NOT NULL CHECK (option_letter IN ('A','B','C','D')),
  option_text   TEXT     NOT NULL,
  is_correct    BOOLEAN  NOT NULL DEFAULT FALSE,
  sort_order    SMALLINT NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_answer_options_question ON answer_options(question_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_answer_options_unique ON answer_options(question_id, option_letter);

CREATE TABLE IF NOT EXISTS games (
  id                   UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id           UUID         REFERENCES companies(id) ON DELETE SET NULL,
  created_by           UUID         NOT NULL REFERENCES users(id),
  deposit_id           UUID,
  title                VARCHAR(120) NOT NULL DEFAULT 'Tonight''s SHAMO',
  description          TEXT,
  status               game_status  NOT NULL DEFAULT 'draft',
  starts_at            TIMESTAMPTZ  NOT NULL,
  ends_at              TIMESTAMPTZ  NOT NULL,
  game_date            DATE         NOT NULL,
  prize_pool_etb       NUMERIC(10,2) NOT NULL DEFAULT 0.00,
  prize_pool_remaining NUMERIC(10,2) NOT NULL DEFAULT 0.00,
  platform_fee_pct     NUMERIC(5,2)  NOT NULL DEFAULT 15.00,
  platform_fee_etb     NUMERIC(10,2) NOT NULL DEFAULT 0.00,
  usd_to_etb_rate      NUMERIC(8,2)  NOT NULL DEFAULT 57.00,
  max_prize_etb        NUMERIC(10,2) NOT NULL DEFAULT 5700.00,
  player_cap_pct       NUMERIC(5,2)  NOT NULL DEFAULT 30.00,
  total_players        INTEGER       NOT NULL DEFAULT 0,
  total_winners        INTEGER       NOT NULL DEFAULT 0,
  total_paid_out       NUMERIC(10,2) NOT NULL DEFAULT 0.00,
  created_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

ALTER TABLE games ADD COLUMN IF NOT EXISTS deposit_id            UUID;
ALTER TABLE games ADD COLUMN IF NOT EXISTS prize_pool_etb        NUMERIC(10,2) NOT NULL DEFAULT 0.00;
ALTER TABLE games ADD COLUMN IF NOT EXISTS prize_pool_remaining  NUMERIC(10,2) NOT NULL DEFAULT 0.00;
ALTER TABLE games ADD COLUMN IF NOT EXISTS platform_fee_etb      NUMERIC(10,2) NOT NULL DEFAULT 0.00;
ALTER TABLE games ADD COLUMN IF NOT EXISTS usd_to_etb_rate       NUMERIC(8,2)  NOT NULL DEFAULT 57.00;
ALTER TABLE games ADD COLUMN IF NOT EXISTS max_prize_etb         NUMERIC(10,2) NOT NULL DEFAULT 5700.00;
ALTER TABLE games ADD COLUMN IF NOT EXISTS player_cap_pct        NUMERIC(5,2)  NOT NULL DEFAULT 30.00;

CREATE INDEX IF NOT EXISTS idx_games_status  ON games(status);
CREATE INDEX IF NOT EXISTS idx_games_company ON games(company_id);
CREATE INDEX IF NOT EXISTS idx_games_date    ON games(game_date);

CREATE TABLE IF NOT EXISTS game_questions (
  id          UUID     PRIMARY KEY DEFAULT uuid_generate_v4(),
  game_id     UUID     NOT NULL REFERENCES games(id) ON DELETE CASCADE,
  question_id UUID     NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
  sort_order  SMALLINT NOT NULL DEFAULT 0
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_game_questions_unique ON game_questions(game_id, question_id);
CREATE INDEX IF NOT EXISTS idx_game_questions_game ON game_questions(game_id);

CREATE TABLE IF NOT EXISTS qr_codes (
  id         UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  token      TEXT        UNIQUE NOT NULL,
  game_id    UUID        NOT NULL REFERENCES games(id) ON DELETE CASCADE,
  company_id UUID        REFERENCES companies(id) ON DELETE SET NULL,
  created_by UUID        NOT NULL REFERENCES users(id),
  label      TEXT,
  qr_url     TEXT        NOT NULL,
  base_url   TEXT        NOT NULL,
  status     qr_status   NOT NULL DEFAULT 'active',
  scan_count INTEGER     NOT NULL DEFAULT 0,
  max_scans  INTEGER     NOT NULL DEFAULT 0,
  expires_at TIMESTAMPTZ,
  revoked_by UUID        REFERENCES users(id),
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_qr_codes_token   ON qr_codes(token);
CREATE INDEX IF NOT EXISTS idx_qr_codes_game    ON qr_codes(game_id);
CREATE INDEX IF NOT EXISTS idx_qr_codes_company ON qr_codes(company_id);
CREATE INDEX IF NOT EXISTS idx_qr_codes_status  ON qr_codes(status);

CREATE TABLE IF NOT EXISTS qr_scans (
  id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  qr_code_id   UUID        NOT NULL REFERENCES qr_codes(id) ON DELETE CASCADE,
  qr_token     TEXT        NOT NULL,
  game_id      UUID        NOT NULL REFERENCES games(id),
  user_id      UUID        REFERENCES users(id),
  telegram_id  BIGINT,
  phone_number VARCHAR(20),
  entry_status VARCHAR(20) NOT NULL DEFAULT 'entered',
  block_reason TEXT,
  scanned_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_qr_scans_qr_code ON qr_scans(qr_code_id);
CREATE INDEX IF NOT EXISTS idx_qr_scans_user    ON qr_scans(user_id);
CREATE INDEX IF NOT EXISTS idx_qr_scans_game    ON qr_scans(game_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_qr_scans_once ON qr_scans(game_id, phone_number);

CREATE TABLE IF NOT EXISTS game_sessions (
  id                 UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
  game_id            UUID         NOT NULL REFERENCES games(id) ON DELETE CASCADE,
  user_id            UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  qr_code_id         UUID         REFERENCES qr_codes(id),
  current_question   SMALLINT     NOT NULL DEFAULT 1,
  questions_answered SMALLINT     NOT NULL DEFAULT 0,
  wrong_count        SMALLINT     NOT NULL DEFAULT 0,
  is_active          BOOLEAN      NOT NULL DEFAULT TRUE,
  is_completed       BOOLEAN      NOT NULL DEFAULT FALSE,
  cooldown_until     TIMESTAMPTZ,
  total_earned       NUMERIC(8,2) NOT NULL DEFAULT 0.00,
  player_cap_etb     NUMERIC(8,2) NOT NULL DEFAULT 0.00,
  ended_at           TIMESTAMPTZ,
  started_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

ALTER TABLE game_sessions ADD COLUMN IF NOT EXISTS qr_code_id         UUID        REFERENCES qr_codes(id);
ALTER TABLE game_sessions ADD COLUMN IF NOT EXISTS current_question   SMALLINT    NOT NULL DEFAULT 1;
ALTER TABLE game_sessions ADD COLUMN IF NOT EXISTS questions_answered SMALLINT    NOT NULL DEFAULT 0;
ALTER TABLE game_sessions ADD COLUMN IF NOT EXISTS wrong_count        SMALLINT    NOT NULL DEFAULT 0;
ALTER TABLE game_sessions ADD COLUMN IF NOT EXISTS cooldown_until     TIMESTAMPTZ;
ALTER TABLE game_sessions ADD COLUMN IF NOT EXISTS player_cap_etb     NUMERIC(8,2) NOT NULL DEFAULT 0.00;

CREATE UNIQUE INDEX IF NOT EXISTS idx_sessions_user_game ON game_sessions(user_id, game_id);
CREATE INDEX IF NOT EXISTS idx_sessions_game   ON game_sessions(game_id);
CREATE INDEX IF NOT EXISTS idx_sessions_active ON game_sessions(is_active) WHERE is_active = TRUE;

CREATE TABLE IF NOT EXISTS round_answers (
  id                 UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id         UUID          NOT NULL REFERENCES game_sessions(id) ON DELETE CASCADE,
  user_id            UUID          NOT NULL REFERENCES users(id),
  game_id            UUID          NOT NULL REFERENCES games(id),
  question_id        UUID          NOT NULL REFERENCES questions(id),
  question_number    SMALLINT      NOT NULL,
  selected_option_id UUID          REFERENCES answer_options(id),
  is_correct         BOOLEAN       NOT NULL DEFAULT FALSE,
  status             answer_status NOT NULL DEFAULT 'timeout',
  time_taken_ms      INTEGER,
  answered_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_round_answers_session  ON round_answers(session_id);
CREATE INDEX IF NOT EXISTS idx_round_answers_user     ON round_answers(user_id);
CREATE INDEX IF NOT EXISTS idx_round_answers_question ON round_answers(question_id);

CREATE TABLE IF NOT EXISTS spin_results (
  id              UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id      UUID         NOT NULL REFERENCES game_sessions(id) ON DELETE CASCADE,
  user_id         UUID         NOT NULL REFERENCES users(id),
  game_id         UUID         NOT NULL REFERENCES games(id),
  question_number SMALLINT     NOT NULL,
  segment_label   VARCHAR(20)  NOT NULL,
  amount_etb      NUMERIC(8,2) NOT NULL,
  spun_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_spin_results_unique ON spin_results(session_id, question_number);
CREATE INDEX IF NOT EXISTS idx_spin_results_user ON spin_results(user_id);
CREATE INDEX IF NOT EXISTS idx_spin_results_game ON spin_results(game_id);

CREATE TABLE IF NOT EXISTS leaderboard (
  id                UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
  game_id           UUID         NOT NULL REFERENCES games(id) ON DELETE CASCADE,
  user_id           UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  rank              INTEGER      NOT NULL,
  total_earned      NUMERIC(8,2) NOT NULL DEFAULT 0.00,
  questions_correct SMALLINT     NOT NULL DEFAULT 0,
  total_time_ms     INTEGER      NOT NULL DEFAULT 0,
  updated_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_leaderboard_user_game ON leaderboard(game_id, user_id);
CREATE INDEX IF NOT EXISTS idx_leaderboard_rank ON leaderboard(game_id, rank);

CREATE TABLE IF NOT EXISTS withdrawals (
  id               UUID              PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id          UUID              NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount_requested NUMERIC(10,2)     NOT NULL DEFAULT 0.00,
  fee_pct          NUMERIC(5,2)      NOT NULL DEFAULT 5.00,
  fee_etb          NUMERIC(10,2)     NOT NULL DEFAULT 0.00,
  amount_paid      NUMERIC(10,2)     NOT NULL DEFAULT 0.00,
  status           withdrawal_status NOT NULL DEFAULT 'pending',
  phone_number     VARCHAR(20),
  bank_account     VARCHAR(40),
  chapa_reference  VARCHAR(120)      UNIQUE,
  chapa_response   JSONB,
  processed_by     UUID              REFERENCES users(id),
  processed_at     TIMESTAMPTZ,
  failure_reason   TEXT,
  notes            TEXT,
  requested_at     TIMESTAMPTZ       NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ       NOT NULL DEFAULT NOW()
);

ALTER TABLE withdrawals ADD COLUMN IF NOT EXISTS amount_requested NUMERIC(10,2) NOT NULL DEFAULT 0.00;
ALTER TABLE withdrawals ADD COLUMN IF NOT EXISTS fee_pct          NUMERIC(5,2)  NOT NULL DEFAULT 5.00;
ALTER TABLE withdrawals ADD COLUMN IF NOT EXISTS fee_etb          NUMERIC(10,2) NOT NULL DEFAULT 0.00;
ALTER TABLE withdrawals ADD COLUMN IF NOT EXISTS amount_paid      NUMERIC(10,2) NOT NULL DEFAULT 0.00;

CREATE INDEX IF NOT EXISTS idx_withdrawals_user   ON withdrawals(user_id);
CREATE INDEX IF NOT EXISTS idx_withdrawals_status ON withdrawals(status);

CREATE TABLE IF NOT EXISTS transactions (
  id             UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id        UUID          NOT NULL REFERENCES users(id),
  type           tx_type       NOT NULL,
  amount         NUMERIC(10,2) NOT NULL,
  balance_before NUMERIC(10,2) NOT NULL,
  balance_after  NUMERIC(10,2) NOT NULL,
  reference_id   UUID,
  reference_type VARCHAR(40),
  description    TEXT,
  metadata       JSONB,
  created_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_transactions_user ON transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_transactions_type ON transactions(type);
CREATE INDEX IF NOT EXISTS idx_transactions_ref  ON transactions(reference_id);

CREATE TABLE IF NOT EXISTS notifications (
  id         UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id    UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type       VARCHAR(40)  NOT NULL,
  title      VARCHAR(120) NOT NULL,
  body       TEXT         NOT NULL,
  is_read    BOOLEAN      NOT NULL DEFAULT FALSE,
  data       JSONB,
  created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notifications_user   ON notifications(user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_unread ON notifications(user_id) WHERE is_read = FALSE;

CREATE TABLE IF NOT EXISTS platform_config (
  key        VARCHAR(80) PRIMARY KEY,
  value      JSONB       NOT NULL,
  description TEXT,
  updated_by UUID        REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO platform_config (key, value, description) VALUES
  ('commission_pct',     '15',    'Company deposit commission %'),
  ('withdrawal_fee_pct', '5',     'Player withdrawal fee %'),
  ('min_withdrawal_etb', '50',    'Minimum withdrawal in ETB'),
  ('player_cap_pct',     '30',    'Max % of prize pool one player can win'),
  ('cooldown_hours',     '2',     'Hours to wait after 3 wrong answers'),
  ('max_wrong_answers',  '3',     'Wrong answers before cooldown'),
  ('usd_to_etb_rate',    '57',    'Exchange rate used across platform'),
  ('questions_per_game', '10',    'Questions a company must submit'),
  ('maintenance_mode',   'false', 'Disable platform for maintenance')
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS audit_log (
  id         BIGSERIAL   PRIMARY KEY,
  actor_id   UUID        REFERENCES users(id),
  action     VARCHAR(80) NOT NULL,
  table_name VARCHAR(60),
  record_id  UUID,
  old_data   JSONB,
  new_data   JSONB,
  ip_address INET,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_log_actor ON audit_log(actor_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_table ON audit_log(table_name, record_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_time  ON audit_log(created_at DESC);

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['users','companies','company_deposits','games','game_sessions','questions','withdrawals','qr_codes'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_updated_at' AND tgrelid = t::regclass) THEN
      EXECUTE format('CREATE TRIGGER trg_updated_at BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION set_updated_at()', t);
    END IF;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION check_single_correct_answer()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.is_correct = TRUE THEN
    IF EXISTS (SELECT 1 FROM answer_options WHERE question_id = NEW.question_id AND is_correct = TRUE AND id != NEW.id) THEN
      RAISE EXCEPTION 'Question % already has a correct answer', NEW.question_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_single_correct_answer ON answer_options;
CREATE TRIGGER trg_single_correct_answer
  BEFORE INSERT OR UPDATE ON answer_options
  FOR EACH ROW EXECUTE FUNCTION check_single_correct_answer();

CREATE OR REPLACE FUNCTION on_spin_result_insert()
RETURNS TRIGGER AS $$
DECLARE
  v_bal_before NUMERIC(10,2);
  v_bal_after  NUMERIC(10,2);
BEGIN
  SELECT balance INTO v_bal_before FROM users WHERE id = NEW.user_id;
  v_bal_after := v_bal_before + NEW.amount_etb;
  UPDATE users SET balance = balance + NEW.amount_etb, total_earned = total_earned + NEW.amount_etb, updated_at = NOW() WHERE id = NEW.user_id;
  UPDATE game_sessions SET total_earned = total_earned + NEW.amount_etb, updated_at = NOW() WHERE id = NEW.session_id;
  UPDATE games SET prize_pool_remaining = prize_pool_remaining - NEW.amount_etb, total_paid_out = total_paid_out + NEW.amount_etb, updated_at = NOW() WHERE id = NEW.game_id;
  INSERT INTO transactions (user_id, type, amount, balance_before, balance_after, reference_id, reference_type, description)
  VALUES (NEW.user_id, 'game_win', NEW.amount_etb, v_bal_before, v_bal_after, NEW.session_id, 'game_session', 'Q' || NEW.question_number || ' spin — ' || NEW.segment_label);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_on_spin_insert ON spin_results;
CREATE TRIGGER trg_on_spin_insert
  AFTER INSERT ON spin_results
  FOR EACH ROW EXECUTE FUNCTION on_spin_result_insert();

CREATE OR REPLACE FUNCTION on_session_end()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.is_active = FALSE AND OLD.is_active = TRUE THEN
    UPDATE users SET
      games_played   = games_played + 1,
      games_won      = games_won + CASE WHEN NEW.total_earned > 0 THEN 1 ELSE 0 END,
      current_streak = CASE WHEN NEW.total_earned > 0 THEN current_streak + 1 ELSE 0 END,
      best_streak    = GREATEST(best_streak, CASE WHEN NEW.total_earned > 0 THEN current_streak + 1 ELSE current_streak END),
      last_game_date = CURRENT_DATE,
      updated_at     = NOW()
    WHERE id = NEW.user_id;
    UPDATE games SET total_players = total_players + 1, total_winners = total_winners + CASE WHEN NEW.total_earned > 0 THEN 1 ELSE 0 END, updated_at = NOW() WHERE id = NEW.game_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_on_session_end ON game_sessions;
CREATE TRIGGER trg_on_session_end
  AFTER UPDATE ON game_sessions
  FOR EACH ROW EXECUTE FUNCTION on_session_end();

CREATE OR REPLACE FUNCTION on_round_answer_insert()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE questions SET
    times_shown   = times_shown + 1,
    times_correct = times_correct + CASE WHEN NEW.is_correct THEN 1 ELSE 0 END,
    times_wrong   = times_wrong   + CASE WHEN NOT NEW.is_correct AND NEW.status != 'timeout' THEN 1 ELSE 0 END,
    updated_at    = NOW()
  WHERE id = NEW.question_id;
  UPDATE users SET
    correct_answers = correct_answers + CASE WHEN NEW.is_correct THEN 1 ELSE 0 END,
    wrong_answers   = wrong_answers   + CASE WHEN NOT NEW.is_correct THEN 1 ELSE 0 END,
    updated_at      = NOW()
  WHERE id = NEW.user_id;
  IF NOT NEW.is_correct THEN
    UPDATE game_sessions SET
      wrong_count    = wrong_count + 1,
      cooldown_until = CASE WHEN wrong_count + 1 >= 3 THEN NOW() + INTERVAL '2 hours' ELSE cooldown_until END,
      is_active      = CASE WHEN wrong_count + 1 >= 3 THEN FALSE ELSE is_active END,
      updated_at     = NOW()
    WHERE id = NEW.session_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_on_round_answer ON round_answers;
CREATE TRIGGER trg_on_round_answer
  AFTER INSERT ON round_answers
  FOR EACH ROW EXECUTE FUNCTION on_round_answer_insert();

CREATE OR REPLACE FUNCTION on_withdrawal_status_change()
RETURNS TRIGGER AS $$
DECLARE
  v_bal_before NUMERIC(10,2);
  v_bal_after  NUMERIC(10,2);
BEGIN
  IF NEW.status = 'processing' AND OLD.status = 'pending' THEN
    SELECT balance INTO v_bal_before FROM users WHERE id = NEW.user_id;
    IF v_bal_before < NEW.amount_requested THEN RAISE EXCEPTION 'Insufficient balance'; END IF;
    v_bal_after := v_bal_before - NEW.amount_requested;
    UPDATE users SET balance = balance - NEW.amount_requested, total_withdrawn = total_withdrawn + NEW.amount_paid, updated_at = NOW() WHERE id = NEW.user_id;
    INSERT INTO transactions (user_id, type, amount, balance_before, balance_after, reference_id, reference_type, description)
    VALUES (NEW.user_id, 'withdrawal_request', -NEW.amount_requested, v_bal_before, v_bal_after, NEW.id, 'withdrawal', 'Withdrawal — fee: ' || NEW.fee_etb || ' ETB');
  ELSIF NEW.status = 'failed' AND OLD.status IN ('pending','processing') THEN
    SELECT balance INTO v_bal_before FROM users WHERE id = NEW.user_id;
    v_bal_after := v_bal_before + NEW.amount_requested;
    UPDATE users SET balance = balance + NEW.amount_requested, total_withdrawn = total_withdrawn - NEW.amount_paid, updated_at = NOW() WHERE id = NEW.user_id;
    INSERT INTO transactions (user_id, type, amount, balance_before, balance_after, reference_id, reference_type, description)
    VALUES (NEW.user_id, 'withdrawal_failed', NEW.amount_requested, v_bal_before, v_bal_after, NEW.id, 'withdrawal', 'Withdrawal failed — ' || COALESCE(NEW.failure_reason, 'unknown'));
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_withdrawal_status ON withdrawals;
CREATE TRIGGER trg_withdrawal_status
  AFTER UPDATE ON withdrawals
  FOR EACH ROW EXECUTE FUNCTION on_withdrawal_status_change();

CREATE OR REPLACE FUNCTION on_deposit_confirmed()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'confirmed' AND OLD.status = 'pending' THEN
    NEW.commission_etb := ROUND(NEW.amount_etb * NEW.commission_pct / 100, 2);
    NEW.prize_pool_etb := NEW.amount_etb - NEW.commission_etb;
    NEW.confirmed_at   := NOW();
    IF NEW.game_id IS NOT NULL THEN
      UPDATE games SET prize_pool_etb = NEW.prize_pool_etb, prize_pool_remaining = NEW.prize_pool_etb, platform_fee_etb = NEW.commission_etb, updated_at = NOW() WHERE id = NEW.game_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_on_deposit_confirmed ON company_deposits;
CREATE TRIGGER trg_on_deposit_confirmed
  BEFORE UPDATE ON company_deposits
  FOR EACH ROW EXECUTE FUNCTION on_deposit_confirmed();

CREATE OR REPLACE FUNCTION on_qr_scan_insert()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE qr_codes SET scan_count = scan_count + 1, updated_at = NOW() WHERE id = NEW.qr_code_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_on_qr_scan ON qr_scans;
CREATE TRIGGER trg_on_qr_scan
  AFTER INSERT ON qr_scans
  FOR EACH ROW EXECUTE FUNCTION on_qr_scan_insert();

CREATE OR REPLACE VIEW v_active_game AS
SELECT g.*, c.name AS company_name, c.logo_url AS company_logo,
  (SELECT COUNT(*) FROM game_questions gq WHERE gq.game_id = g.id) AS question_count
FROM games g LEFT JOIN companies c ON g.company_id = c.id
WHERE g.status = 'active' AND g.starts_at <= NOW() AND g.ends_at >= NOW();

CREATE OR REPLACE VIEW v_user_profile AS
SELECT u.id, u.telegram_id, u.telegram_username, u.first_name, u.last_name,
  u.first_name || COALESCE(' ' || u.last_name, '') AS full_name,
  u.phone_number, u.photo_url, u.role, u.balance, u.total_earned, u.total_withdrawn,
  u.games_played, u.games_won, u.current_streak, u.best_streak, u.correct_answers, u.wrong_answers,
  CASE WHEN u.games_played > 0 THEN ROUND((u.games_won::NUMERIC / u.games_played) * 100, 1) ELSE 0 END AS win_rate_pct,
  u.last_game_date, u.created_at
FROM users u WHERE u.is_active = TRUE AND u.is_banned = FALSE;

CREATE OR REPLACE VIEW v_alltime_leaderboard AS
SELECT u.telegram_username, u.first_name || COALESCE(' ' || u.last_name, '') AS full_name,
  u.total_earned, u.games_won, u.games_played, u.best_streak,
  RANK() OVER (ORDER BY u.total_earned DESC) AS rank
FROM users u WHERE u.is_active = TRUE AND u.games_played > 0
ORDER BY u.total_earned DESC LIMIT 100;

CREATE OR REPLACE VIEW v_recent_claims AS
SELECT u.first_name || ' ' || COALESCE(LEFT(u.last_name,1) || '.', '') AS display_name,
  sr.amount_etb, sr.segment_label, sr.question_number, sr.spun_at,
  g.title AS game_title, c.name AS company_name
FROM spin_results sr
JOIN users u ON sr.user_id = u.id
JOIN games g ON sr.game_id = g.id
LEFT JOIN companies c ON g.company_id = c.id
WHERE sr.spun_at >= NOW() - INTERVAL '24 hours'
ORDER BY sr.spun_at DESC LIMIT 50;

CREATE OR REPLACE VIEW v_company_game_summary AS
SELECT g.id, g.title, g.status, g.game_date, g.prize_pool_etb, g.prize_pool_remaining,
  g.platform_fee_etb, g.total_players, g.total_winners, g.total_paid_out,
  c.name AS company_name, c.id AS company_id, d.amount_etb AS deposited_etb, d.commission_etb
FROM games g
LEFT JOIN companies c ON g.company_id = c.id
LEFT JOIN company_deposits d ON g.deposit_id = d.id
ORDER BY g.game_date DESC;

CREATE OR REPLACE VIEW v_qr_code_summary AS
SELECT q.id, q.token, q.label, q.status, q.scan_count, q.max_scans, q.expires_at, q.created_at,
  g.title AS game_title, g.status AS game_status, c.name AS company_name
FROM qr_codes q
JOIN games g ON q.game_id = g.id
LEFT JOIN companies c ON q.company_id = c.id
ORDER BY q.created_at DESC;

ALTER TABLE users            ENABLE ROW LEVEL SECURITY;
ALTER TABLE companies        ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_deposits ENABLE ROW LEVEL SECURITY;
ALTER TABLE questions        ENABLE ROW LEVEL SECURITY;
ALTER TABLE answer_options   ENABLE ROW LEVEL SECURITY;
ALTER TABLE games            ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_sessions    ENABLE ROW LEVEL SECURITY;
ALTER TABLE round_answers    ENABLE ROW LEVEL SECURITY;
ALTER TABLE spin_results     ENABLE ROW LEVEL SECURITY;
ALTER TABLE leaderboard      ENABLE ROW LEVEL SECURITY;
ALTER TABLE withdrawals      ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions     ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications    ENABLE ROW LEVEL SECURITY;
ALTER TABLE qr_codes         ENABLE ROW LEVEL SECURITY;
ALTER TABLE qr_scans         ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION auth_user_id() RETURNS UUID AS $$
  SELECT id FROM users WHERE telegram_id = ((current_setting('request.jwt.claims', true)::JSONB ->> 'telegram_id')::BIGINT);
$$ LANGUAGE sql STABLE SECURITY DEFINER;

DROP POLICY IF EXISTS "users_select_own"      ON users;
DROP POLICY IF EXISTS "users_update_own"      ON users;
DROP POLICY IF EXISTS "sessions_own"          ON game_sessions;
DROP POLICY IF EXISTS "answers_own"           ON round_answers;
DROP POLICY IF EXISTS "spins_own"             ON spin_results;
DROP POLICY IF EXISTS "withdrawals_own"       ON withdrawals;
DROP POLICY IF EXISTS "transactions_own"      ON transactions;
DROP POLICY IF EXISTS "notifications_own"     ON notifications;
DROP POLICY IF EXISTS "qr_scans_own"          ON qr_scans;
DROP POLICY IF EXISTS "questions_approved"    ON questions;
DROP POLICY IF EXISTS "questions_own_company" ON questions;
DROP POLICY IF EXISTS "answer_options_select" ON answer_options;
DROP POLICY IF EXISTS "games_active"          ON games;
DROP POLICY IF EXISTS "games_own"             ON games;
DROP POLICY IF EXISTS "leaderboard_select"    ON leaderboard;
DROP POLICY IF EXISTS "companies_public"      ON companies;
DROP POLICY IF EXISTS "companies_own"         ON companies;
DROP POLICY IF EXISTS "qr_codes_select"       ON qr_codes;
DROP POLICY IF EXISTS "deposits_own_company"  ON company_deposits;

CREATE POLICY "users_select_own"      ON users            FOR SELECT USING (id = auth_user_id());
CREATE POLICY "users_update_own"      ON users            FOR UPDATE USING (id = auth_user_id());
CREATE POLICY "sessions_own"          ON game_sessions    FOR ALL    USING (user_id = auth_user_id());
CREATE POLICY "answers_own"           ON round_answers    FOR ALL    USING (user_id = auth_user_id());
CREATE POLICY "spins_own"             ON spin_results     FOR ALL    USING (user_id = auth_user_id());
CREATE POLICY "withdrawals_own"       ON withdrawals      FOR ALL    USING (user_id = auth_user_id());
CREATE POLICY "transactions_own"      ON transactions     FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "notifications_own"     ON notifications    FOR ALL    USING (user_id = auth_user_id());
CREATE POLICY "qr_scans_own"          ON qr_scans         FOR SELECT USING (user_id = auth_user_id());
CREATE POLICY "questions_approved"    ON questions        FOR SELECT USING (status = 'approved');
CREATE POLICY "questions_own_company" ON questions        FOR ALL    USING (created_by = auth_user_id());
CREATE POLICY "answer_options_select" ON answer_options   FOR SELECT USING (question_id IN (SELECT id FROM questions WHERE status = 'approved') OR question_id IN (SELECT id FROM questions WHERE created_by = auth_user_id()));
CREATE POLICY "games_active"          ON games            FOR SELECT USING (status IN ('active','ended'));
CREATE POLICY "games_own"             ON games            FOR ALL    USING (created_by = auth_user_id());
CREATE POLICY "leaderboard_select"    ON leaderboard      FOR SELECT USING (TRUE);
CREATE POLICY "companies_public"      ON companies        FOR SELECT USING (status = 'active');
CREATE POLICY "companies_own"         ON companies        FOR ALL    USING (owner_id = auth_user_id());
CREATE POLICY "qr_codes_select"       ON qr_codes         FOR SELECT USING (status = 'active');
CREATE POLICY "deposits_own_company"  ON company_deposits FOR SELECT USING (company_id IN (SELECT id FROM companies WHERE owner_id = auth_user_id()));
-- game_questions: allow anyone to read (questions inside active games are not sensitive)
DROP POLICY IF EXISTS "game_questions_select" ON game_questions;
CREATE POLICY "game_questions_select" ON game_questions   FOR SELECT USING (TRUE);

INSERT INTO users (telegram_id, first_name, role, telegram_username)
VALUES (0, 'SHAMO Platform', 'admin', 'shamo_platform')
ON CONFLICT (telegram_id) DO NOTHING;

DO $$
DECLARE
  v_admin UUID;
  q1 UUID; q2 UUID; q3 UUID; q4 UUID; q5 UUID;
  q6 UUID; q7 UUID; q8 UUID; q9 UUID; q10 UUID;
  q11 UUID; q12 UUID; q13 UUID; q14 UUID; q15 UUID;
BEGIN
  SELECT id INTO v_admin FROM users WHERE telegram_id = 0;
  INSERT INTO questions (created_by,status,icon,question_text,category) VALUES (v_admin,'approved','🇪🇹','What is the capital city of Ethiopia?','Geography') RETURNING id INTO q1;
  INSERT INTO questions (created_by,status,icon,question_text,category) VALUES (v_admin,'approved','☕','Ethiopia is the birthplace of which popular drink?','Culture') RETURNING id INTO q2;
  INSERT INTO questions (created_by,status,icon,question_text,category) VALUES (v_admin,'approved','🏃','How did Abebe Bikila run the 1960 Olympic marathon?','Sports') RETURNING id INTO q3;
  INSERT INTO questions (created_by,status,icon,question_text,category) VALUES (v_admin,'approved','🗓️','How many months does the Ethiopian calendar have?','Culture') RETURNING id INTO q4;
  INSERT INTO questions (created_by,status,icon,question_text,category) VALUES (v_admin,'approved','🦁','What is the symbolic animal of Ethiopia''s imperial history?','History') RETURNING id INTO q5;
  INSERT INTO questions (created_by,status,icon,question_text,category) VALUES (v_admin,'approved','⚔️','In what year did Ethiopia defeat Italy at the Battle of Adwa?','History') RETURNING id INTO q6;
  INSERT INTO questions (created_by,status,icon,question_text,category) VALUES (v_admin,'approved','👑','Which Ethiopian emperor is revered in Rastafarian faith?','Religion') RETURNING id INTO q7;
  INSERT INTO questions (created_by,status,icon,question_text,category) VALUES (v_admin,'approved','📜','What ancient script is used to write Amharic?','Language') RETURNING id INTO q8;
  INSERT INTO questions (created_by,status,icon,question_text,category) VALUES (v_admin,'approved','🌊','Which river starts in Ethiopia and provides most of the Nile''s water?','Geography') RETURNING id INTO q9;
  INSERT INTO questions (created_by,status,icon,question_text,category) VALUES (v_admin,'approved','🏺','The ancient city of Axum was the center of which empire?','History') RETURNING id INTO q10;
  INSERT INTO questions (created_by,status,icon,question_text,category) VALUES (v_admin,'approved','📖','What is Ethiopia''s ancient text about the Ark of the Covenant?','Religion') RETURNING id INTO q11;
  INSERT INTO questions (created_by,status,icon,question_text,category) VALUES (v_admin,'approved','🎵','What is the Ethiopian traditional musical mode system called?','Music') RETURNING id INTO q12;
  INSERT INTO questions (created_by,status,icon,question_text,category) VALUES (v_admin,'approved','🏔️','What is the highest peak in Ethiopia?','Geography') RETURNING id INTO q13;
  INSERT INTO questions (created_by,status,icon,question_text,category) VALUES (v_admin,'approved','🏛️','Which dynasty claimed descent from King Solomon?','History') RETURNING id INTO q14;
  INSERT INTO questions (created_by,status,icon,question_text,category) VALUES (v_admin,'approved','🦋','What Ethiopian fossil hominid was discovered in 1974?','Science') RETURNING id INTO q15;
  INSERT INTO answer_options (question_id,option_letter,option_text,is_correct,sort_order) VALUES
    (q1,'A','Nairobi',FALSE,0),(q1,'B','Addis Ababa',TRUE,1),(q1,'C','Khartoum',FALSE,2),(q1,'D','Kampala',FALSE,3),
    (q2,'A','Tea',FALSE,0),(q2,'B','Cocoa',FALSE,1),(q2,'C','Coffee',TRUE,2),(q2,'D','Wine',FALSE,3),
    (q3,'A','In sandals',FALSE,0),(q3,'B','Barefoot',TRUE,1),(q3,'C','In boots',FALSE,2),(q3,'D','On a bike',FALSE,3),
    (q4,'A','12',FALSE,0),(q4,'B','11',FALSE,1),(q4,'C','13',TRUE,2),(q4,'D','14',FALSE,3),
    (q5,'A','Lion',TRUE,0),(q5,'B','Eagle',FALSE,1),(q5,'C','Elephant',FALSE,2),(q5,'D','Giraffe',FALSE,3),
    (q6,'A','1880',FALSE,0),(q6,'B','1896',TRUE,1),(q6,'C','1910',FALSE,2),(q6,'D','1935',FALSE,3),
    (q7,'A','Menelik II',FALSE,0),(q7,'B','Tewodros II',FALSE,1),(q7,'C','Haile Selassie I',TRUE,2),(q7,'D','Yohannes IV',FALSE,3),
    (q8,'A','Arabic',FALSE,0),(q8,'B','Latin',FALSE,1),(q8,'C','Ge''ez',TRUE,2),(q8,'D','Cyrillic',FALSE,3),
    (q9,'A','Congo River',FALSE,0),(q9,'B','Amazon River',FALSE,1),(q9,'C','Blue Nile',TRUE,2),(q9,'D','Zambezi',FALSE,3),
    (q10,'A','Ottoman',FALSE,0),(q10,'B','Aksumite',TRUE,1),(q10,'C','Mali',FALSE,2),(q10,'D','Zulu',FALSE,3),
    (q11,'A','Kebra Nagast',TRUE,0),(q11,'B','Fetha Nagast',FALSE,1),(q11,'C','Gadl',FALSE,2),(q11,'D','Awda Nagast',FALSE,3),
    (q12,'A','Pentatonic',FALSE,0),(q12,'B','Qenet',TRUE,1),(q12,'C','Heptatonic',FALSE,2),(q12,'D','Maqam',FALSE,3),
    (q13,'A','Mount Kenya',FALSE,0),(q13,'B','Ras Dashen',TRUE,1),(q13,'C','Mount Elgon',FALSE,2),(q13,'D','Tullu Dimtu',FALSE,3),
    (q14,'A','Zagwe Dynasty',FALSE,0),(q14,'B','Gondarine Dynasty',FALSE,1),(q14,'C','Solomonic Dynasty',TRUE,2),(q14,'D','Tigrayan Dynasty',FALSE,3),
    (q15,'A','Ardi',FALSE,0),(q15,'B','Selam',FALSE,1),(q15,'C','Lucy',TRUE,2),(q15,'D','Kadanuumuu',FALSE,3);
END;
$$;