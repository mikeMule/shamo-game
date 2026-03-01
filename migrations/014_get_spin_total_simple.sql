-- Fallback RPC: SUM(amount_etb) for user_id only (no w-status filter).
-- Use when get_active_spin_total fails (e.g. w-status column missing).

CREATE OR REPLACE FUNCTION get_spin_total_simple(p_user_id UUID)
RETURNS NUMERIC AS $$
  SELECT COALESCE(SUM(amount_etb), 0)::NUMERIC
  FROM spin_results
  WHERE user_id = p_user_id;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION get_spin_total_simple(UUID) IS 'Total ETB from all spins (no w-status filter). Fallback for withdraw.';
