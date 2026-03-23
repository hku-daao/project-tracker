# Backend Deployment Guide

This guide covers deploying the Project Tracker backend to **Railway** and **Render**.

---

## Prerequisites

Before deploying, ensure you have:

1. **Supabase credentials**:
   - `SUPABASE_URL` (from Supabase Dashboard → Project Settings → API)
   - `SUPABASE_SERVICE_ROLE_KEY` (same page, **service_role** key, not anon key)

2. **Firebase Admin credentials**:
   - Firebase Console → Project Settings → Service Accounts → Generate new private key
   - Download the JSON file

3. **GitHub account** (for connecting repositories)

---

## Option 1: Deploy to Railway

### Step 1: Create Railway Account

1. Go to [railway.app](https://railway.app)
2. Click **"Login"** → Sign in with **GitHub**
3. Authorize Railway to access your GitHub account

### Step 2: Create New Project

1. In Railway dashboard, click **"New Project"**
2. Select **"Deploy from GitHub repo"**
3. Choose your repository: `Project Tracker` (or the repo name)
4. Railway will detect it's a Node.js project

### Step 3: Configure Service Settings

1. Click on the **service** that was created
2. Go to **"Settings"** tab
3. Set the **Root Directory** to `backend` (if your repo root contains both Flutter app and backend)
4. Set the **Start Command** to: `npm start`
5. Railway should auto-detect Node.js and use `package.json`

### Step 4: Add Environment Variables

1. In the service, go to **"Variables"** tab
2. Click **"New Variable"** for each:

   **Variable 1: SUPABASE_URL**
   - **Name**: `SUPABASE_URL`
   - **Value**: `https://YOUR_PROJECT_REF.supabase.co`
   - (Get from Supabase Dashboard → Project Settings → API → Project URL)

   **Variable 2: SUPABASE_SERVICE_ROLE_KEY**
   - **Name**: `SUPABASE_SERVICE_ROLE_KEY`
   - **Value**: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...` (the long JWT token)
   - (Get from same Supabase page, **service_role** key)

   **Variable 3: FIREBASE_SERVICE_ACCOUNT_JSON**
   - **Name**: `FIREBASE_SERVICE_ACCOUNT_JSON`
   - **Value**: Paste the **entire JSON as one line** (no line breaks)
   - Example format: `{"type":"service_account","project_id":"...","private_key":"...",...}`
   - **Important**: Remove all line breaks from the JSON file you downloaded

   **Variable 4: ADMIN_EMAIL** (Optional)
   - **Name**: `ADMIN_EMAIL`
   - **Value**: `test-admin@test.com` (or your admin email)
   - If not set, defaults to `test-admin@test.com`

   **Variable 5: PORT** (Optional)
   - Railway sets this automatically, but if needed:
   - **Name**: `PORT`
   - **Value**: `3000` (or leave Railway's default)

### Step 5: Deploy

1. Railway will automatically deploy when you:
   - Push to the connected branch (usually `main` or `master`)
   - Or click **"Deploy"** in the dashboard
2. Watch the **"Deployments"** tab for build logs
3. Wait for status to show **"Active"** (green)

### Step 6: Get Your Backend URL

1. In the service, go to **"Settings"** tab
2. Scroll to **"Domains"** section
3. Railway provides a default domain like: `your-service-name.up.railway.app`
4. Copy this URL (e.g., `https://project-tracker-backend.up.railway.app`)
5. **Update your Flutter app**: In `lib/config/api_config.dart`, set:
   ```dart
   static const String baseUrl = 'https://your-service-name.up.railway.app';
   ```

### Step 7: Verify Deployment

1. Open your browser to: `https://YOUR-RAILWAY-URL/health`
2. You should see JSON: `{"ok":true,"message":"Project Tracker backend","timestamp":"..."}`
3. If you see this, the backend is running!

### Step 8: Custom Domain (Optional)

1. In **"Settings"** → **"Domains"**
2. Click **"Generate Domain"** or **"Custom Domain"**
3. Follow Railway's instructions to add your domain

---

## Option 2: Deploy to Render

### Step 1: Create Render Account

1. Go to [render.com](https://render.com)
2. Click **"Get Started for Free"**
3. Sign up with **GitHub** (recommended) or email

### Step 2: Create New Web Service

1. In Render dashboard, click **"New +"** → **"Web Service"**
2. Connect your GitHub repository:
   - Click **"Connect account"** if not connected
   - Select your repository: `Project Tracker`
3. Configure the service:
   - **Name**: `project-tracker-backend` (or any name)
   - **Environment**: `Node`
   - **Region**: Choose closest to your users (e.g., `Singapore` or `Oregon`)
   - **Branch**: `main` (or your default branch)
   - **Root Directory**: `backend` (if backend is in a subfolder)
   - **Build Command**: `npm install` (Render auto-detects this)
   - **Start Command**: `npm start`

### Step 3: Add Environment Variables

1. Scroll down to **"Environment Variables"** section
2. Click **"Add Environment Variable"** for each:

   **Variable 1: SUPABASE_URL**
   - **Key**: `SUPABASE_URL`
   - **Value**: `https://YOUR_PROJECT_REF.supabase.co`

   **Variable 2: SUPABASE_SERVICE_ROLE_KEY**
   - **Key**: `SUPABASE_SERVICE_ROLE_KEY`
   - **Value**: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...`

   **Variable 3: FIREBASE_SERVICE_ACCOUNT_JSON**
   - **Key**: `FIREBASE_SERVICE_ACCOUNT_JSON`
   - **Value**: Paste the **entire JSON as one line**
   - **Tip**: In Render, you can use the **"Secret File"** option if the JSON is too long, but single-line JSON works fine

   **Variable 4: ADMIN_EMAIL** (Optional)
   - **Key**: `ADMIN_EMAIL`
   - **Value**: `test-admin@test.com`

   **Variable 5: PORT** (Optional)
   - Render sets this automatically via `$PORT`, but if your code needs it:
   - **Key**: `PORT`
   - **Value**: `10000` (Render's default, or leave empty)

### Step 4: Deploy

1. Scroll to bottom and click **"Create Web Service"**
2. Render will:
   - Clone your repo
   - Run `npm install` in the `backend` directory
   - Start the service with `npm start`
3. Watch the **"Logs"** tab for build progress
4. Wait for status: **"Live"** (green)

### Step 5: Get Your Backend URL

1. In the service dashboard, you'll see:
   - **URL**: `https://project-tracker-backend.onrender.com` (or similar)
2. Copy this URL
3. **Update your Flutter app**: In `lib/config/api_config.dart`:
   ```dart
   static const String baseUrl = 'https://project-tracker-backend.onrender.com';
   ```

### Step 6: Verify Deployment

1. Open: `https://YOUR-RENDER-URL/health`
2. You should see: `{"ok":true,"message":"Project Tracker backend","timestamp":"..."}`

### Step 7: Auto-Deploy Settings (Optional)

1. In **"Settings"** tab
2. **Auto-Deploy**: Enabled by default (deploys on every push to main branch)
3. **Pull Request Previews**: Enable if you want preview deployments

### Step 8: Custom Domain (Optional)

1. In **"Settings"** → **"Custom Domains"**
2. Click **"Add"**
3. Enter your domain (e.g., `api.yourdomain.com`)
4. Follow DNS instructions to point your domain to Render

---

## Converting Firebase JSON to Single Line

If you have the Firebase service account JSON file with line breaks, convert it to one line:

### On Windows (PowerShell):
```powershell
# Read the JSON file and remove line breaks
$json = Get-Content "path\to\firebase-service-account.json" -Raw
$json = $json -replace "`r`n", "" -replace "`n", "" -replace "`r", ""
$json | Out-File "firebase-single-line.txt" -NoNewline
```

### On Mac/Linux:
```bash
# Remove all line breaks
cat firebase-service-account.json | tr -d '\n' > firebase-single-line.txt
```

### Manual Method:
1. Open the JSON file in a text editor
2. Select all (Ctrl+A / Cmd+A)
3. Copy (Ctrl+C / Cmd+C)
4. Paste into a new file
5. Use Find & Replace:
   - Find: `\n` (newline)
   - Replace: (empty)
   - Replace All
6. Copy the entire single line
7. Paste into the environment variable

---

## Troubleshooting

### Backend returns 503 "Supabase not configured"
- Check that `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are set correctly
- Verify the service role key (not the anon key)

### Firebase Admin init failed
- Ensure `FIREBASE_SERVICE_ACCOUNT_JSON` is on **one line** with no line breaks
- Verify the JSON is valid (use a JSON validator)
- Check that all quotes are properly escaped if needed

### Backend returns 401 "Unauthorized" on `/api/me`
- Verify Firebase Admin is initialized (check logs)
- Ensure `FIREBASE_SERVICE_ACCOUNT_JSON` is correct
- Check that the Firebase project ID matches

### Health check works but `/api/me` fails
- Check the deployment logs for errors
- Verify environment variables are set (some platforms require a redeploy after adding vars)
- Test with a Firebase ID token from your Flutter app

### Port binding errors
- Railway: Uses `PORT` env var automatically
- Render: Uses `$PORT` env var (usually 10000)
- Your code should use `process.env.PORT || 3000`

---

## Updating Environment Variables

### Railway:
1. Go to service → **"Variables"** tab
2. Edit or add variables
3. Railway **automatically redeploys** when you save

### Render:
1. Go to service → **"Environment"** tab
2. Edit or add variables
3. Click **"Save Changes"**
4. Render **automatically redeploys**

---

## Monitoring & Logs

### Railway:
- **"Deployments"** tab: Build and deploy history
- **"Logs"** tab: Real-time application logs
- **"Metrics"** tab: CPU, memory, network usage

### Render:
- **"Logs"** tab: Real-time application logs
- **"Metrics"** tab: CPU, memory, request metrics
- **"Events"** tab: Deploy and service events

---

## Cost Comparison

### Railway:
- **Free tier**: $5 credit/month (usually enough for small projects)
- **Paid**: Pay-as-you-go after free tier
- **Pros**: Fast deploys, great DX, auto HTTPS
- **Cons**: Free tier limited

### Render:
- **Free tier**: Web services sleep after 15 min inactivity (wakes on request)
- **Paid**: $7/month for always-on web service
- **Pros**: Generous free tier, good for testing
- **Cons**: Cold starts on free tier

---

## Recommendation

- **For production**: Use **Railway** (faster, always-on, better for production)
- **For testing/development**: Use **Render** (free tier is great for testing)

Both platforms are excellent choices. Choose based on your needs!
