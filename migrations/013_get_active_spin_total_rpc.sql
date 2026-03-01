-- RPC: Sum of amount_etb from spin_results WHERE user_id AND w-status = 'active'.
-- Same as: SELECT COALESCE(SUM(sr.amount_etb), 0) FROM spin_results sr
--          LEFT JOIN games g ON g.id = sr.game_id
--          WHERE sr.user_id = p_user_id AND sr."w-status" = 'active';

CREATE OR REPLACE FUNCTION get_active_spin_total(p_user_id UUID)
RETURNS NUMERIC AS $$
  SELECT COALESCE(SUM(sr.amount_etb), 0)::NUMERIC
  FROM spin_results sr
  LEFT JOIN games g ON g.id = sr.game_id
  WHERE sr.user_id = p_user_id
    AND sr."w-status" = 'active';
$$ LANGUAGE sql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION get_active_spin_total(UUID) IS 'Total ETB from active spins. Used for profile balance and withdraw check.';
