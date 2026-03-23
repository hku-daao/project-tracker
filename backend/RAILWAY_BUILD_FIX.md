# Fix Railway Build Error: "failed to solve: secret SUPABASE_SERVICE_ROLE_KEY: not found"

## What the logs actually show (Railpack / BuildKit)

If your export looks like **Railpack 0.20.0** and the plan includes `"secrets":["*"]` on the **build** step, BuildKit runs layers that **require every listed secret** (including `SUPABASE_SERVICE_ROLE_KEY`). The failure in logs is often on an early layer (e.g. **install apt packages: libatomic1**) with:

`ERROR: failed to build: failed to solve: secret SUPABASE_SERVICE_ROLE_KEY: not found`

That means the secret was **not available to the image build**, not necessarily that you forgot it in the dashboard—Railway can scope variables to **runtime only** while Railpack still expects them at **build** time.

### Recommended fix: Dockerfile builder (no secrets at build)

This repo’s `backend/` includes:

- `Dockerfile` – `npm install` only needs `package.json` / lockfile (no Supabase/Firebase env).
- `railway.json` – `"builder": "DOCKERFILE"`, `"dockerfilePath": "Dockerfile"`.
- `.dockerignore` – avoids copying `node_modules` / `.env` into the image.

**Deploy:** Commit and push these files, set **Root Directory** to `backend`, redeploy. Supabase/Firebase variables stay **Variables** on the service; they are read when `node server.js` runs, not during `docker build`.

If logs still say **Railpack**, confirm the latest commit is deployed and that **Settings → Build** is using Dockerfile (not falling back to Railpack).

---

## The Problem (summary)
Railway’s **Railpack** builder can require secrets during the **Docker build phase**. Your app only needs those values at **runtime**. If variables are not exposed to the build (or Railpack lists them as build secrets), the build fails even when Variables look correct in the UI.

## Solution: Verify Variable Configuration in Railway

### Step 1: Double-Check Variables Are Actually Set

1. Go to Railway Dashboard → Your Project → **Backend Service**
2. Click **"Variables"** tab
3. **Verify each variable individually**:
   - Click on `SUPABASE_SERVICE_ROLE_KEY` to edit/view it
   - Make sure the value is actually there (not empty)
   - Make sure there are no extra spaces or hidden characters
4. Do this for all 3 variables

### Step 2: Check Variable Visibility

In Railway, variables can be:
- **Public** (visible in build logs - not recommended for secrets)
- **Secret** (hidden, only available at runtime)

For `SUPABASE_SERVICE_ROLE_KEY` and `FIREBASE_SERVICE_ACCOUNT_JSON`:
- They should be marked as **"Secret"** or **"Sensitive"**
- But Railway should still make them available at runtime

### Step 3: Try Removing and Re-adding Variables

Sometimes Railway's cache can cause issues:

1. **Delete all 3 variables** from Railway Variables tab
2. **Wait 30 seconds**
3. **Add them back one by one**:
   - Add `SUPABASE_URL` first
   - Save and wait
   - Add `SUPABASE_SERVICE_ROLE_KEY` second
   - Save and wait
   - Add `FIREBASE_SERVICE_ACCOUNT_JSON` last
   - Save
4. **Redeploy** after all are added

### Step 4: Check Railway Service Settings

1. Go to **Settings** tab in your backend service
2. Verify:
   - **Root Directory**: `backend` ✅
   - **Start Command**: `node server.js` ✅
   - **Build Command**: Should be empty or `npm install` (not referencing env vars)
3. If **Build Command** has anything referencing the env vars, remove it

### Step 5: Try a Fresh Deployment

1. Go to **"Deployments"** tab
2. Click **"Deploy"** → **"Deploy Latest"** (or create a new deployment)
3. Watch the build logs carefully
4. The error should appear early in the build process

### Step 6: Check Build Logs for Exact Error

The build logs will show exactly where it's failing. Look for:
- Which phase is failing (setup, install, or start)
- The exact error message
- Any references to Docker or Nixpacks

---

## Alternative Solution: Use Railway's Environment Variable Reference

If the above doesn't work, try setting variables at the **Project level** instead of Service level:

1. Go to Railway Dashboard → **Your Project** (not the service)
2. Click **"Variables"** tab (at project level)
3. Add the 3 variables there
4. Railway should make them available to all services

**Note**: This is less secure but might work if service-level variables aren't working.

---

## Nuclear Option: Recreate the Service

If nothing works:

1. **Note down** your Railway service URL
2. **Delete** the current backend service
3. **Create a new service**:
   - Click **"+ New"** → **"GitHub Repo"** or **"Empty Service"**
   - Connect to your backend code
   - Set **Root Directory** to `backend`
   - Set **Start Command** to `node server.js`
4. **Add all 3 environment variables** in the Variables tab
5. **Deploy**

---

## Debug: Check What Railway Sees

1. In Railway, go to your service → **Variables** tab
2. Take a screenshot or note down:
   - How many variables are listed?
   - What are their exact names?
   - Are they marked as "Secret" or "Public"?
3. Check if there are any **duplicate variables** (same name listed twice)

---

## Common Railway Issues

### Issue 1: Variables Not Persisting
- **Symptom**: You add variables but they disappear
- **Fix**: Make sure you click "Save" or "Add" after entering each variable

### Issue 2: Wrong Service
- **Symptom**: Variables are in a different service
- **Fix**: Make sure you're adding to the **backend service**, not a frontend service

### Issue 3: Build Cache
- **Symptom**: Old build configuration is cached
- **Fix**: Try **"Clear Build Cache"** in Settings → Advanced

---

## Still Not Working?

If you've tried everything:
1. **Contact Railway Support** via their dashboard chat
2. **Share this information**:
   - Error message: "failed to solve: secret SUPABASE_SERVICE_ROLE_KEY: not found"
   - Your service configuration (Root Directory, Start Command)
   - Confirmation that variables are set in Variables tab
   - Build logs showing where it fails

3. **Alternative**: Try deploying to a different platform temporarily:
   - **Render.com** (similar to Railway)
   - **Fly.io**
   - **Heroku** (if you have an account)

---

## Quick Test: Verify Variables Are Accessible

Once the service is running (if you can get it to deploy), you can test if variables are accessible:

1. Add a test endpoint to `server.js`:
```javascript
if (path === '/api/test-env' && req.method === 'GET') {
  sendJson(res, 200, {
    hasSupabaseUrl: !!SUPABASE_URL,
    hasSupabaseKey: !!SUPABASE_SERVICE_ROLE_KEY,
    hasFirebaseJson: !!FIREBASE_SERVICE_ACCOUNT_JSON,
  });
  return;
}
```

2. Call: `https://your-railway-url.up.railway.app/api/test-env`
3. Should return all `true` if variables are set

---

## Final Checklist Before Redeploying

- [ ] All 3 variables are in the **Variables** tab of the **backend service**
- [ ] Variable names are **exactly** correct (case-sensitive)
- [ ] Values don't have extra quotes or spaces
- [ ] `FIREBASE_SERVICE_ACCOUNT_JSON` is on one line
- [ ] Root Directory is set to `backend`
- [ ] Start Command is `node server.js`
- [ ] Build Command is empty or just `npm install`
- [ ] No duplicate variables exist
- [ ] You've tried deleting and re-adding variables
