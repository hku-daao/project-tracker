# How to Check Backend Server Logs

## Option 1: Local Development (Running `npm start` or `node server.js`)

### Step 1: Open a Terminal/Command Prompt
- **Windows**: Press `Win + R`, type `cmd` or `powershell`, press Enter
- **Mac/Linux**: Open Terminal

### Step 2: Navigate to Backend Directory
```bash
cd "C:\Users\calvin\OneDrive - The University Of Hong Kong\Documents\Cursor AI\Project Tracker\backend"
```

### Step 3: Start the Backend Server
```bash
npm start
```
or
```bash
node server.js
```

### Step 4: View Logs
The logs will appear directly in the terminal window. You should see:
- `Server running at http://localhost:3000`
- Any error messages
- Console.log messages like:
  - `handleApiTeams: Found X teams`
  - `handleApiTeams: Found X team members`
  - `handleApiStaff: Returning X staff members`
  - Any error messages from database queries

### Step 5: Test the Endpoints
While the server is running, open your Flutter app in Chrome. The terminal will show:
- HTTP requests coming in (if you add request logging)
- Database query results
- Any errors

---

## Option 2: Railway Deployment

### Step 1: Access Railway Dashboard
1. Go to [https://railway.app](https://railway.app)
2. Log in with your account
3. Click on your project (e.g., "Project Tracker")

### Step 2: View Logs
1. Click on your **service** (the backend service)
2. Click on the **"Deployments"** tab or **"Logs"** tab
3. You'll see real-time logs from your deployed backend

### Step 3: Filter Logs
- Look for messages containing: `handleApiTeams`, `handleApiStaff`, `get_user_profile`
- Check for error messages in red
- Look for database connection errors

---

## Option 3: Check via Browser Network Tab

### Step 1: Open Chrome DevTools
1. In your Flutter app (Chrome), press `F12` or `Ctrl+Shift+I` (Windows) / `Cmd+Option+I` (Mac)
2. Click on the **"Network"** tab

### Step 2: Filter Requests
1. In the filter box, type: `api/teams` or `api/staff`
2. Refresh the page or navigate to "Create Initiative/ Task" screen

### Step 3: Check Response
1. Click on the `/api/teams` request
2. Check the **"Response"** tab to see what the backend returned
3. Check the **"Headers"** tab to see the request/response status
4. If status is not 200, check the error message

### Step 4: Check Request Details
- **Status Code**: Should be `200` for success
- **Response Body**: Should contain `{"teams": [...]}` or `{"staff": [...]}`
- **Request Headers**: Should include `Authorization: Bearer <token>`

---

## Option 4: Test Backend Endpoints Directly

### Step 1: Get Firebase Token
1. In Chrome DevTools (F12), go to **Console** tab
2. Type and run:
```javascript
firebase.auth().currentUser.getIdToken().then(token => console.log('Token:', token));
```
3. Copy the token

### Step 2: Test in Browser or Postman
Open a new tab and test:
```
http://localhost:3000/api/teams
```
Or if deployed:
```
https://your-railway-url.up.railway.app/api/teams
```

**With Authorization Header:**
- Use a tool like **Postman** or **curl**
- Add header: `Authorization: Bearer <your-token>`

### Step 3: Using curl (Command Line)
```bash
curl -H "Authorization: Bearer YOUR_TOKEN_HERE" http://localhost:3000/api/teams
```

---

## What to Look For in Logs

### Success Messages:
- ✅ `handleApiTeams: Found X teams`
- ✅ `handleApiTeams: Found X team members`
- ✅ `handleApiStaff: Returning X staff members`
- ✅ `Server running at http://localhost:3000`

### Error Messages to Watch For:
- ❌ `Supabase not configured` - Missing environment variables
- ❌ `Unauthorized` - Token validation failed
- ❌ `teams query error:` - Database query failed
- ❌ `team_members query error:` - Database query failed
- ❌ `Error: relation "teams" does not exist` - Table doesn't exist
- ❌ `Error: permission denied` - Database permissions issue

---

## Quick Debug Checklist

1. ✅ **Is the backend server running?**
   - Check terminal/console for "Server running at..."
   
2. ✅ **Are environment variables set?**
   - Check `.env` file has `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`
   
3. ✅ **Is Supabase connection working?**
   - Look for "Supabase not configured" errors
   
4. ✅ **Are there teams in the database?**
   - Run in Supabase SQL Editor: `SELECT COUNT(*) FROM teams;`
   
5. ✅ **Is the token valid?**
   - Check Network tab for 401 Unauthorized errors

---

## Example: What Good Logs Look Like

```
Server running at http://localhost:3000
handleApiTeams: Found 3 teams
handleApiTeams: Found 15 team members
handleApiTeams: Returning 3 teams with members
handleApiStaff: Returning 20 staff members
```

## Example: What Error Logs Look Like

```
handleApiTeams: teams query error: { code: 'PGRST116', message: 'The schema "public" does not exist' }
handleApiTeams: Server error: The schema "public" does not exist
```

---

## Need More Help?

If you see errors, copy the full error message and:
1. Check the error code (e.g., PGRST116)
2. Search for the error in Supabase documentation
3. Verify your database migrations have been run
4. Check that your Supabase project is active and accessible
