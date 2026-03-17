# Backend

Node.js backend for the Project Tracker (DAAO Apps).

## Setup

```bash
npm install
```

## Run

```bash
node server.js
```

Or with auto-reload (if using nodemon):

```bash
npx nodemon server.js
```

## Railway deployment

After pushing code changes (e.g. CORS updates in `server.js`), **redeploy** the backend on Railway so the live site uses the latest version. The Flutter web app needs CORS headers from this server to connect; without them you'll see a red cloud (connection failed).

1. Push to GitHub (backend is in `backend/`).
2. In [Railway](https://railway.app), trigger a redeploy for the project (e.g. from the GitHub connection or Deploy button).

## Environment

Create a `.env` file for environment variables (see `.env.example` if provided). Do not commit `.env`.
