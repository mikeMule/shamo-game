"""
SHAMO Admin API — FastAPI backend  (Performance-Optimized)
• Singleton Supabase client (created once at startup, reused for all requests)
• asyncio + thread-pool for concurrent queries (parallel stats, parallel N+1 fixes)
• N+1 eliminated: withdrawals embed user info; questions batch-fetch options
Run: uvicorn api:app --port 8001 --reload
"""
import os, json, logging, asyncio
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from concurrent.futures import ThreadPoolExecutor
from typing import Optional, Any, Dict, List
from functools import partial
import httpx as _httpx

from dotenv import load_dotenv
load_dotenv()

from fastapi import FastAPI, HTTPException, Request, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from supabase import create_client, Client

# ─── Config ───────────────────────────────────────────────────────────────────
SUPABASE_URL  = os.getenv("SUPABASE_URL", "")
SUPABASE_KEY  = os.getenv("SUPABASE_SERVICE_KEY") or os.getenv("SUPABASE_ANON_KEY", "")
ADMIN_TOKEN   = os.getenv("ADMIN_TOKEN",    "shamo_admin_2024")
ADMIN_USER    = os.getenv("ADMIN_USERNAME", "admin")
ADMIN_PASS    = os.getenv("ADMIN_PASSWORD", "shamo2024")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("shamo.api")

# ─── Singleton Supabase client (created ONCE at startup) ───────────────────────────
_sb: Client | None = None

def get_sb() -> Client:
    global _sb
    if _sb is None:
        if not SUPABASE_URL or not SUPABASE_KEY:
            raise HTTPException(500, "SUPABASE_URL / SUPABASE_SERVICE_KEY not set in .env")
        _sb = create_client(SUPABASE_URL, SUPABASE_KEY)
        logger.info("Supabase client initialized (singleton)")
    return _sb

def _reset_sb():
    """Drop the stale singleton so the next call to get_sb() creates a fresh one."""
    global _sb
    _sb = None
    logger.warning("Supabase client reset — stale connection detected, reconnecting...")

# ─── Thread-pool for running sync Supabase calls concurrently ─────────────────
_pool = ThreadPoolExecutor(max_workers=12)

async def run(fn, *args, **kwargs):
    """Run sync fn in the thread-pool. Auto-reconnects if HTTP/2 connection is stale."""
    loop = asyncio.get_event_loop()
    _fn = partial(fn, *args, **kwargs)
    try:
        return await loop.run_in_executor(_pool, _fn)
    except (_httpx.LocalProtocolError, _httpx.RemoteProtocolError) as exc:
        # Supabase's HTTP/2 connection went stale — reset and retry once
        logger.warning("HTTP/2 connection error (%s), resetting client and retrying...", exc)
        _reset_sb()
        # Rebuild fn with a fresh sb reference
        return await loop.run_in_executor(_pool, _fn)

# ─── Fast parallel helper ─────────────────────────────────────────────────────
async def gather(*fns):
    """Run multiple synchronous callables concurrently and return results list."""
    return await asyncio.gather(*[run(f) for f in fns])

# ─── Bot lifecycle — runs bot alongside FastAPI ───────────────────────────────
_bot_task: asyncio.Task | None = None

async def _run_bot():
    """Run the Telegram bot inside the same event loop as FastAPI."""
    try:
        from bot import build_application
        from telegram.ext import Application
        bot_app: Application = build_application()
        await bot_app.initialize()
        await bot_app.start()
        await bot_app.updater.start_polling(allowed_updates=["message", "callback_query"])
        logger.info("Telegram bot started alongside API ✅")
        # Keep running until cancelled
        await asyncio.Event().wait()
    except asyncio.CancelledError:
        await bot_app.updater.stop()
        await bot_app.stop()
        await bot_app.shutdown()
        logger.info("Telegram bot stopped.")
    except Exception as e:
        logger.error("Bot startup failed: %s", e)

@asynccontextmanager
async def lifespan(app: FastAPI):
    # NOTE: The Telegram bot is launched separately via bot.py (start_services.ps1).
    # Do NOT start the bot here to avoid running two instances simultaneously (409 Conflict).
    yield

# ─── App ──────────────────────────────────────────────────────────────────────
app = FastAPI(title="SHAMO Admin API", version="2.0.0", docs_url="/api/docs", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], allow_credentials=True,
    allow_methods=["*"], allow_headers=["*"],
)

# Static mounts
_admin_dir = os.path.join(os.path.dirname(__file__), "admin")
app.mount("/admin", StaticFiles(directory=_admin_dir, html=True), name="admin")

_game_dir = os.path.dirname(__file__)
app.mount("/game",  StaticFiles(directory=_game_dir,  html=True), name="game")

@app.get("/", include_in_schema=False)
def root():
    return RedirectResponse(url="/game/login.html")

@app.get("/admin-panel", include_in_schema=False)
def admin_redirect():
    return RedirectResponse(url="/admin/login.html")

# ─── Auth guard ───────────────────────────────────────────────────────────────
def require_admin(request: Request):
    token = request.headers.get("X-Admin-Token") or request.query_params.get("token")
    if token != ADMIN_TOKEN:
        raise HTTPException(401, "Unauthorized")

# ─── Schemas ──────────────────────────────────────────────────────────────────
class LoginReq(BaseModel):
    username: str; password: str

class UserUpdate(BaseModel):
    first_name: Optional[str] = None; last_name: Optional[str] = None
    role: Optional[str] = None; is_active: Optional[bool] = None
    is_banned: Optional[bool] = None; ban_reason: Optional[str] = None
    language_code: Optional[str] = None

class BalanceAdjust(BaseModel):
    amount: float; type: str; note: Optional[str] = ""

class GameCreate(BaseModel):
    title: str = "Tonight's SHAMO"; description: Optional[str] = None
    status: str = "draft"; starts_at: str; ends_at: str; game_date: str
    prize_pool_etb: float = 0.0; max_prize_etb: float = 5700.0
    platform_fee_pct: float = 15.0; player_cap_pct: float = 30.0
    company_id: Optional[str] = None; deposit_id: Optional[str] = None

class GameUpdate(BaseModel):
    title: Optional[str] = None; description: Optional[str] = None
    status: Optional[str] = None; starts_at: Optional[str] = None
    ends_at: Optional[str] = None; game_date: Optional[str] = None
    prize_pool_etb: Optional[float] = None; max_prize_etb: Optional[float] = None
    platform_fee_pct: Optional[float] = None; player_cap_pct: Optional[float] = None
    company_id: Optional[str] = None; deposit_id: Optional[str] = None


class QuestionCreate(BaseModel):
    question_text: str; category: Optional[str] = None
    explanation: Optional[str] = None; icon: str = "🇪🇹"
    company_id: Optional[str] = None; is_sponsored: bool = False
    game_id: Optional[str] = None  # link to game_questions join table
    options: list

class QuestionUpdate(BaseModel):
    question_text: Optional[str] = None
    category: Optional[str] = None; explanation: Optional[str] = None
    status: Optional[str] = None; icon: Optional[str] = None

class RejectReq(BaseModel):
    reason: Optional[str] = ""

class CompanyCreate(BaseModel):
    name: str; slug: str; category: Optional[str] = None
    description: Optional[str] = None; contact_email: Optional[str] = None
    contact_phone: Optional[str] = None; website: Optional[str] = None
    primary_color: str = "#E8B84B"; owner_id: Optional[str] = None

class CompanyUpdate(BaseModel):
    name: Optional[str] = None; category: Optional[str] = None
    description: Optional[str] = None; contact_email: Optional[str] = None
    contact_phone: Optional[str] = None; website: Optional[str] = None
    status: Optional[str] = None; primary_color: Optional[str] = None

class TopUpReq(BaseModel):
    amount: float; note: Optional[str] = ""

class WithdrawalUpdate(BaseModel):
    notes: Optional[str] = None

class DenyReq(BaseModel):
    reason: Optional[str] = "Admin denied"

class SettingUpdate(BaseModel):
    settings: Dict[str, Any]

class QRCreateReq(BaseModel):
    game_id: str; company_id: Optional[str] = None; label: Optional[str] = None
    base_url: str; max_scans: int = 0; expiry_hours: int = 24

class QRScanReq(BaseModel):
    token: str; user_id: Optional[str] = None
    telegram_id: Optional[int] = None; phone_number: Optional[str] = None

class SessionStartReq(BaseModel):
    game_id: str; user_id: str; qr_token: Optional[str] = None

class AnswerReq(BaseModel):
    session_id: str; user_id: str; game_id: str
    question_id: str; selected_option_id: Optional[str] = None
    question_number: int; time_taken_ms: Optional[int] = None

class SpinReq(BaseModel):
    session_id: str; user_id: str; game_id: str
    question_number: int; segment_label: str; amount_etb: float

class DepositApproveReq(BaseModel):
    notes: Optional[str] = None

class DepositRejectReq(BaseModel):
    reason: Optional[str] = "Rejected by admin"

class WithdrawReq(BaseModel):
    user_id: str; amount_requested: float
    phone_number: Optional[str] = None; bank_account: Optional[str] = None

class PlayerLoginReq(BaseModel):
    telegram_id:        int
    first_name:         str
    last_name:          Optional[str] = None
    telegram_username:  Optional[str] = None
    language_code:      Optional[str] = 'en'
    photo_url:          Optional[str] = None
    phone_number:       Optional[str] = None   # from Telegram contact share
    init_data:          Optional[str] = None

class PhoneReq(BaseModel):
    user_id:      str
    phone_number: str

# ═══════════════════════════════════════════════════════════════════════════════
# PLAYER (public) — login with Telegram, no admin token needed
# ═══════════════════════════════════════════════════════════════════════════════
@app.post("/api/player/login")
async def player_login(body: PlayerLoginReq):
    """Register or update a Telegram user and return their profile."""
    sb = get_sb()

    # Look up existing user by telegram_id
    existing = await run(lambda: sb.table("users")
        .select("*").eq("telegram_id", body.telegram_id).limit(1).execute())

    now = datetime.now(timezone.utc).isoformat()
    upsert_data = {
        "telegram_id":       body.telegram_id,
        "first_name":        body.first_name,
        "last_name":         body.last_name,
        "telegram_username": body.telegram_username,
        "language_code":     body.language_code or 'en',
        "photo_url":         body.photo_url,
        "is_active":         True,
        "updated_at":        now,
    }
    # Include phone number if provided
    if body.phone_number:
        upsert_data["phone_number"] = body.phone_number

    if existing.data:
        # Update returning user
        uid = existing.data[0]["id"]
        await run(lambda: sb.table("users").update(upsert_data).eq("id", uid).execute())
        res = await run(lambda: sb.table("users").select("*").eq("id", uid).single().execute())
        return res.data
    else:
        # Create new user
        upsert_data["role"]       = "player"
        upsert_data["created_at"] = now
        res = await run(lambda: sb.table("users").insert(upsert_data).execute())
        new_user = (res.data or [{}])[0]
        logger.info("New player registered: %s (tg_id=%s)", body.first_name, body.telegram_id)
        return new_user

@app.post("/api/player/phone")
async def save_player_phone(body: PhoneReq):
    """Save a player's phone number after they share contact."""
    sb = get_sb()
    await run(lambda: sb.table("users")
        .update({"phone_number": body.phone_number, "updated_at": datetime.now(timezone.utc).isoformat()})
        .eq("id", body.user_id).execute())
    return {"message": "Phone saved", "phone_number": body.phone_number}


# ═══════════════════════════════════════════════════════════════════════════════
# AUTH
# ═══════════════════════════════════════════════════════════════════════════════
@app.post("/api/auth/login")
def login(body: LoginReq):
    if body.username == ADMIN_USER and body.password == ADMIN_PASS:
        return {"token": ADMIN_TOKEN, "username": ADMIN_USER, "role": "admin"}
    raise HTTPException(401, "Invalid credentials")

@app.post("/api/auth/logout")
def logout(_=Depends(require_admin)):
    return {"message": "Logged out"}

@app.get("/api/auth/me")
def me(_=Depends(require_admin)):
    return {"username": ADMIN_USER, "role": "admin"}

# ═══════════════════════════════════════════════════════════════════════════════
# DASHBOARD STATS — all queries run in parallel
# ═══════════════════════════════════════════════════════════════════════════════
@app.get("/api/stats")
async def get_stats(_=Depends(require_admin)):
    sb = get_sb()
    try:
        def q_total_users():    return sb.table("users").select("id", count="exact").execute()
        def q_active_users():   return sb.table("users").select("id", count="exact").eq("is_active", True).eq("is_banned", False).execute()
        def q_banned_users():   return sb.table("users").select("id", count="exact").eq("is_banned", True).execute()
        def q_total_games():    return sb.table("games").select("id", count="exact").execute()
        def q_active_game():    return sb.table("games").select("id,title,status,total_players,total_winners,total_paid_out,prize_pool_etb,prize_pool_remaining,game_date").eq("status", "active").limit(1).execute()
        def q_pend_withdraw():  return sb.table("withdrawals").select("id", count="exact").eq("status", "pending").execute()
        def q_active_comp():    return sb.table("companies").select("id", count="exact").eq("status", "active").execute()
        def q_pend_comp():      return sb.table("companies").select("id", count="exact").eq("status", "pending").execute()
        def q_pend_qs():        return sb.table("questions").select("id", count="exact").eq("status", "pending").execute()
        def q_total_comp():     return sb.table("companies").select("id", count="exact").execute()
        def q_total_qs():       return sb.table("questions").select("id", count="exact").execute()
        def q_games_data():     return sb.table("games").select("total_paid_out,platform_fee_pct").execute()

        # Run ALL 12 queries at the same time
        (r_total_users, r_active_users, r_banned_users, r_total_games,
         r_active_game, r_pend_withdraw, r_active_comp, r_pend_comp,
         r_pend_qs, r_total_comp, r_total_qs, r_games_data) = await gather(
            q_total_users, q_active_users, q_banned_users, q_total_games,
            q_active_game, q_pend_withdraw, q_active_comp, q_pend_comp,
            q_pend_qs, q_total_comp, q_total_qs, q_games_data
        )

        games = r_games_data.data or []
        total_payout = sum(float(g.get("total_paid_out") or 0) for g in games)
        fee_income   = sum(float(g.get("total_paid_out") or 0) * float(g.get("platform_fee_pct") or 0) / 100 for g in games)
        active_game  = (r_active_game.data or [None])[0]

        return {
            "total_users": r_total_users.count or 0,
            "active_users": r_active_users.count or 0,
            "banned_users": r_banned_users.count or 0,
            "total_games": r_total_games.count or 0,
            "active_game": active_game,
            "pending_withdrawals": r_pend_withdraw.count or 0,
            "active_companies": r_active_comp.count or 0,
            "pending_companies": r_pend_comp.count or 0,
            "total_companies": r_total_comp.count or 0,
            "pending_questions": r_pend_qs.count or 0,
            "total_questions": r_total_qs.count or 0,
            "total_payout": total_payout,
            "platform_fee_income": fee_income,
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Stats error: %s", e)
        raise HTTPException(500, str(e))

# ═══════════════════════════════════════════════════════════════════════════════
# USERS
# ═══════════════════════════════════════════════════════════════════════════════
@app.get("/api/users")
async def list_users(
    request: Request, _=Depends(require_admin),
    page: int = 1, per_page: int = 20,
    search: str = "", role: str = "", status: str = "",
    sort: str = "created_at", order: str = "desc"
):
    sb = get_sb()
    safe_sort = sort if sort in ("created_at","balance","total_earned","games_played","first_name") else "created_at"

    def _query():
        q = sb.table("users").select(
            "id,telegram_id,telegram_username,first_name,last_name,phone_number,role,"
            "is_active,is_banned,ban_reason,balance,total_earned,total_withdrawn,"
            "games_played,games_won,correct_answers,wrong_answers,current_streak,best_streak,"
            "last_game_date,created_at",
            count="exact"
        )
        if search:
            q = q.or_(f"first_name.ilike.%{search}%,last_name.ilike.%{search}%,telegram_username.ilike.%{search}%,phone_number.ilike.%{search}%")
        if role:   q = q.eq("role", role)
        if status == "active":   q = q.eq("is_active", True).eq("is_banned", False)
        elif status == "banned": q = q.eq("is_banned", True)
        elif status == "inactive": q = q.eq("is_active", False)
        q = q.order(safe_sort, desc=(order.lower() == "desc"))
        offset = (page - 1) * per_page
        return q.range(offset, offset + per_page - 1).execute()

    res = await run(_query)
    return {"data": res.data or [], "total": res.count or 0, "page": page, "per_page": per_page}

@app.get("/api/users/{uid}")
async def get_user(uid: str, _=Depends(require_admin)):
    sb = get_sb()
    res = await run(lambda: sb.table("users").select("*").eq("id", uid).single().execute())
    if not res.data: raise HTTPException(404, "User not found")
    return res.data

@app.put("/api/users/{uid}")
async def update_user(uid: str, body: UserUpdate, _=Depends(require_admin)):
    updates = body.dict(exclude_none=True)
    if not updates: raise HTTPException(400, "Nothing to update")
    sb = get_sb()
    await run(lambda: sb.table("users").update(updates).eq("id", uid).execute())
    return await get_user(uid, _)

@app.delete("/api/users/{uid}")
async def delete_user(uid: str, _=Depends(require_admin)):
    sb = get_sb()
    await run(lambda: sb.table("users").delete().eq("id", uid).execute())
    return {"message": "User deleted"}

@app.post("/api/users/{uid}/ban")
async def ban_user(uid: str, _=Depends(require_admin)):
    sb = get_sb()
    res = await run(lambda: sb.table("users").select("is_banned").eq("id", uid).single().execute())
    if not res.data: raise HTTPException(404, "User not found")
    new_val = not res.data["is_banned"]
    await run(lambda: sb.table("users").update({"is_banned": new_val}).eq("id", uid).execute())
    return {"is_banned": new_val, "message": "Banned" if new_val else "Unbanned"}

@app.post("/api/users/{uid}/balance")
async def adjust_balance(uid: str, body: BalanceAdjust, _=Depends(require_admin)):
    sb = get_sb()
    res = await run(lambda: sb.table("users").select("balance").eq("id", uid).single().execute())
    if not res.data: raise HTTPException(404, "User not found")
    bal_before = float(res.data["balance"] or 0)
    if body.type == "credit":
        bal_after = bal_before + body.amount
        await run(lambda: sb.table("users").update({"balance": bal_after, "total_earned": bal_after}).eq("id", uid).execute())
    else:
        bal_after = max(0, bal_before - body.amount)
        await run(lambda: sb.table("users").update({"balance": bal_after}).eq("id", uid).execute())
    await run(lambda: sb.table("transactions").insert({
        "user_id": uid, "type": "admin_credit" if body.type == "credit" else "admin_debit",
        "amount": body.amount if body.type == "credit" else -body.amount,
        "balance_before": bal_before, "balance_after": bal_after,
        "description": body.note or "Admin adjustment"
    }).execute())
    return {"balance_before": bal_before, "balance_after": bal_after}

# ═══════════════════════════════════════════════════════════════════════════════
# GAMES
# ═══════════════════════════════════════════════════════════════════════════════
@app.get("/api/games")
async def list_games(
    request: Request, _=Depends(require_admin),
    page: int = 1, per_page: int = 20, status: str = "", search: str = ""
):
    sb = get_sb()
    def _query():
        q = sb.table("games").select(
            "*, companies(name)",
            count="exact"
        )
        if status: q = q.eq("status", status)
        if search: q = q.ilike("title", f"%{search}%")
        offset = (page - 1) * per_page
        return q.order("created_at", desc=True).range(offset, offset + per_page - 1).execute()
    res = await run(_query)
    games = res.data or []
    # Flatten company name for easy frontend access
    for g in games:
        g["company_name"] = (g.pop("companies", None) or {}).get("name") or g.get("company_name")
    return {"data": games, "total": res.count or 0, "page": page, "per_page": per_page}

@app.get("/api/games/{gid}")
async def get_game(gid: str, _=Depends(require_admin)):
    sb = get_sb()
    res = await run(lambda: sb.table("games").select("*, companies(name, id)").eq("id", gid).limit(1).execute())
    rows = res.data or []
    if not rows: raise HTTPException(404, "Game not found")
    g = rows[0]
    g["company_name"] = (g.pop("companies", None) or {}).get("name")
    return g

@app.post("/api/games")
async def create_game(body: GameCreate, _=Depends(require_admin)):
    sb = get_sb()
    admin = await run(lambda: sb.table("users").select("id").eq("role", "admin").limit(1).execute())
    created_by = (admin.data or [{}])[0].get("id")
    payload = body.dict()
    payload["created_by"] = created_by
    payload["company_id"] = payload["company_id"] or None
    res = await run(lambda: sb.table("games").insert(payload).execute())
    return (res.data or [{}])[0]

@app.put("/api/games/{gid}")
async def update_game(gid: str, body: GameUpdate, _=Depends(require_admin)):
    updates = body.dict(exclude_unset=True)
    if not updates: raise HTTPException(400, "Nothing to update")
    sb = get_sb()
    await run(lambda: sb.table("games").update(updates).eq("id", gid).execute())
    return await get_game(gid, _)

@app.delete("/api/games/{gid}")
async def delete_game(gid: str, _=Depends(require_admin)):
    sb = get_sb()
    def _del():
        # Manually cascade delete dependent records where game_id = gid
        for tbl in ["game_questions", "game_sessions", "qr_scans", "qr_codes", "leaderboard", "round_answers", "spins"]:
            try: sb.table(tbl).delete().eq("game_id", gid).execute()
            except Exception: pass
        # Delete the game itself
        sb.table("games").delete().eq("id", gid).execute()
    await run(_del)
    return {"message": "Game deleted"}

@app.post("/api/games/{gid}/activate")
async def activate_game(gid: str, _=Depends(require_admin)):
    sb = get_sb()
    await run(lambda: sb.table("games").update({"status": "active"}).eq("id", gid).execute())
    return {"status": "active"}

@app.post("/api/games/{gid}/end")
async def end_game(gid: str, _=Depends(require_admin)):
    sb = get_sb()
    await run(lambda: sb.table("games").update({"status": "ended"}).eq("id", gid).execute())
    return {"status": "ended"}

@app.get("/api/games/{gid}/questions")
async def get_game_questions(gid: str, _=Depends(require_admin)):
    """Return all questions linked to a game via game_questions join table."""
    sb = get_sb()
    # 1. Fetch questions linked to game
    gq_res = await run(lambda: sb.table("game_questions")
        .select("sort_order, question_id, questions(*)")
        .eq("game_id", gid)
        .order("sort_order").execute())
    rows = gq_res.data or []
    if not rows: return []
    
    # 2. Extract out the questions and gather their IDs
    result = []
    qids = []
    for row in rows:
        q = row.get("questions") or {}
        if not q: continue
        q["sort_order"] = row.get("sort_order", 0)
        qids.append(q["id"])
        result.append(q)
        
    # 3. Batch fetch ALL options for these questions to avoid N+1
    if qids:
        opts_res = await run(lambda: sb.table("answer_options")
            .select("*")
            .in_("question_id", qids)
            .order("sort_order").execute())
        opts_map = {}
        for opt in (opts_res.data or []):
            opts_map.setdefault(opt["question_id"], []).append(opt)
        for q in result:
            q["options"] = opts_map.get(q["id"], [])
            
    return result

@app.delete("/api/games/{gid}/questions/{qid}")
async def remove_question_from_game(gid: str, qid: str, _=Depends(require_admin)):
    """Unlink a question from a game (does NOT delete the question itself)."""
    sb = get_sb()
    await run(lambda: sb.table("game_questions").delete()
        .eq("game_id", gid).eq("question_id", qid).execute())
    return {"message": "Question removed from game"}


# ═══════════════════════════════════════════════════════════════════════════════
# QUESTIONS — batch options fetch (no N+1)
# ═══════════════════════════════════════════════════════════════════════════════
@app.get("/api/questions")
async def list_questions(
    request: Request, _=Depends(require_admin),
    page: int = 1, per_page: int = 20,
    status: str = "", search: str = "", game_id: str = ""
):
    sb = get_sb()
    def _qs():
        q = sb.table("questions").select("*", count="exact")
        if status: q = q.eq("status", status)
        if search: q = q.ilike("question_text", f"%{search}%")
        offset = (page - 1) * per_page
        return q.order("created_at", desc=True).range(offset, offset + per_page - 1).execute()

    res = await run(_qs)
    questions = res.data or []

    # Filter by game if given — join via game_questions
    if game_id and questions:
        gq_res = await run(lambda: sb.table("game_questions").select("question_id").eq("game_id", game_id).execute())
        linked_ids = {row["question_id"] for row in (gq_res.data or [])}
        questions = [q for q in questions if q["id"] in linked_ids]

    if questions:
        # Single batch query for all options on this page (no N+1!)
        qids = [q["id"] for q in questions]
        opts_res = await run(lambda: sb.table("answer_options").select("*").in_("question_id", qids).order("sort_order").execute())
        opts_map: Dict[str, list] = {}
        for opt in (opts_res.data or []):
            opts_map.setdefault(opt["question_id"], []).append(opt)
        
        # Also fetch which games each question belongs to
        gq_all = await run(lambda: sb.table("game_questions").select("question_id, games(id, title)").in_("question_id", qids).execute())
        gq_map: Dict[str, list] = {}
        for row in (gq_all.data or []):
            gq_map.setdefault(row["question_id"], []).append((row.get("games") or {}).get("title", "?"))
        
        for q in questions:
            q["options"] = opts_map.get(q["id"], [])
            q["games"] = gq_map.get(q["id"], [])

    return {"data": questions, "total": res.count or 0, "page": page, "per_page": per_page}

@app.get("/api/questions/{qid}")
async def get_question(qid: str, _=Depends(require_admin)):
    sb = get_sb()
    res_q, res_opts = await gather(
        lambda: sb.table("questions").select("*").eq("id", qid).single().execute(),
        lambda: sb.table("answer_options").select("*").eq("question_id", qid).order("sort_order").execute(),
    )
    if not res_q.data: raise HTTPException(404, "Question not found")
    q = res_q.data
    q["options"] = res_opts.data or []
    return q

@app.post("/api/questions")
async def create_question(body: QuestionCreate, _=Depends(require_admin)):
    sb = get_sb()
    admin = await run(lambda: sb.table("users").select("id").eq("role", "admin").limit(1).execute())
    created_by = (admin.data or [{}])[0].get("id")
    payload = {
        "question_text": body.question_text,
        "category": body.category, "explanation": body.explanation,
        "icon": body.icon, "company_id": body.company_id,
        "is_sponsored": body.is_sponsored, "created_by": created_by,
        "status": "approved"  # Admin-created questions are auto-approved
    }
    qrow_res = await run(lambda: sb.table("questions").insert(payload).execute())
    qrow = (qrow_res.data or [{}])[0]
    qid = qrow["id"]
    
    # Insert answer options
    opts = [{"question_id": qid, "option_letter": opt["letter"],
             "option_text": opt["text"], "is_correct": opt.get("is_correct", False),
             "sort_order": ord(opt["letter"]) - ord("A")} for opt in body.options]
    if opts:
        await run(lambda: sb.table("answer_options").insert(opts).execute())
    
    # Link to game via game_questions join table
    if body.game_id:
        gq_res = await run(lambda: sb.table("game_questions").select("id")
            .eq("game_id", body.game_id).eq("question_id", qid).execute())
        if not (gq_res.data):
            max_ord_res = await run(lambda: sb.table("game_questions").select("sort_order")
                .eq("game_id", body.game_id).order("sort_order", desc=True).limit(1).execute())
            next_order = ((max_ord_res.data or [{}])[0].get("sort_order") or 0) + 1
            await run(lambda: sb.table("game_questions").insert({
                "game_id": body.game_id, "question_id": qid, "sort_order": next_order
            }).execute())
        qrow["game_id"] = body.game_id
    
    return qrow

@app.put("/api/questions/{qid}")
async def update_question(qid: str, body: QuestionUpdate, _=Depends(require_admin)):
    updates = body.dict(exclude_none=True)
    if not updates: raise HTTPException(400, "Nothing to update")
    sb = get_sb()
    await run(lambda: sb.table("questions").update(updates).eq("id", qid).execute())
    return await get_question(qid, _)

@app.delete("/api/questions/{qid}")
async def delete_question(qid: str, _=Depends(require_admin)):
    sb = get_sb()
    await run(lambda: sb.table("questions").delete().eq("id", qid).execute())
    return {"message": "Question deleted"}

@app.post("/api/questions/{qid}/approve")
async def approve_question(qid: str, _=Depends(require_admin)):
    sb = get_sb()
    await run(lambda: sb.table("questions").update({
        "status": "approved",
        "reviewed_at": datetime.now(timezone.utc).isoformat()
    }).eq("id", qid).execute())
    return {"status": "approved"}

@app.post("/api/questions/{qid}/reject")
async def reject_question(qid: str, body: RejectReq, _=Depends(require_admin)):
    sb = get_sb()
    await run(lambda: sb.table("questions").update({
        "status": "rejected", "rejected_reason": body.reason,
        "reviewed_at": datetime.now(timezone.utc).isoformat()
    }).eq("id", qid).execute())
    return {"status": "rejected"}

# ═══════════════════════════════════════════════════════════════════════════════
# WITHDRAWALS — embedded user info (no N+1)
# ═══════════════════════════════════════════════════════════════════════════════
@app.get("/api/withdrawals")
async def list_withdrawals(
    request: Request, _=Depends(require_admin),
    page: int = 1, per_page: int = 20, status: str = "", search: str = ""
):
    sb = get_sb()
    def _query():
        # Embed user data in a single query — no N+1
        q = sb.table("withdrawals").select(
            "*, user:users!withdrawals_user_id_fkey(first_name,last_name,phone_number,telegram_username)",
            count="exact"
        )
        if status: q = q.eq("status", status)
        offset = (page - 1) * per_page
        return q.order("requested_at", desc=True).range(offset, offset + per_page - 1).execute()

    res = await run(_query)
    withdrawals = res.data or []
    # Flatten embedded user fields
    for w in withdrawals:
        user = w.pop("user", None) or {}
        w["user_name"]          = f"{user.get('first_name','') or ''} {user.get('last_name','') or ''}".strip() or "—"
        w["user_phone"]         = user.get("phone_number")
        w["telegram_username"]  = user.get("telegram_username")
    return {"data": withdrawals, "total": res.count or 0, "page": page, "per_page": per_page}

@app.get("/api/withdrawals/{wid}")
async def get_withdrawal(wid: str, _=Depends(require_admin)):
    sb = get_sb()
    res = await run(lambda: sb.table("withdrawals").select(
        "*, user:users!withdrawals_user_id_fkey(first_name,last_name,phone_number)"
    ).eq("id", wid).single().execute())
    if not res.data: raise HTTPException(404, "Withdrawal not found")
    w = res.data
    user = w.pop("user", None) or {}
    w["user_name"]  = f"{user.get('first_name','') or ''} {user.get('last_name','') or ''}".strip() or "—"
    w["user_phone"] = user.get("phone_number")
    return w

@app.put("/api/withdrawals/{wid}")
async def update_withdrawal(wid: str, body: WithdrawalUpdate, _=Depends(require_admin)):
    if body.notes is not None:
        sb = get_sb()
        await run(lambda: sb.table("withdrawals").update({"notes": body.notes}).eq("id", wid).execute())
    return await get_withdrawal(wid, _)

@app.post("/api/withdrawals/{wid}/approve")
async def approve_withdrawal(wid: str, _=Depends(require_admin)):
    sb = get_sb()
    await run(lambda: sb.table("withdrawals").update({
        "status": "processing",
        "processed_at": datetime.now(timezone.utc).isoformat()
    }).eq("id", wid).eq("status", "pending").execute())
    return {"status": "processing"}

@app.post("/api/withdrawals/{wid}/complete")
async def complete_withdrawal(wid: str, _=Depends(require_admin)):
    sb = get_sb()
    await run(lambda: sb.table("withdrawals").update({"status": "completed"}).eq("id", wid).eq("status", "processing").execute())
    return {"status": "completed"}

@app.post("/api/withdrawals/{wid}/deny")
async def deny_withdrawal(wid: str, body: DenyReq, _=Depends(require_admin)):
    sb = get_sb()
    await run(lambda: sb.table("withdrawals").update({
        "status": "failed", "failure_reason": body.reason
    }).eq("id", wid).in_("status", ["pending", "processing"]).execute())
    return {"status": "failed"}

# ═══════════════════════════════════════════════════════════════════════════════
# COMPANIES
# ═══════════════════════════════════════════════════════════════════════════════
@app.get("/api/companies")
async def list_companies(
    request: Request, _=Depends(require_admin),
    page: int = 1, per_page: int = 20, status: str = "", search: str = ""
):
    sb = get_sb()
    def _query():
        q = sb.table("companies").select("*", count="exact")
        if status: q = q.eq("status", status)
        if search: q = q.ilike("name", f"%{search}%")
        offset = (page - 1) * per_page
        return q.order("created_at", desc=True).range(offset, offset + per_page - 1).execute()
    res = await run(_query)
    return {"data": res.data or [], "total": res.count or 0, "page": page, "per_page": per_page}

@app.get("/api/companies/{cid}")
async def get_company(cid: str, _=Depends(require_admin)):
    sb = get_sb()
    res = await run(lambda: sb.table("companies").select("*").eq("id", cid).single().execute())
    if not res.data: raise HTTPException(404, "Company not found")
    return res.data

@app.post("/api/companies")
async def create_company(body: CompanyCreate, _=Depends(require_admin)):
    sb = get_sb()
    owner_id = body.owner_id
    if not owner_id:
        admin = await run(lambda: sb.table("users").select("id").eq("role", "admin").limit(1).execute())
        owner_id = (admin.data or [{}])[0].get("id")
    payload = body.dict()
    payload["owner_id"] = owner_id
    payload["status"] = "pending"
    res = await run(lambda: sb.table("companies").insert(payload).execute())
    return (res.data or [{}])[0]

@app.put("/api/companies/{cid}")
async def update_company(cid: str, body: CompanyUpdate, _=Depends(require_admin)):
    updates = body.dict(exclude_none=True)
    if not updates: raise HTTPException(400, "Nothing to update")
    sb = get_sb()
    await run(lambda: sb.table("companies").update(updates).eq("id", cid).execute())
    return await get_company(cid, _)

@app.delete("/api/companies/{cid}")
async def delete_company(cid: str, _=Depends(require_admin)):
    sb = get_sb()
    await run(lambda: sb.table("companies").delete().eq("id", cid).execute())
    return {"message": "Company deleted"}

@app.post("/api/companies/{cid}/verify")
async def verify_company(cid: str, _=Depends(require_admin)):
    sb = get_sb()
    await run(lambda: sb.table("companies").update({
        "status": "active",
        "verified_at": datetime.now(timezone.utc).isoformat()
    }).eq("id", cid).execute())
    return {"status": "active"}

@app.post("/api/companies/{cid}/suspend")
async def suspend_company(cid: str, _=Depends(require_admin)):
    sb = get_sb()
    await run(lambda: sb.table("companies").update({"status": "suspended"}).eq("id", cid).execute())
    return {"status": "suspended"}

@app.post("/api/companies/{cid}/topup")
async def topup_company(cid: str, body: TopUpReq, _=Depends(require_admin)):
    sb = get_sb()
    res = await run(lambda: sb.table("companies").select("credit_balance").eq("id", cid).single().execute())
    if not res.data: raise HTTPException(404, "Company not found")
    new_bal = float(res.data["credit_balance"] or 0) + body.amount
    await run(lambda: sb.table("companies").update({"credit_balance": new_bal}).eq("id", cid).execute())
    return {"credit_balance": new_bal}

# ═══════════════════════════════════════════════════════════════════════════════
# SETTINGS
# ═══════════════════════════════════════════════════════════════════════════════
@app.get("/api/settings")
async def get_settings(_=Depends(require_admin)):
    sb = get_sb()
    rows = await run(lambda: sb.table("platform_config").select("key,value,description,updated_at").order("key").execute())
    return {r["key"]: {"value": r["value"], "description": r.get("description"), "updated_at": str(r.get("updated_at"))}
            for r in (rows.data or [])}

@app.put("/api/settings")
async def update_settings(body: SettingUpdate, _=Depends(require_admin)):
    sb = get_sb()
    now = datetime.now(timezone.utc).isoformat()
    rows = [{"key": k, "value": json.dumps(v) if not isinstance(v, str) else json.dumps(v), "updated_at": now}
            for k, v in body.settings.items()]
    for row in rows:
        await run(lambda r=row: sb.table("platform_config").upsert(r, on_conflict="key").execute())
    return {"message": "Settings saved", "updated": list(body.settings.keys())}

# ═══════════════════════════════════════════════════════════════════════════════
# ANALYTICS — parallel queries
# ═══════════════════════════════════════════════════════════════════════════════
@app.get("/api/analytics")
async def get_analytics(days: int = 30, _=Depends(require_admin)):
    sb = get_sb()
    try:
        def q_top_earners(): return sb.table("users").select("first_name,last_name,total_earned,games_played,games_won").order("total_earned", desc=True).limit(6).execute()
        def q_company_spend(): return sb.table("companies").select("name,total_spent,credit_balance,status").order("total_spent", desc=True).execute()
        def q_total_users(): return sb.table("users").select("id", count="exact").execute()
        def q_banned(): return sb.table("users").select("id", count="exact").eq("is_banned", True).execute()
        def q_streak(): return sb.table("users").select("id", count="exact").gt("current_streak", 1).execute()
        def q_wd_total(): return sb.table("withdrawals").select("id", count="exact").execute()
        def q_wd_done(): return sb.table("withdrawals").select("id", count="exact").eq("status", "completed").execute()
        def q_games(): return sb.table("games").select("total_paid_out,platform_fee_pct").execute()

        (r_earners, r_comp, r_users, r_banned,
         r_streak, r_wd_total, r_wd_done, r_games) = await gather(
            q_top_earners, q_company_spend, q_total_users, q_banned,
            q_streak, q_wd_total, q_wd_done, q_games
        )

        total_users = r_users.count or 0
        banned      = r_banned.count or 0
        streak      = r_streak.count or 0
        wd_total    = r_wd_total.count or 0
        wd_done     = r_wd_done.count or 0
        games       = r_games.data or []
        fee_income  = sum(float(g.get("total_paid_out") or 0) * float(g.get("platform_fee_pct") or 0) / 100 for g in games)

        return {
            "user_growth": [], "payout_trend": [], "question_accuracy_by_category": [], "level_stats": None,
            "top_earners": r_earners.data or [],
            "company_spend": r_comp.data or [],
            "health": {
                "ban_rate":                round(banned / total_users * 100, 1) if total_users else 0,
                "retention_rate":          round(streak  / total_users * 100, 1) if total_users else 0,
                "withdrawal_success_rate": round(wd_done  / wd_total   * 100, 1) if wd_total   else 0,
                "platform_fee_income":     fee_income,
            }
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Analytics error: %s", e)
        raise HTTPException(500, str(e))

# ─── Health check ─────────────────────────────────────────────────────────────
@app.get("/api/health")
async def health():
    try:
        sb = get_sb()
        await run(lambda: sb.table("users").select("id").limit(1).execute())
        return {"status": "ok", "db": "connected"}
    except Exception as e:
        return {"status": "ok", "db": "disconnected", "error": str(e)}

# ═══════════════════════════════════════════════════════════════════════════════
# QR CODES — admin generates; mini-app validates & scans
# ═══════════════════════════════════════════════════════════════════════════════
import secrets as _secrets

@app.get("/api/qr")
async def list_qr(_=Depends(require_admin), game_id: str = "", company_id: str = "", status: str = ""):
    sb = get_sb()
    def _q():
        q = sb.table("qr_codes").select(
            "*, games!qr_codes_game_id_fkey(title,game_date,status), companies!qr_codes_company_id_fkey(name)"
        ).order("created_at", desc=True).limit(200)
        if game_id:    q = q.eq("game_id", game_id)
        if company_id: q = q.eq("company_id", company_id)
        if status:     q = q.eq("status", status)
        return q.execute()
    res = await run(_q)
    return res.data or []

@app.post("/api/qr")
async def create_qr(body: QRCreateReq, _=Depends(require_admin)):
    sb = get_sb()
    admin = await run(lambda: sb.table("users").select("id").eq("role","admin").limit(1).execute())
    created_by = (admin.data or [{}])[0].get("id")
    token = "SHQ_" + _secrets.token_hex(16).upper()
    from datetime import datetime, timezone, timedelta
    expires_at = (datetime.now(timezone.utc) + timedelta(hours=body.expiry_hours)).isoformat() if body.expiry_hours > 0 else None
    
    # We want to support Telegram deep linking via startapp
    # If the base_url is a t.me link (e.g. https://t.me/ShamoET_bot/app)
    # The payload needs to be attached as startapp=TOKEN
    base_url = body.base_url.rstrip("?")
    qr_url = f"{base_url}?startapp={token}"
    
    payload = {
        "token": token, "game_id": body.game_id, "company_id": body.company_id or None,
        "created_by": created_by, "label": body.label, "qr_url": qr_url,
        "base_url": body.base_url, "max_scans": body.max_scans, "expires_at": expires_at,
        "status": "active", "scan_count": 0
    }
    res = await run(lambda: sb.table("qr_codes").insert(payload).execute())
    return (res.data or [{}])[0]

@app.post("/api/qr/validate")
async def validate_qr_token(body: QRScanReq):
    """Public endpoint — mini-app calls this to validate a scanned QR token."""
    sb = get_sb()
    from datetime import datetime, timezone
    res = await run(lambda: sb.table("qr_codes").select(
        "*, games!qr_codes_game_id_fkey(id,title,status,game_date,prize_pool_etb,prize_pool_remaining),"
        "companies!qr_codes_company_id_fkey(name)"
    ).eq("token", body.token).limit(1).execute())
    rows = res.data or []
    if not rows:
        return {"ok": False, "reason": "Invalid QR code"}
    qr = rows[0]
    if qr["status"] != "active":
        return {"ok": False, "reason": f"QR code is {qr['status']}"}
    if qr["expires_at"] and datetime.fromisoformat(qr["expires_at"].replace("Z","+00:00")) < datetime.now(timezone.utc):
        await run(lambda: sb.table("qr_codes").update({"status": "expired"}).eq("id", qr["id"]).execute())
        return {"ok": False, "reason": "QR code has expired"}
    if qr["max_scans"] > 0 and qr["scan_count"] >= qr["max_scans"]:
        return {"ok": False, "reason": "QR code scan limit reached"}
    game = qr.get("games") or {}
    if game.get("status") not in ("active", "scheduled"):
        return {"ok": False, "reason": f"Game is {game.get('status', 'unavailable')}"}
    return {
        "ok": True, "qr_code_id": qr["id"], "token": qr["token"],
        "game_id": game.get("id"), "game_title": game.get("title"),
        "game_date": game.get("game_date"),
        "prize_pool_etb": game.get("prize_pool_etb"),
        "company": (qr.get("companies") or {}).get("name"),
        "label": qr.get("label"),
    }

from fastapi.responses import StreamingResponse
import qrcode
import io

@app.get("/api/qr/{qid}/image")
async def get_qr_image(qid: str):
    """Generate and return a QR code image (PNG) dynamically."""
    sb = get_sb()
    res = await run(lambda: sb.table("qr_codes").select("qr_url").eq("id", qid).limit(1).execute())
    rows = res.data or []
    if not rows:
        raise HTTPException(404, "QR code not found")
    qr_url = rows[0]["qr_url"]
    
    def _make_qr():
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_H,
            box_size=10,
            border=2,
        )
        qr.add_data(qr_url)
        qr.make(fit=True)
        img = qr.make_image(fill_color="#08070A", back_color="white")
        img_byte_arr = io.BytesIO()
        img.save(img_byte_arr, format='PNG')
        img_byte_arr.seek(0)
        return img_byte_arr

    img_byte_arr = await asyncio.to_thread(_make_qr)
    return StreamingResponse(img_byte_arr, media_type="image/png")

@app.post("/api/qr/scan")
async def record_qr_scan(body: QRScanReq):
    """Public — record a scan after successful validation."""
    sb = get_sb()
    # get qr_code_id by token
    qr_res = await run(lambda: sb.table("qr_codes").select("id,game_id").eq("token", body.token).limit(1).execute())
    qr_rows = qr_res.data or []
    if not qr_rows:
        raise HTTPException(404, "QR code not found")
    qr = qr_rows[0]
    scan = {
        "qr_code_id": qr["id"], "qr_token": body.token, "game_id": qr["game_id"],
        "user_id": body.user_id or None, "telegram_id": body.telegram_id,
        "phone_number": body.phone_number, "entry_status": "entered"
    }
    try:
        res = await run(lambda: sb.table("qr_scans").insert(scan).execute())
        return (res.data or [{}])[0]
    except Exception as e:
        if "idx_qr_scans_once" in str(e):
            return {"entry_status": "already_scanned", "message": "Already entered this game"}
        raise HTTPException(400, str(e))

@app.post("/api/qr/{qid}/revoke")
async def revoke_qr(qid: str, _=Depends(require_admin)):
    sb = get_sb()
    await run(lambda: sb.table("qr_codes").update({"status": "revoked"}).eq("id", qid).execute())
    return {"status": "revoked"}

# ═══════════════════════════════════════════════════════════════════════════════
# GAME SESSIONS & TRIVIA FLOW  (public — mini-app)
# ═══════════════════════════════════════════════════════════════════════════════
@app.post("/api/game/session/start")
async def start_session(body: SessionStartReq):
    sb = get_sb()
    # Check if already has a session
    existing = await run(lambda: sb.table("game_sessions")
        .select("*").eq("user_id", body.user_id).eq("game_id", body.game_id).limit(1).execute())
    if existing.data:
        sess = existing.data[0]
        if sess.get("cooldown_until"):
            from datetime import datetime, timezone
            cd = datetime.fromisoformat(sess["cooldown_until"].replace("Z","+00:00"))
            if cd > datetime.now(timezone.utc):
                return {"session": sess, "cooldown": True, "cooldown_until": sess["cooldown_until"]}
        return {"session": sess, "cooldown": False}
    # Get qr_code_id if token provided
    qr_code_id = None
    if body.qr_token:
        qr_r = await run(lambda: sb.table("qr_codes").select("id").eq("token", body.qr_token).single().execute())
        if qr_r.data: qr_code_id = qr_r.data["id"]
    # Get game's player_cap_pct and prize_pool_remaining
    game_r = await run(lambda: sb.table("games").select("prize_pool_remaining,player_cap_pct").eq("id", body.game_id).single().execute())
    game = game_r.data or {}
    remaining = float(game.get("prize_pool_remaining") or 0)
    cap_pct = float(game.get("player_cap_pct") or 30)
    player_cap_etb = round(remaining * cap_pct / 100, 2)
    sess_payload = {"game_id": body.game_id, "user_id": body.user_id,
        "qr_code_id": qr_code_id, "player_cap_etb": player_cap_etb,
        "current_question": 1, "questions_answered": 0, "wrong_count": 0, "is_active": True}
    res = await run(lambda: sb.table("game_sessions").insert(sess_payload).execute())
    return {"session": (res.data or [{}])[0], "cooldown": False}

@app.get("/api/game/{game_id}/questions")
async def get_game_questions(game_id: str):
    """Return the ordered questions for a game with answer options."""
    sb = get_sb()
    gq_res = await run(lambda: sb.table("game_questions")
        .select("sort_order, questions!game_questions_question_id_fkey(id,icon,question_text,category,explanation)")
        .eq("game_id", game_id).order("sort_order").execute())
    rows = gq_res.data or []
    q_ids = [r["questions"]["id"] for r in rows if r.get("questions")]
    if not q_ids: return []
    opts_res = await run(lambda: sb.table("answer_options").select("*").in_("question_id", q_ids).order("sort_order").execute())
    opts_map: Dict[str, list] = {}
    for o in (opts_res.data or []): opts_map.setdefault(o["question_id"], []).append(o)
    questions = []
    for r in rows:
        q = r.get("questions")
        if q:
            q["sort_order"] = r["sort_order"]
            q["options"] = opts_map.get(q["id"], [])
            questions.append(q)
    return questions

@app.post("/api/game/answer")
async def submit_answer(body: AnswerReq):
    """Record a player's answer, update session wrong_count, trigger cooldown if needed."""
    sb = get_sb()
    # Check correct answer
    is_correct = False
    status_val = "timeout"
    if body.selected_option_id:
        opt_res = await run(lambda: sb.table("answer_options")
            .select("is_correct").eq("id", body.selected_option_id).single().execute())
        is_correct = bool((opt_res.data or {}).get("is_correct", False))
        status_val = "correct" if is_correct else "wrong"
    ans_payload = {
        "session_id": body.session_id, "user_id": body.user_id, "game_id": body.game_id,
        "question_id": body.question_id, "selected_option_id": body.selected_option_id,
        "question_number": body.question_number, "is_correct": is_correct,
        "status": status_val, "time_taken_ms": body.time_taken_ms
    }
    await run(lambda: sb.table("round_answers").insert(ans_payload).execute())
    # Get updated session (triggers updated wrong_count via DB trigger)
    sess_res = await run(lambda: sb.table("game_sessions").select("*").eq("id", body.session_id).single().execute())
    return {"is_correct": is_correct, "status": status_val, "session": sess_res.data}

@app.post("/api/game/spin")
async def record_spin(body: SpinReq):
    """Record a spin result (credits user balance via DB trigger)."""
    sb = get_sb()
    spin_payload = {
        "session_id": body.session_id, "user_id": body.user_id, "game_id": body.game_id,
        "question_number": body.question_number, "segment_label": body.segment_label,
        "amount_etb": body.amount_etb
    }
    res = await run(lambda: sb.table("spin_results").insert(spin_payload).execute())
    # Update session's current_question and questions_answered
    await run(lambda: sb.table("game_sessions").update({
        "current_question": body.question_number + 1,
        "questions_answered": body.question_number
    }).eq("id", body.session_id).execute())
    # Get updated user balance
    user_res = await run(lambda: sb.table("users").select("balance,total_earned").eq("id", body.user_id).single().execute())
    return {"spin": (res.data or [{}])[0], "user": user_res.data}

@app.post("/api/game/session/{sid}/end")
async def end_session(sid: str, user_id: str):
    sb = get_sb()
    await run(lambda: sb.table("game_sessions").update({
        "is_active": False, "is_completed": True,
        "ended_at": datetime.now(timezone.utc).isoformat()
    }).eq("id", sid).execute())
    sess = await run(lambda: sb.table("game_sessions").select("*").eq("id", sid).single().execute())
    return sess.data

# ═══════════════════════════════════════════════════════════════════════════════
# COMPANY DEPOSITS — admin manages, triggers update prize pool
# ═══════════════════════════════════════════════════════════════════════════════
@app.get("/api/deposits")
async def list_deposits(_=Depends(require_admin), status: str = "", company_id: str = ""):
    sb = get_sb()
    def _q():
        q = sb.table("company_deposits").select(
            "*, companies(name), games(title)"
        ).order("created_at", desc=True).limit(200)
        if status:     q = q.eq("status", status)
        if company_id: q = q.eq("company_id", company_id)
        return q.execute()
    res = await run(_q)
    return res.data or []

@app.post("/api/deposits/{did}/approve")
async def approve_deposit(did: str, body: DepositApproveReq, _=Depends(require_admin)):
    sb = get_sb()
    admin = await run(lambda: sb.table("users").select("id").eq("role","admin").limit(1).execute())
    confirmed_by = (admin.data or [{}])[0].get("id")
    await run(lambda: sb.table("company_deposits").update({
        "status": "confirmed", "notes": body.notes,
        "confirmed_by": confirmed_by
    }).eq("id", did).eq("status", "pending").execute())
    return {"status": "confirmed"}

@app.post("/api/deposits/{did}/reject")
async def reject_deposit(did: str, body: DepositRejectReq, _=Depends(require_admin)):
    sb = get_sb()
    await run(lambda: sb.table("company_deposits").update({
        "status": "rejected", "rejected_reason": body.reason
    }).eq("id", did).eq("status", "pending").execute())
    return {"status": "rejected"}

# ═══════════════════════════════════════════════════════════════════════════════
# PLAYER WITHDRAW (public — mini-app submits)
# ═══════════════════════════════════════════════════════════════════════════════
@app.post("/api/player/withdraw")
async def player_withdraw(body: WithdrawReq):
    sb = get_sb()
    # Get fee config
    cfg = await run(lambda: sb.table("platform_config").select("key,value")
        .in_("key", ["withdrawal_fee_pct","min_withdrawal_etb"]).execute())
    cfg_map = {r["key"]: r["value"] for r in (cfg.data or [])}
    fee_pct = float(cfg_map.get("withdrawal_fee_pct", 5))
    min_etb = float(cfg_map.get("min_withdrawal_etb", 50))
    if body.amount_requested < min_etb:
        raise HTTPException(400, f"Minimum withdrawal is {min_etb} ETB")
    # Check user balance
    u_res = await run(lambda: sb.table("users").select("balance").eq("id", body.user_id).single().execute())
    if not u_res.data: raise HTTPException(404, "User not found")
    balance = float(u_res.data.get("balance") or 0)
    if balance < body.amount_requested:
        raise HTTPException(400, f"Insufficient balance ({balance:.2f} ETB)")
    fee_etb = round(body.amount_requested * fee_pct / 100, 2)
    amount_paid = round(body.amount_requested - fee_etb, 2)
    payload = {
        "user_id": body.user_id,
        "amount_requested": body.amount_requested, "fee_pct": fee_pct,
        "fee_etb": fee_etb, "amount_paid": amount_paid,
        "phone_number": body.phone_number, "bank_account": body.bank_account,
        "status": "pending"
    }
    res = await run(lambda: sb.table("withdrawals").insert(payload).execute())
    return (res.data or [{}])[0]

@app.get("/api/player/{uid}/withdrawals")
async def player_withdrawals(uid: str):
    sb = get_sb()
    res = await run(lambda: sb.table("withdrawals").select("*")
        .eq("user_id", uid).order("requested_at", desc=True).limit(20).execute())
    return res.data or []

@app.get("/api/player/{uid}/spins")
async def player_spin_history(uid: str):
    sb = get_sb()
    res = await run(lambda: sb.table("spin_results").select(
        "*, games!spin_results_game_id_fkey(title,game_date)"
    ).eq("user_id", uid).order("spun_at", desc=True).limit(30).execute())
    return res.data or []

# ─── Startup: pre-warm the singleton client ───────────────────────────────────
@app.on_event("startup")
async def startup():
    try:
        get_sb()   # initialize singleton now, not on first request
        logger.info("✅ Supabase singleton client ready")
    except Exception as e:
        logger.warning("⚠️  Supabase init warning: %s", e)

