-- When withdrawal is denied (status → failed) from PENDING, refund users.balance.
-- Migration 008 trigger only handled processing→failed. Add pending→failed.

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
