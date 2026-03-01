-- Recreate withdrawals table (clean schema from migrations 001, 003, 006)
-- WARNING: This DROPS the table and all withdrawal data. Run only if you need a fresh table.

DROP TRIGGER IF EXISTS trg_withdrawal_status ON withdrawals;
DROP TABLE IF EXISTS withdrawals;

CREATE TABLE withdrawals (
  id               UUID              PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id          UUID              NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount_requested NUMERIC(10,2)     NOT NULL DEFAULT 0.00,
  fee_pct          NUMERIC(5,2)      NOT NULL DEFAULT 5.00,
  fee_etb          NUMERIC(10,2)     NOT NULL DEFAULT 0.00,
  amount_paid      NUMERIC(10,2)     NOT NULL DEFAULT 0.00,
  status           withdrawal_status NOT NULL DEFAULT 'pending',
  phone_number     VARCHAR(20),
  full_name        VARCHAR(120),
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

CREATE INDEX idx_withdrawals_user   ON withdrawals(user_id);
CREATE INDEX idx_withdrawals_status ON withdrawals(status);

ALTER TABLE withdrawals ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "withdrawals_own" ON withdrawals;
CREATE POLICY "withdrawals_own" ON withdrawals FOR ALL USING (user_id = auth_user_id());

-- Trigger (from migration 003)
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
  ELSIF NEW.status = 'failed' AND OLD.status = 'processing' THEN
    SELECT balance INTO v_bal_before FROM users WHERE id = NEW.user_id;
    v_bal_after := v_bal_before + NEW.amount_requested;
    UPDATE users SET balance = balance + NEW.amount_requested, total_withdrawn = total_withdrawn - NEW.amount_paid, updated_at = NOW() WHERE id = NEW.user_id;
    INSERT INTO transactions (user_id, type, amount, balance_before, balance_after, reference_id, reference_type, description)
    VALUES (NEW.user_id, 'withdrawal_failed', NEW.amount_requested, v_bal_before, v_bal_after, NEW.id, 'withdrawal', 'Withdrawal failed — ' || COALESCE(NEW.failure_reason, 'unknown'));
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_withdrawal_status
  AFTER UPDATE ON withdrawals
  FOR EACH ROW EXECUTE FUNCTION on_withdrawal_status_change();

COMMENT ON TABLE withdrawals IS 'User withdrawal requests. status: pending, processing, completed, failed, cancelled';
