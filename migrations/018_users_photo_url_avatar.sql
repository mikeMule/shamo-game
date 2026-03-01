-- Add profile image / avatar column to users table.
-- Stores Telegram profile photo URL (from tgUser.photo_url or bot get_user_profile_photos).
-- Used for avatar display in profile, header, leaderboard, etc.

ALTER TABLE users ADD COLUMN IF NOT EXISTS photo_url TEXT;

COMMENT ON COLUMN users.photo_url IS 'Telegram profile photo URL (avatar). From Mini App tgUser.photo_url or bot get_user_profile_photos.';
