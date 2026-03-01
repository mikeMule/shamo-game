"""
Supabase/PostgreSQL helpers for SHAMO.
Uses DATABASE_URL from .env. If unset or psycopg2 missing, all functions no-op.
"""
import logging
import os

logger = logging.getLogger(__name__)

try:
    import psycopg2
    from psycopg2.extras import RealDictCursor
except ImportError:
    psycopg2 = None


def _conn():
    # From .env — see .env.example.local (optional if using supabase-py only)
    url = (os.getenv("DATABASE_URL") or "").strip()
    if not url or not psycopg2:
        return None
    try:
        return psycopg2.connect(url)
    except Exception as e:
        logger.warning("Database connection failed: %s", e)
        return None


def init_players_table() -> None:
    """Create players table if it does not exist."""
    conn = _conn()
    if not conn:
        return
    try:
        with conn.cursor() as cur:
            cur.execute("""
                CREATE TABLE IF NOT EXISTS public.players (
                    id             SERIAL PRIMARY KEY,
                    tg_user_id     BIGINT UNIQUE NOT NULL,
                    phone          TEXT,
                    username       TEXT,
                    full_name      TEXT,
                    created_at     TIMESTAMPTZ DEFAULT NOW(),
                    updated_at     TIMESTAMPTZ DEFAULT NOW()
                );
            """)
        conn.commit()
    except Exception as e:
        logger.warning("Could not create players table: %s", e)
    finally:
        conn.close()


def register_player(tg_user_id: int, phone: str, username: str, full_name: str) -> bool:
    """Insert or update a player by Telegram user id. Returns True if saved."""
    conn = _conn()
    if not conn:
        return False
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("""
                INSERT INTO public.players (tg_user_id, phone, username, full_name, updated_at)
                VALUES (%s, %s, %s, %s, NOW())
                ON CONFLICT (tg_user_id)
                DO UPDATE SET phone = EXCLUDED.phone, username = EXCLUDED.username,
                              full_name = EXCLUDED.full_name, updated_at = NOW();
            """, (tg_user_id, phone or None, username or None, full_name or None))
        conn.commit()
        return True
    except Exception as e:
        logger.warning("Could not save player: %s", e)
        return False
    finally:
        conn.close()
