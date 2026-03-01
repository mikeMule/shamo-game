-- Remove withdrawal_status from spin_results. Spin results and withdrawals are independent.
-- Balance = SUM(spin_results.amount_etb) - pending withdrawals. No spin-level status.

ALTER TABLE spin_results DROP CONSTRAINT IF EXISTS chk_spin_withdrawal_status;
ALTER TABLE spin_results DROP COLUMN IF EXISTS withdrawal_status;
DROP INDEX IF EXISTS idx_spin_results_withdrawal_status;

-- RPC to get spin balance (avoids PostgREST schema cache issues after column drop)
CREATE OR REPLACE FUNCTION get_user_spin_balance(p_user_id UUID)
RETURNS NUMERIC AS $$
  SELECT COALESCE(SUM(amount_etb), 0)::NUMERIC FROM spin_results WHERE user_id = p_user_id;
$$ LANGUAGE sql STABLE SECURITY DEFINER;
