-- Update default withdrawal fee to 5% (company commission)
-- User requested 138 ETB → company deducts 5% = 7 ETB → user receives 131 ETB
UPDATE platform_config SET value = '5' WHERE key = 'withdrawal_fee_pct';
