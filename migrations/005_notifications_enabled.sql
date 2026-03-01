-- Add notifications_enabled column to users table for push notification preferences.
-- When a user blocks the bot (Telegram Forbidden), we set this to false to exclude them from future broadcasts.
ALTER TABLE users ADD COLUMN IF NOT EXISTS notifications_enabled boolean DEFAULT true;
