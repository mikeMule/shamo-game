-- Add full_name to withdrawals: Telebirr registered name for payout
ALTER TABLE withdrawals ADD COLUMN IF NOT EXISTS full_name VARCHAR(120);
