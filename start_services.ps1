# ─────────────────────────────────────────────────
#  SHAMO Launcher  —  runs API + Bot in one window
# ─────────────────────────────────────────────────

$ProjectDir = "C:\PY-BOT\AI-PROJECT\Shamo"
$PythonExe = "$ProjectDir\.venv\Scripts\python.exe"

Set-Location -Path $ProjectDir

if (-Not (Test-Path -Path $PythonExe)) {
    Write-Host "ERROR: venv not found at $ProjectDir\.venv" -ForegroundColor Red
    Write-Host "Run:  python -m venv .venv" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"; Exit
}

Write-Host "Installing / updating dependencies..." -ForegroundColor Yellow

# Install each package separately so one failure does not block the rest
$packages = @(
    "python-dotenv>=1.0.1",
    "fastapi>=0.111.0",
    "uvicorn[standard]>=0.29.0",
    "psycopg2-binary>=2.9.10",
    "python-telegram-bot>=21.4",
    "supabase>=2.0.0"
)

foreach ($pkg in $packages) {
    Write-Host "  Installing $pkg ..." -ForegroundColor DarkCyan
    & $PythonExe -m pip install --quiet "$pkg"
}

Write-Host ""
Write-Host "Killing any existing Python processes to prevent bot conflicts..." -ForegroundColor Yellow
Stop-Process -Name python -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

Write-Host "Starting FastAPI server + Telegram Bot (in-process) on http://localhost:8001 ..." -ForegroundColor Cyan
Write-Host "  Swagger docs → http://localhost:8001/api/docs"  -ForegroundColor Yellow
Write-Host ""
Write-Host "  Press Ctrl+C to stop everything." -ForegroundColor Gray
Write-Host "  NOTE: Hot-reload is disabled to prevent duplicate bot instances." -ForegroundColor Gray
Write-Host "================================================" -ForegroundColor Magenta

try {
    # Run uvicorn WITHOUT --reload to prevent spawning multiple bot instances.
    # Bot is started in-process by api.py lifespan for broadcast support.
    & $PythonExe -m uvicorn api:app --host 0.0.0.0 --port 8001
}
finally {
    Write-Host "`nShutting down..." -ForegroundColor Yellow
    Write-Host "All services stopped." -ForegroundColor Green
}
