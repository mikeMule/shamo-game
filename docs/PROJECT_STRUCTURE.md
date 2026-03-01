# SHAMO — Project structure

```
shamo/
├── game/                  ← Mini App (index.html is here)
│   └── index.html         ← Telegram Mini App entry (login + spinner)
├── admin/                 ← Admin panel (static HTML)
│   ├── index.html
│   ├── login.html
│   ├── _shared.js
│   ├── companies.html
│   ├── games.html
│   ├── questions.html
│   ├── qr-manager.html
│   ├── users.html
│   ├── withdrawals.html
│   ├── settings.html
│   ├── deposits.html
│   └── analytics.html
├── migrations/            ← SQL schema migrations
├── docs/                  ← Documentation
├── api.py                 ← FastAPI backend (serves /api, /game, /admin)
├── bot.py                 ← Telegram bot
├── ecosystem.config.js    ← PM2 process config (optional)
├── start_services.ps1      ← Windows launcher (API + bot)
├── .env                   ← Secrets (copy from .env.example.local or .env.example.vps)
├── .env.example           ← Generic template
├── .env.example.local     ← Local development
├── .env.example.vps       ← VPS / production
└── requirements.txt
```

## URL layout

| Path | Served from | Description |
|------|-------------|-------------|
| `/` | redirect | → `/game/index.html` |
| `/game/*` | `game/` | Mini App static files |
| `/admin/*` | `admin/` | Admin panel static files |
| `/api/*` | `api.py` | REST API |

## Running

- **API + Bot (Windows):** `.\start_services.ps1`
- **API only:** `uvicorn api:app --port 8001 --reload`
- **PM2:** `pm2 start ecosystem.config.js`

## Paths and config

- **api.py** loads `.env` from project root (`Path(__file__).parent / ".env"`). Serves `/game` from `game/`, `/admin` from `admin/`. Root `/` redirects to `/game/index.html`.
- **bot.py** loads `.env` from project root (same dir as `bot.py`). Uses `API_BASE_URL` (e.g. `http://127.0.0.1:8001`) and `SHAMO_WEBAPP_URL` (e.g. `https://selamdelivery.xyz/shamo/game/index.html`).
- **game/index.html** uses `window.location.origin` as API base (same host); optional `?api_base=...` for local override.
- **admin** uses same-origin `/api` when served from the API host (works on VPS and local).
