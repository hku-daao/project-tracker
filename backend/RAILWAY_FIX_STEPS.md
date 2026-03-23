# Fix Railway Build Error: "secret SUPABASE_SERVICE_ROLE_KEY: not found"

## The Issue
Railway is trying to access the environment variable during the **Docker build phase**, but it's not finding it. This usually means:
1. The variable isn't set in Railway, OR
2. The variable is set in the wrong place (service vs project level)

## Step-by-Step Fix

### Step 1: Verify You're Adding Variables to the Correct Service

1. Go to [Railway Dashboard](https://railway.app)
2. Click on your **Project** (e.g., "Project Tracker")
3. You should see your **backend service** listed
4. **Click on the backend service** (the one that runs `node server.js`)
5. Make sure you're NOT adding variables to the project level or a different service

### Step 2: Add Variables to the Service (Not Project)

1. With your **backend service** selected, click the **"Variables"** tab
   - If you don't see a "Variables" tab, click **"Settings"** first, then look for **"Variables"**
2. You should see a list of existing variables (or it might be empty)
3. Click **"+ New Variable"** or **"Add Variable"** button

### Step 3: Add Each Variable One by One

**Variable 1: SUPABASE_URL**
- Click **"+ New Variable"**
- **Name**: Type exactly: `SUPABASE_URL` (all caps, underscore)
- **Value**: `https://cjeyowmqhluiilrhkvmj.supabase.co`
- Click **"Add"** or **"Save"**

**Variable 2: SUPABASE_SERVICE_ROLE_KEY**
- Click **"+ New Variable"** again
- **Name**: Type exactly: `SUPABASE_SERVICE_ROLE_KEY` (all caps, underscores)
- **Value**: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNqZXlvd21xaGx1aWlscmhrdm1qIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MzcyNzkzOSwiZXhwIjoyMDg5MzAzOTM5fQ.WPgXPTbsJH8zj5IzSDVDPPz0_Q-4iGp30qu68FvVMJM`
- Click **"Add"** or **"Save"**

**Variable 3: FIREBASE_SERVICE_ACCOUNT_JSON**
- Click **"+ New Variable"** again
- **Name**: Type exactly: `FIREBASE_SERVICE_ACCOUNT_JSON` (all caps, underscores)
- **Value**: Copy the entire JSON from your `.env` file (it's already on one line)
- Click **"Add"** or **"Save"**

### Step 4: Verify Variables Are Saved

After adding all 3, you should see them listed in the Variables tab:
```
SUPABASE_URL
SUPABASE_SERVICE_ROLE_KEY
FIREBASE_SERVICE_ACCOUNT_JSON
```

### Step 5: Trigger a New Deployment

1. Go to **"Deployments"** tab
2. Click **"Redeploy"** on the latest deployment
3. Or click **"Deploy"** → **"Deploy Latest"**
4. Wait for the build to start

### Step 6: Watch the Build

1. Stay on the **"Deployments"** tab
2. Click on the new deployment that's building
3. Watch the build logs
4. The error should be gone if variables are set correctly

---

## Common Mistakes to Avoid

### ❌ Wrong: Adding at Project Level
- Don't add variables to the **Project** settings
- Add them to the **Service** (backend service) settings

### ❌ Wrong: Wrong Variable Name
- ❌ `supabase_service_role_key` (lowercase)
- ❌ `SUPABASE_SERVICE_ROLE` (missing _KEY)
- ✅ `SUPABASE_SERVICE_ROLE_KEY` (correct)

### ❌ Wrong: Adding Quotes
- ❌ Value: `"https://xxxxx.supabase.co"` (with quotes)
- ✅ Value: `https://xxxxx.supabase.co` (no quotes)

### ❌ Wrong: Multiple Services
- Make sure you're adding to the **backend service**, not a frontend service
- If you have multiple services, identify which one runs `server.js`

---

## Alternative: Use Railway CLI

If the web UI isn't working, you can use Railway CLI:

1. Install Railway CLI: `npm i -g @railway/cli`
2. Login: `railway login`
3. Link to project: `railway link`
4. Set variables:
   ```bash
   railway variables set SUPABASE_URL="https://cjeyowmqhluiilrhkvmj.supabase.co"
   railway variables set SUPABASE_SERVICE_ROLE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNqZXlvd21xaGx1aWlscmhrdm1qIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MzcyNzkzOSwiZXhwIjoyMDg5MzAzOTM5fQ.WPgXPTbsJH8zj5IzSDVDPPz0_Q-4iGp30qu68FvVMJM"
   railway variables set FIREBASE_SERVICE_ACCOUNT_JSON='{"type":"service_account",...}'
   ```

---

## Still Getting the Error?

### Check 1: Are Variables Actually Saved?
1. Go to Variables tab
2. Do you see all 3 variables listed?
3. Can you click on them to see/edit their values?

### Check 2: Is Railway Using the Right Service?
1. Check which service is failing to build
2. Make sure that service has the variables set
3. If you have multiple services, each needs its own variables

### Check 3: Check Build Logs
1. Go to **Deployments** tab
2. Click on the failed deployment
3. Look at the **build logs**
4. The error should show exactly which variable is missing

### Check 4: Try Deleting and Re-adding
1. Delete all 3 variables from Railway
2. Wait a moment
3. Add them back one by one
4. Redeploy

---

## Visual Guide: Where to Add Variables

```
Railway Dashboard
└── Your Project
    └── Backend Service  ← CLICK HERE
        ├── Variables Tab  ← ADD VARIABLES HERE
        ├── Settings
        ├── Deployments
        └── Logs
```

**NOT here:**
```
Railway Dashboard
└── Your Project  ← DON'T ADD HERE (Project level)
    └── Settings
        └── Variables  ← This is wrong!
```

---

## After Fixing

Once variables are set and deployment succeeds:
1. Check **Logs** tab - you should see: `Server running at http://localhost:PORT`
2. Test the health endpoint: `https://your-railway-url.up.railway.app/health`
3. Your Flutter app should now be able to call `/api/me` and get roles
