# Deployment Quick Checklist

Use this checklist when deploying to Railway or Render.

## Pre-Deployment Checklist

- [ ] Have Supabase URL ready
- [ ] Have Supabase Service Role Key ready (not anon key!)
- [ ] Have Firebase service account JSON file downloaded
- [ ] Converted Firebase JSON to single line (use `convert-firebase-json.ps1` or `convert-firebase-json.sh`)
- [ ] GitHub repository is ready and pushed

## Environment Variables Checklist

Copy these values into Railway/Render:

- [ ] `SUPABASE_URL` = `https://YOUR_PROJECT_REF.supabase.co`
- [ ] `SUPABASE_SERVICE_ROLE_KEY` = `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...`
- [ ] `FIREBASE_SERVICE_ACCOUNT_JSON` = `{"type":"service_account",...}` (single line, no breaks)
- [ ] `ADMIN_EMAIL` = `test-admin@test.com` (optional)
- [ ] `PORT` = (usually auto-set by platform, optional)

## Railway Deployment Steps

1. [ ] Login to [railway.app](https://railway.app) with GitHub
2. [ ] Create new project → Deploy from GitHub repo
3. [ ] Select your repository
4. [ ] Set Root Directory to `backend` (if needed)
5. [ ] Set Start Command to `npm start`
6. [ ] Add all environment variables in "Variables" tab
7. [ ] Wait for deployment to complete (status: "Active")
8. [ ] Copy the Railway URL (e.g., `https://xxx.up.railway.app`)
9. [ ] Update Flutter `lib/config/api_config.dart` with Railway URL
10. [ ] Test: Open `https://YOUR-RAILWAY-URL/health` in browser

## Render Deployment Steps

1. [ ] Login to [render.com](https://render.com) with GitHub
2. [ ] New + → Web Service
3. [ ] Connect GitHub repository
4. [ ] Set Name: `project-tracker-backend`
5. [ ] Set Root Directory: `backend`
6. [ ] Set Start Command: `npm start`
7. [ ] Add all environment variables
8. [ ] Click "Create Web Service"
9. [ ] Wait for status: "Live"
10. [ ] Copy the Render URL (e.g., `https://xxx.onrender.com`)
11. [ ] Update Flutter `lib/config/api_config.dart` with Render URL
12. [ ] Test: Open `https://YOUR-RENDER-URL/health` in browser

## Post-Deployment Verification

- [ ] Health endpoint works: `GET /health` returns `{"ok":true,...}`
- [ ] Backend logs show "Server running at http://localhost:PORT"
- [ ] No errors in deployment logs
- [ ] Flutter app can connect to backend (check network tab)
- [ ] `/api/me` endpoint works with Firebase token (test from Flutter app)

## Common Issues & Fixes

| Issue | Fix |
|-------|-----|
| 503 "Supabase not configured" | Check `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are set |
| Firebase Admin init failed | Ensure `FIREBASE_SERVICE_ACCOUNT_JSON` is single line |
| 401 Unauthorized | Verify Firebase JSON is correct and valid |
| Port binding error | Platform sets PORT automatically, code uses `process.env.PORT \|\| 3000` |
| Health works, `/api/me` fails | Check logs for Firebase Admin initialization errors |

## Quick Commands

### Convert Firebase JSON (Windows PowerShell):
```powershell
.\convert-firebase-json.ps1 path\to\firebase-service-account.json
```

### Convert Firebase JSON (Mac/Linux):
```bash
chmod +x convert-firebase-json.sh
./convert-firebase-json.sh path/to/firebase-service-account.json
```

### Test Backend Locally:
```bash
cd backend
npm install
npm start
# Should see: "Server running at http://localhost:3000"
# Test: http://localhost:3000/health
```

---

**Need help?** Check `DEPLOYMENT.md` for detailed instructions.
