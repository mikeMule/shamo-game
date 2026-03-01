-- Add w-status column to spin_results table.
-- Use for tracking withdrawal-related status per spin (e.g. active, withdrawn).
-- Balance = SUM(amount_etb) WHERE user_id AND w-status = 'active'.

ALTER TABLE spin_results ADD COLUMN IF NOT EXISTS "w-status" VARCHAR(20) NOT NULL DEFAULT 'active';

CREATE INDEX IF NOT EXISTS idx_spin_results_user_w_status ON spin_results(user_id, "w-status");

COMMENT ON COLUMN spin_results."w-status" IS 'Withdrawal status: active = available for balance; withdrawn = paid out via withdrawal';
