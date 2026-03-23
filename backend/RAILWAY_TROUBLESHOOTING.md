# Railway Build Error: "secret SUPABASE_SERVICE_ROLE_KEY: not found"

## The Problem
Railway is trying to use environment variables during the **build phase**, but they should only be used at **runtime**. This error typically happens when Railway thinks the variables are needed for building.

## Solution 1: Verify Variables Are Set Correctly

### Step 1: Check Railway Variables Tab
1. Go to Railway Dashboard → Your Project → Your Backend Service
2. Click **"Variables"** tab
3. Verify you see these 3 variables:
   - `SUPABASE_URL`
   - `SUPABASE_SERVICE_ROLE_KEY`
   - `FIREBASE_SERVICE_ACCOUNT_JSON`

### Step 2: Check Variable Names (Case-Sensitive!)
- ✅ Correct: `SUPABASE_SERVICE_ROLE_KEY`
- ❌ Wrong: `supabase_service_role_key` (lowercase)
- ❌ Wrong: `SUPABASE_SERVICE_ROLE` (missing _KEY)

### Step 3: Check Variable Values
- Make sure values don't have extra quotes or spaces
- `SUPABASE_URL` should be: `https://xxxxx.supabase.co` (no quotes)
- `SUPABASE_SERVICE_ROLE_KEY` should be the long JWT string (no quotes)
- `FIREBASE_SERVICE_ACCOUNT_JSON` should be the entire JSON on one line

---

## Solution 2: Use Railway's Environment Variable UI

### Method A: Add Variables One by One
1. In Railway Dashboard → Your Service → **Variables** tab
2. Click **"+ New Variable"** or **"Add Variable"**
3. For each variable:
   - **Name**: Type exactly (case-sensitive): `SUPABASE_SERVICE_ROLE_KEY`
   - **Value**: Paste the value (no quotes)
   - Click **"Add"** or **"Save"**
4. Repeat for all 3 variables

### Method B: Use Railway CLI (Alternative)
If you have Railway CLI installed:
```bash
railway variables set SUPABASE_SERVICE_ROLE_KEY="your-key-here"
railway variables set SUPABASE_URL="https://xxxxx.supabase.co"
railway variables set FIREBASE_SERVICE_ACCOUNT_JSON='{"type":"service_account",...}'
```

---

## Solution 3: Check Service Settings

### Verify Service Type
1. In Railway, go to your backend service
2. Click **"Settings"** tab
3. Check **"Build Command"**: Should be `npm install` or empty (auto-detected)
4. Check **"Start Command"**: Should be `node server.js` or `npm start`

### Verify Root Directory
1. In **Settings** → **"Root Directory"**
2. Should be: `backend` (if your service is in a subfolder)
3. Or leave empty if `server.js` is in the root

---

## Solution 4: Force Redeploy After Adding Variables

After adding variables:
1. Go to **"Deployments"** tab
2. Click **"Redeploy"** on the latest deployment
3. Or click **"Deploy"** → **"Deploy Latest"**
4. Wait for build to complete
5. Check **"Logs"** tab for errors

---

## Solution 5: Check for Hidden Characters or Formatting

### Copy Values Correctly
1. Open your local `.env` file
2. Copy each value **one at a time**
3. Paste into Railway **without**:
   - Extra spaces at start/end
   - Quotes (unless the value itself needs quotes)
   - Line breaks (especially for FIREBASE_SERVICE_ACCOUNT_JSON)

### For FIREBASE_SERVICE_ACCOUNT_JSON
The JSON must be on **ONE LINE**. If your `.env` has it on multiple lines:
1. Copy the entire JSON
2. Use an online tool like [jsonformatter.org](https://jsonformatter.org) → "Minify"
3. Copy the minified (one-line) version
4. Paste into Railway

---

## Solution 6: Verify Railway Project Structure

### Check Your Service Configuration
1. In Railway Dashboard → Your Project
2. Make sure you have a **backend service** (not just a frontend service)
3. The service should be connected to your backend code (either via GitHub repo or manual upload)

### If Using GitHub
1. Go to **Settings** → **"Source"**
2. Verify it's connected to the correct repository
3. Verify the **"Root Directory"** is set to `backend` (if your backend code is in a `backend` folder)

---

## Solution 7: Create a New Service (Last Resort)

If nothing works, create a fresh service:

1. In Railway Dashboard → Your Project
2. Click **"+ New"** → **"GitHub Repo"** or **"Empty Service"**
3. Connect to your backend code
4. Set **Root Directory** to `backend` (if needed)
5. Add all 3 environment variables in **Variables** tab
6. Set **Start Command** to `node server.js`
7. Deploy

---

## Quick Checklist

Before redeploying, verify:
- [ ] All 3 variables are in Railway's **Variables** tab
- [ ] Variable names are **exactly** correct (case-sensitive)
- [ ] Values don't have extra quotes or spaces
- [ ] `FIREBASE_SERVICE_ACCOUNT_JSON` is on one line
- [ ] Service **Root Directory** is correct
- [ ] **Start Command** is `node server.js` or `npm start`

---

## Still Not Working?

1. **Check Railway Logs**: Go to **Logs** tab and look for the exact error message
2. **Check Railway Status**: Go to [status.railway.app](https://status.railway.app) to see if Railway has issues
3. **Contact Railway Support**: Use Railway's support chat in the dashboard

---

## Example: What Railway Variables Tab Should Look Like

```
┌─────────────────────────────┬─────────────────────────────────────────┐
│ Variable Name               │ Value                                    │
├─────────────────────────────┼─────────────────────────────────────────┤
│ SUPABASE_URL                │ https://xxxxx.supabase.co                │
│ SUPABASE_SERVICE_ROLE_KEY   │ eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...  │
│ FIREBASE_SERVICE_ACCOUNT... │ {"type":"service_account","project_id"...}│
└─────────────────────────────┴─────────────────────────────────────────┘
```

**Note**: The values shown above are truncated for display. Your actual values should be complete.
