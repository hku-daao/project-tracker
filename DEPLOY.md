# Deploy to Firebase Hosting

Firebase project: **daao-a20c6** (DAAO). Two Hosting sites — **testing** and **production** — see **`docs/ENVIRONMENTS.md`** for the full matrix (Supabase, Railway, URLs).

> **Important:** Test and production use **different** `DEPLOY_ENV` builds. Build **separately** for each site; the same `build/web` folder cannot serve both stacks at once.

## One-time setup

### 1. Install Firebase CLI

**Option A – Using Node.js:**
```powershell
npm install -g firebase-tools
```

**Option B – Standalone (Windows):**  
https://firebase.google.com/docs/cli#install_the_firebase_cli  

### 2. Log in to Firebase
```powershell
firebase login
```
Use the Google account that can access **daao-a20c6**.

### 3. Hosting targets (if deploy says target is missing)

Use **site ID only** (no `projectId:` prefix) in `.firebaserc` — e.g. `project-tracker-production`, not `daao-a20c6:project-tracker-production` (wrong format causes HTTP 404 on deploy).

```powershell
firebase target:clear hosting production
firebase target:clear hosting testing
firebase target:apply hosting testing project-tracker-test
firebase target:apply hosting production project-tracker-production
```

### 4. Hosting sites must exist (404 on deploy)

If deploy fails with **`Requested entity was not found`** / **404** on `.../sites/.../versions`:

1. Open [Firebase Console](https://console.firebase.google.com/) → project **daao-a20c6** → **Hosting**.
2. **Testing:** ensure a site with ID **`project-tracker-test`** exists (default URL **https://project-tracker-test.web.app/**). If not → **Add another site** → site ID **`project-tracker-test`**.
3. **Production:** ensure **`project-tracker-production`** exists. If not → **Add another site** → **`project-tracker-production`**.
4. Run `firebase deploy` again for that target.

### 5. Custom domains (HKU)

| Environment | Custom domain |
|---------------|----------------|
| Testing | **https://projecttrackertest.hku-ia.ai/** |
| Production | **https://projecttracker.hku-ia.ai/** |

Add each domain under the **matching** site (`project-tracker-test` vs `project-tracker-production`) → **Domains → Add custom domain**, then add the DNS records at **hku-ia.ai**. In **Authentication → Settings → Authorized domains**, add both hostnames so sign-in works.

Deploying **does not change** when you use custom domains; the same `firebase deploy` updates all URLs for that site (default + custom).

---

## Deploy — **Testing** stack

Uses **DAAO Tests** Supabase + **test** Railway (default `DEPLOY_ENV=testing`).

1. Set the **DAAO Tests** anon key in `lib/config/supabase_config.dart` (`_testingAnonKey`) or pass `--dart-define=SUPABASE_ANON_KEY=...` (see `docs/ENVIRONMENTS.md`).

2. Build and deploy:
```powershell
flutter build web --release --no-wasm-dry-run
firebase deploy --only hosting:testing
```

**URLs:** **https://project-tracker-test.web.app/** · https://project-tracker-test.firebaseapp.com/ · custom https://projecttrackertest.hku-ia.ai/ (if configured)

> `--no-wasm-dry-run` avoids Firebase Pigeon `channel-error` / `FirebaseCoreHostApi.initializeCore` on many Flutter web setups.

---

## Deploy — **Production** stack

Uses **DAAO Apps** Supabase + **production** Railway.

```powershell
flutter build web --release --no-wasm-dry-run --dart-define=DEPLOY_ENV=production
firebase deploy --only hosting:production
```

**URLs:** https://projecttracker.hku-ia.ai/ (custom) · https://project-tracker-production.web.app/

---

## Deploy **both** testing and production (full sequence)

Run from the project root. You must **build twice** (different `DEPLOY_ENV`); **do not** reuse one `build/web` for both.

```powershell
# --- Testing (DAAO Tests Supabase + test Railway) ---
flutter build web --release --no-wasm-dry-run
firebase deploy --only hosting:testing

# --- Production (DAAO Apps Supabase + prod Railway) ---
flutter build web --release --no-wasm-dry-run --dart-define=DEPLOY_ENV=production
firebase deploy --only hosting:production
```

After DNS is set up, users open **projecttrackertest.hku-ia.ai** and **projecttracker.hku-ia.ai**; the same deploys also update the default `*.firebaseapp.com` / `*.web.app` URLs.

---

## Optional: deploy only one target

```powershell
firebase deploy --only hosting:testing
firebase deploy --only hosting:production
```

Avoid `firebase deploy --only hosting` unless you intend to push the **same** `build/web` bundle to **both** sites (only OK if both environments should use identical config).

---

## Troubleshooting: **“Site Not Found”** (Firebase)

This message is from **Firebase Hosting** (not the Flutter app). It usually means the **hostname** you opened is not attached to any Hosting site in project **daao-a20c6**, or **DNS** does not match what Firebase expects.

### 1. Test the default Firebase URL first

Open:

**https://project-tracker-test.web.app/**

| Result | What it means |
|--------|----------------|
| **App loads** | Deploy is OK. The problem is **custom domain** (`projecttrackertest.hku-ia.ai`) — see step 2. |
| **“Site Not Found” here too** | Deploy may not have updated this site, site **`project-tracker-test`** missing in Console, or wrong Firebase project — see step 3. |

### 2. Custom domain `projecttrackertest.hku-ia.ai`

1. [Firebase Console](https://console.firebase.google.com/) → **daao-a20c6** → **Hosting**.
2. Open the site **`project-tracker-test`** (testing — **not** the production site).
3. **Domains** tab → **`projecttrackertest.hku-ia.ai`** must appear as **Connected** (not “Needs setup” / “Pending”).
4. If the domain is missing → **Add custom domain** and complete **TXT** + **A/CNAME** at **hku-ia.ai** exactly as Firebase shows.
5. If the domain is on the **wrong** site (e.g. production) → remove it there and add it under **`project-tracker-test`**.

Wait for DNS (and SSL) to finish; can take from minutes to 48 hours.

### 3. Default URL also broken — redeploy to the testing target

From the project root:

```powershell
flutter build web --release --no-wasm-dry-run
firebase deploy --only hosting:testing
```

Confirm **`.firebaserc`** maps `testing` → **`project-tracker-test`** and you use project **daao-a20c6** (`firebase use`).

### 4. Confirm a release exists

**Hosting** → site **`project-tracker-test`** → **Releases** — latest deploy should match your recent deploy time.
