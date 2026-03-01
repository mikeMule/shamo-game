-- Single source of truth for available balance. Used by API to prevent double-withdrawal.
-- Formula: spin_earnings - (pending + processing + completed) withdrawals
-- Balance stays 0 until user plays new games and earns more.

CREATE OR REPLACE FUNCTION get_available_balance(p_user_id UUID)
RETURNS NUMERIC AS $$
  SELECT GREATEST(0,
    (SELECT COALESCE(SUM(amount_etb), 0)::NUMERIC FROM spin_results WHERE user_id = p_user_id)
    -
    (SELECT COALESCE(SUM(amount_requested), 0)::NUMERIC FROM withdrawals
     WHERE user_id = p_user_id AND status IN ('pending', 'processing', 'completed'))
  )::NUMERIC;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION get_available_balance(UUID) IS 'Available ETB = spin earnings minus all non-failed withdrawals. Stays 0 after release until new games.';
