# Deploy to Existing Railway Project

This guide shows how to deploy your backend to an **existing Railway project**.

---

## Step 1: Connect Your GitHub Repository

1. Go to [railway.app](https://railway.app) and log in
2. Open your **existing project**
3. If you don't have a service yet:
   - Click **"New"** → **"GitHub Repo"**
   - Select your repository: `Project Tracker` (or your repo name)
   - Railway will create a new service

4. If you already have a service:
   - Click on the **service** in your project
   - Go to **"Settings"** tab
   - Scroll to **"Source"** section
   - Click **"Connect Repo"** or **"Change Source"**
   - Select your GitHub repository

---

## Step 2: Configure Service Settings

1. In your service, go to **"Settings"** tab
2. Configure these settings:

   **Root Directory:**
   - Set to: `backend`
   - (This tells Railway where your `package.json` and `server.js` are)

   **Start Command:**
   - Set to: `npm start`
   - (Railway usually auto-detects this, but verify it's correct)

   **Build Command:**
   - Usually: `npm install` (auto-detected)
   - Railway runs this automatically

3. **Save** any changes

---

## Step 3: Add Environment Variables

1. In your service, go to **"Variables"** tab
2. Click **"New Variable"** for each environment variable:

   ### Variable 1: SUPABASE_URL
   - **Name**: `SUPABASE_URL`
   - **Value**: `https://cjeyowmqhluiilrhkvmj.supabase.co`
   - (Or your Supabase project URL)
   - Click **"Add"**

   ### Variable 2: SUPABASE_SERVICE_ROLE_KEY
   - **Name**: `SUPABASE_SERVICE_ROLE_KEY`
   - **Value**: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNqZXlvd21xaGx1aWlscmhrdm1qIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MzcyNzkzOSwiZXhwIjoyMDg5MzAzOTM5fQ.WPgXPTbsJH8zj5IzSDVDPPz0_Q-4iGp30qu68FvVMJM`
   - (Your Supabase service_role key - get from Supabase Dashboard → Project Settings → API)
   - Click **"Add"**

   ### Variable 3: FIREBASE_SERVICE_ACCOUNT_JSON
   - **Name**: `FIREBASE_SERVICE_ACCOUNT_JSON`
   - **Value**: Paste the **entire JSON as one line** (no line breaks)
   - Example: `{"type":"service_account","project_id":"daao-a20c6","private_key_id":"...","private_key":"-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n","client_email":"...","client_id":"...","auth_uri":"...","token_uri":"...","auth_provider_x509_cert_url":"...","client_x509_cert_url":"...","universe_domain":"googleapis.com"}`
   - **Important**: Must be on ONE line with no line breaks
   - Click **"Add"**

   ### Variable 4: ADMIN_EMAIL (Optional)
   - **Name**: `ADMIN_EMAIL`
   - **Value**: `test-admin@test.com`
   - (Or your admin email)
   - Click **"Add"**

3. Railway will **automatically redeploy** when you add/update variables

---

## Step 4: Get Your Backend URL

1. In your service, go to **"Settings"** tab
2. Scroll to **"Domains"** section
3. You'll see a default domain like:
   - `your-service-name.up.railway.app`
   - Or `your-project-name-production.up.railway.app`
4. Click **"Generate Domain"** if you don't see one
5. **Copy the full URL** (e.g., `https://project-tracker-backend.up.railway.app`)

---

## Step 5: Update Flutter App Configuration

1. Open: `lib/config/api_config.dart`
2. Update the `baseUrl`:
   ```dart
   static const String baseUrl = 'https://your-service-name.up.railway.app';
   ```
   (Replace with your actual Railway URL)

3. Save the file

---

## Step 6: Verify Deployment

1. **Check Railway Logs:**
   - Go to your service → **"Deployments"** tab
   - Click on the latest deployment
   - Check the logs for:
     - ✅ `Server running at http://localhost:PORT`
     - ✅ No Firebase Admin errors
     - ✅ No Supabase connection errors

2. **Test Health Endpoint:**
   - Open browser: `https://YOUR-RAILWAY-URL/health`
   - Should see: `{"ok":true,"message":"Project Tracker backend","timestamp":"..."}`

3. **Test from Flutter:**
   - Run your Flutter app
   - Try logging in
   - Check browser DevTools → Network tab
   - Verify `GET /api/me` returns 200 with role data

---

## Step 7: Enable Auto-Deploy (Recommended)

1. In your service → **"Settings"** tab
2. Scroll to **"Source"** section
3. Ensure **"Auto Deploy"** is enabled
4. This will automatically deploy when you push to your connected branch (usually `main`)

---

## Troubleshooting

### Deployment Fails
- Check **"Deployments"** tab → click on failed deployment → view logs
- Common issues:
  - Missing `package.json` (check Root Directory is set to `backend`)
  - Build errors (check logs for npm install errors)
  - Port binding errors (Railway sets PORT automatically)

### Environment Variables Not Working
- After adding variables, Railway auto-redeploys
- Wait for deployment to complete
- Check logs to verify variables are loaded
- Variables are case-sensitive: `SUPABASE_URL` not `supabase_url`

### Firebase Admin Init Fails
- Ensure `FIREBASE_SERVICE_ACCOUNT_JSON` is **one line** with no line breaks
- Verify JSON is valid (use a JSON validator)
- Check logs for specific error messages

### Health Works But `/api/me` Fails
- Check logs for Firebase Admin initialization
- Verify `FIREBASE_SERVICE_ACCOUNT_JSON` is correct
- Test with a valid Firebase ID token from your Flutter app

### Can't Find Root Directory
- In **Settings** → **Root Directory**: Set to `backend`
- Railway will look for `backend/package.json` and `backend/server.js`

---

## Quick Reference: Railway Dashboard Locations

- **Service Settings**: Click service → **"Settings"** tab
- **Environment Variables**: Click service → **"Variables"** tab
- **Deployment Logs**: Click service → **"Deployments"** tab → click deployment
- **Live Logs**: Click service → **"Logs"** tab (real-time)
- **Domain/URL**: Click service → **"Settings"** → **"Domains"** section

---

## Next Steps After Deployment

1. ✅ Backend is deployed and health check works
2. ✅ Update Flutter `api_config.dart` with Railway URL
3. ✅ Rebuild Flutter web app
4. ✅ Test login and verify `/api/me` endpoint
5. ✅ Run Supabase migration `010_team_testing.sql` if not done yet
6. ✅ Test System Admin page (login as `test-admin@test.com`)

---

**Need help?** Check the deployment logs in Railway dashboard for specific error messages.
