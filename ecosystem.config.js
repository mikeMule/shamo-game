/**
 * PM2 ecosystem config for SHAMO (API + optional bot).
 * Port from .env (PORT): set PORT in .env or when starting: PORT=8002 pm2 start ecosystem.config.js
 */
try { require('dotenv').config({ path: require('path').join(__dirname, '.env') }); } catch (_) {}
const PORT = process.env.PORT || 8001;

module.exports = {
  apps: [
    {
      name: "shamo-api",
      script: "-m",
      args: `uvicorn api:app --host 0.0.0.0 --port ${PORT}`,
      interpreter: "python",
      cwd: __dirname,
      env: { PYTHONUNBUFFERED: "1", PORT: String(PORT) },
      instances: 1,
      autorestart: true,
      watch: false,
    },
  ],
};
