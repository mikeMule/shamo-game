-- When admin releases a withdrawal (approve or complete), spin_results.w-status is set to 'deactive'
-- for that user. Balance = SUM(amount_etb) WHERE w-status='active', so user sees 0 after release.
-- New spins default to 'active'. No schema change — API handles the update.

COMMENT ON COLUMN spin_results."w-status" IS 'active = counts toward balance; deactive = paid out via withdrawal (balance shows 0)';
