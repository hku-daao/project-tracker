# Railway Deployment Setup Guide

## Step-by-Step: Setting Environment Variables in Railway

### Step 1: Access Railway Dashboard
1. Go to [https://railway.app](https://railway.app)
2. Log in with your account
3. Click on your project (e.g., "Project Tracker")

### Step 2: Open Your Backend Service
1. Click on your **backend service** (the one that's failing to build)
2. Click on the **"Variables"** tab (or **"Settings"** → **"Variables"**)

### Step 3: Add Required Environment Variables

You need to add these **3 environment variables**:

#### 1. SUPABASE_URL
- **Variable Name**: `SUPABASE_URL`
- **Value**: Your Supabase project URL
  - Format: `https://xxxxxxxxxxxxx.supabase.co`
  - Find it in: Supabase Dashboard → Project Settings → API → Project URL

#### 2. SUPABASE_SERVICE_ROLE_KEY
- **Variable Name**: `SUPABASE_SERVICE_ROLE_KEY`
- **Value**: Your Supabase service role key (⚠️ **Keep this secret!**)
  - Format: A long string starting with `eyJ...`
  - Find it in: Supabase Dashboard → Project Settings → API → `service_role` key (under "Project API keys")
  - ⚠️ **Important**: Use the `service_role` key, NOT the `anon` key
  - ⚠️ **Warning**: This key has admin access - never commit it to git!

#### 3. FIREBASE_SERVICE_ACCOUNT_JSON
- **Variable Name**: `FIREBASE_SERVICE_ACCOUNT_JSON`
- **Value**: Your Firebase service account JSON (as a single line)
  - Get it from: Firebase Console → Project Settings → Service Accounts → Generate New Private Key
  - **Important**: The entire JSON must be on ONE line (no line breaks)
  - Example format: `{"type":"service_account","project_id":"...","private_key_id":"...",...}`

### Step 4: How to Add Variables in Railway

1. In the **Variables** tab, click **"+ New Variable"** or **"Add Variable"**
2. Enter the **Variable Name** (e.g., `SUPABASE_URL`)
3. Enter the **Value**
4. Click **"Add"** or **"Save"**
5. Repeat for all 3 variables

### Step 5: Optional - ADMIN_EMAIL (if needed)
- **Variable Name**: `ADMIN_EMAIL`
- **Value**: `test-admin@test.com` (or your admin email)
- This is optional - defaults to `test-admin@test.com` if not set

### Step 6: Redeploy
After adding all variables:
1. Go to the **"Deployments"** tab
2. Click **"Redeploy"** or the service will auto-redeploy
3. Wait for the build to complete
4. Check the **"Logs"** tab to verify it's working

---

## Quick Reference: Where to Find Values

### Supabase URL and Service Role Key:
1. Go to [https://supabase.com/dashboard](https://supabase.com/dashboard)
2. Select your project
3. Click **Settings** (gear icon) → **API**
4. Copy:
   - **Project URL** → Use for `SUPABASE_URL`
   - **service_role** key (under "Project API keys") → Use for `SUPABASE_SERVICE_ROLE_KEY`

### Firebase Service Account JSON:
1. Go to [https://console.firebase.google.com](https://console.firebase.google.com)
2. Select your project
3. Click **Settings** (gear icon) → **Project Settings**
4. Go to **"Service Accounts"** tab
5. Click **"Generate New Private Key"**
6. Download the JSON file
7. Open the JSON file and copy the entire contents
8. **Important**: Remove all line breaks and put it on ONE line
   - You can use an online tool like [jsonformatter.org](https://jsonformatter.org) to minify it
   - Or use PowerShell: `(Get-Content file.json -Raw) -replace '\s+', ' '`

---

## Example: Railway Variables Tab Should Look Like

```
Variable Name                    Value
─────────────────────────────────────────────────────────────
SUPABASE_URL                     https://xxxxx.supabase.co
SUPABASE_SERVICE_ROLE_KEY        eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
FIREBASE_SERVICE_ACCOUNT_JSON    {"type":"service_account","project_id":"..."}
ADMIN_EMAIL                      test-admin@test.com (optional)
```

---

## Troubleshooting

### Error: "secret SUPABASE_SERVICE_ROLE_KEY: not found"
- **Solution**: Make sure you added the variable in Railway's Variables tab
- Check that the variable name is exactly: `SUPABASE_SERVICE_ROLE_KEY` (case-sensitive)

### Error: "Invalid Supabase URL"
- **Solution**: Check that `SUPABASE_URL` starts with `https://` and ends with `.supabase.co`
- Make sure there are no extra spaces or quotes

### Error: "Firebase Admin init failed"
- **Solution**: 
  - Make sure `FIREBASE_SERVICE_ACCOUNT_JSON` is on ONE line (no line breaks)
  - Verify the JSON is valid (use a JSON validator)
  - Make sure you copied the entire JSON, including all fields

### Build Still Failing?
1. Check the **Logs** tab in Railway for specific error messages
2. Verify all 3 required variables are set
3. Make sure variable names match exactly (case-sensitive)
4. Try redeploying after adding variables

---

## Security Notes

⚠️ **Never commit these values to git!**
- The `.env` file should be in `.gitignore`
- Railway variables are encrypted and stored securely
- The `service_role` key has full database access - keep it secret!

---

## After Setup

Once variables are set and the service redeploys successfully:
1. Check the **Logs** tab - you should see: `Server running at http://localhost:PORT`
2. Test the `/health` endpoint: `https://your-railway-url.up.railway.app/health`
3. Test `/api/me` with a Firebase token to verify authentication works
