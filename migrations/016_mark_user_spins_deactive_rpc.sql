-- RPC: Mark all active spins for a user as deactive (called when admin releases withdrawal).
-- Bypasses RLS so admin can update any user's spins. Balance = SUM where w-status='active', so user sees 0 after release.

CREATE OR REPLACE FUNCTION mark_user_spins_deactive(p_user_id UUID)
RETURNS INTEGER AS $$
DECLARE
  result_count INTEGER;
BEGIN
  UPDATE spin_results
  SET "w-status" = 'deactive'
  WHERE user_id = p_user_id AND "w-status" = 'active';
  GET DIAGNOSTICS result_count = ROW_COUNT;
  RETURN result_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION mark_user_spins_deactive(UUID) IS 'Admin: mark all active spins as deactive for user (after withdrawal release). Returns rows updated.';
