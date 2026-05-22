# Run locally on your desktop (development)

Same workflow as your teammate: run the app in **Chrome** on your PC while developing. Push to GitHub only when you want test/production Railway to update.

## What you need installed

| Tool | Purpose | Check |
|------|---------|--------|
| **Flutter** (stable) | Build & run the app | `flutter --version` |
| **Chrome** | Web target (primary dev) | `flutter doctor` → Chrome ✓ |

You do **not** need Android SDK or Windows desktop build tools for normal web dev.

## One-time setup

From the project root:

```powershell
cd "c:\Users\kenlee\OneDrive - The University Of Hong Kong\Documents\Project Tracker"
flutter pub get
```

Supabase **testing** keys are already in `lib/config/supabase_config.dart`. Firebase options are in `lib/firebase_options.dart`. No extra `.env` is required for the Flutter app.

## Run the app (testing stack — default)

**Recommended** (project lives under **OneDrive**; this script avoids file-lock errors):

```powershell
.\scripts\run_chrome.ps1
```

Or manually:

```powershell
flutter run -d chrome
```

This uses:

- **Supabase:** DAAO Tests (`kxrimbbeyirmcjtszsvm`)
- **Backend API:** test Railway (`project-tracker-test-production.up.railway.app`) — already deployed; you do **not** need to run Node locally unless you are changing `backend/` code.

After the first compile, Chrome opens with the app. Use **hot reload** (`r` in the terminal) or **hot restart** (`R`) while coding.

## Sign in

Log in with a **Firebase** account that exists in the **daao-a20c6** project and has a matching **`staff`** / **`app_users`** row in **DAAO Tests** Supabase. Ask your teammate for a test account if you do not have one.

If login fails on `localhost`, ask an admin to add **`localhost`** under Firebase Console → **Authentication** → **Settings** → **Authorized domains** (often already present).

## When things go wrong

| Problem | Try |
|---------|-----|
| `build\flutter_assets` locked / build fails | `.\scripts\run_chrome.ps1` (closes Chrome, cleans `build` + `.dart_tool`) |
| Yellow “Supabase not configured” | Rare if repo is unchanged; see `lib/config/SUPABASE_SETUP.md` |
| API / role errors | Test Railway must be up; you need a valid Firebase login linked to `staff` |
| Slow first run | First `flutter run` compiles for ~30–60s; later runs are faster |

## Optional: run the Node backend locally

Only needed if you edit `backend/server.js` or API routes.

1. `cd backend`
2. Copy `.env.example` → `.env` and fill **SUPABASE_URL**, **SUPABASE_SERVICE_ROLE_KEY**, **FIREBASE_SERVICE_ACCOUNT_JSON** (get values from teammate or Supabase/Firebase dashboards — **DAAO Tests** for dev).
3. `npm install` then `node server.js` → `http://localhost:3000`
4. Run Flutter pointing at your machine:

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3000
```

## Push to GitHub (when ready)

```powershell
git add .
git commit -m "describe your change"
git push origin main          # test repo → test Railway
git push production main      # prod repo → prod Railway (when stable)
```

See **`docs/GITHUB_SETUP.md`** and **`docs/ENVIRONMENTS.md`** for test vs production.
