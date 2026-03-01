-- Add withdrawal_status to spin_results: 'active' = available for balance, 'withdrawn' = already paid out
-- Available balance = SUM(amount_etb) WHERE withdrawal_status = 'active'
-- Game history shows both; only active values count toward available balance

ALTER TABLE spin_results ADD COLUMN IF NOT EXISTS withdrawal_status VARCHAR(20) NOT NULL DEFAULT 'active';

ALTER TABLE spin_results DROP CONSTRAINT IF EXISTS chk_spin_withdrawal_status;
ALTER TABLE spin_results ADD CONSTRAINT chk_spin_withdrawal_status CHECK (withdrawal_status IN ('active', 'withdrawn'));

CREATE INDEX IF NOT EXISTS idx_spin_results_withdrawal_status ON spin_results(user_id, withdrawal_status);

COMMENT ON COLUMN spin_results.withdrawal_status IS 'active = counts toward available balance; withdrawn = already paid out via withdrawal';
