require('dotenv').config();
const crypto = require('crypto');
const http = require('http');
const cron = require('node-cron');
const { createDb } = require('./db');
const localFiles = require('./local_files');
const oidcAuth = require('./oidc_auth');
const smtpMail = require('./smtp_mail');

const NOTIFICATION_EMAIL_FROM = (process.env.SMTP_FROM || '').trim();
/** Public web app origin for task links in emails (no trailing slash). Set PUBLIC_WEB_APP_URL in .env */
const PUBLIC_WEB_APP_URL = (process.env.PUBLIC_WEB_APP_URL || '').trim().replace(/\/$/, '');
/** Marketing / landing URL for “Project Tracker” link in comment emails (no trailing slash). */
const PROJECT_TRACKER_LANDING_URL = (
  process.env.PROJECT_TRACKER_LANDING_URL || PUBLIC_WEB_APP_URL
).trim().replace(/\/$/, '');
/** Same base as [PROJECT_TRACKER_LANDING_URL] with trailing slash (overdue email templates). */
const OVERDUE_REMINDER_LANDING_HREF = `${PROJECT_TRACKER_LANDING_URL}/`;

/**
 * Flutter web deep link: hash query survives many email clients better than `?subtask=` alone.
 * Must match `lib/web_deep_link_web.dart` parsing of `location.hash` / fragment.
 */
function subtaskWebAppUrl(subtaskId) {
  const id = String(subtaskId || '').trim();
  const base = String(PUBLIC_WEB_APP_URL || '').trim().replace(/\/$/, '');
  return `${base}/#/?subtask=${encodeURIComponent(id)}`;
}

/** Flutter web deep link for task detail (hash survives many email clients). */
function taskWebAppUrl(taskId) {
  const id = String(taskId || '').trim();
  const base = String(PUBLIC_WEB_APP_URL || '').trim().replace(/\/$/, '');
  return `${base}/#/?task=${encodeURIComponent(id)}`;
}

/** Flutter web deep link for project detail (`/#/?project=` matches [web_deep_link_web.dart]). */
function projectWebAppUrl(projectId) {
  const id = String(projectId || '').trim();
  const base = String(PUBLIC_WEB_APP_URL || '').trim().replace(/\/$/, '');
  return `${base}/#/?project=${encodeURIComponent(id)}`;
}

/** “Project Tracker” footer link in task-updated assignee emails. */
const TASK_UPDATE_NOTIFY_PROJECT_TRACKER_HREF = `${PROJECT_TRACKER_LANDING_URL}/`;

/** Allowed keys from Flutter for task-updated email lines (display label is server-side). */
const TASK_UPDATE_NOTIFY_FIELD_LABELS = {
  taskName: 'Task name',
  description: 'Description',
  project: 'Project',
  assignees: 'Assignees',
  pic: 'PIC',
  priority: 'Priority',
  complexity: 'Complexity',
  status: 'Status',
  commencementStatus: 'Commence',
  startDate: 'Start date',
  dueDate: 'Due date',
  submission: 'Submission',
  files: 'Files',
  urls: 'URLs',
};

const TASK_UPDATE_NOTIFY_MAX_CHANGES = 8;
const TASK_UPDATE_NOTIFY_MAX_VALUE_LEN = 4000;
const TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN = 8000;

const LLM_PROXY_BASE_URL = String(
  process.env.LLM_PROXY_BASE_URL ||
    process.env.OLLAMA_LLM_BASE_URL ||
    '',
).trim().replace(/\/+$/, '');
const LLM_PROXY_TIMEOUT_MS = Number(process.env.LLM_PROXY_TIMEOUT_MS || 120000);

/** Allowed keys from Flutter for sub-task-updated email lines (display label is server-side). */
const SUBTASK_UPDATE_NOTIFY_FIELD_LABELS = {
  subtaskName: 'Sub-task name',
  description: 'Description',
  project: 'Project',
  assignees: 'Assignees',
  pic: 'PIC',
  priority: 'Priority',
  complexity: 'Complexity',
  status: 'Status',
  commencementStatus: 'Commence',
  startDate: 'Start date',
  dueDate: 'Due date',
  submission: 'Submission',
  files: 'Files',
  urls: 'URLs',
};

/** Allowed keys from Flutter for project-updated email lines (display label is server-side). */
const PROJECT_UPDATE_NOTIFY_FIELD_LABELS = {
  projectName: 'Project name',
  description: 'Description',
  assignees: 'Assignee(s)',
  pic: 'PIC(s)',
  status: 'Status',
  startDate: 'Start date',
  endDate: 'End date',
};

/**
 * Task-updated assignee email: Aptos 16px; first block = field lines and/or comment line
 * per product template (double break between field block and comment when both present).
 *
 * @param {{ recipientDisplayName: string, introHtml?: string, introText?: string, detailLinesHtml?: string, detailLinesText?: string, changeLinesHtml: string, changeLinesText: string, commentLineHtml: string, commentLineText: string, taskName: string, taskUrl: string, updaterName: string, updatedAtLine: string }} p
 */
function buildTaskUpdatedAssigneeEmailHtml(p) {
  const safeHi = escapeHtml(p.recipientDisplayName || 'Assignees');
  const intro = (p.introHtml || '').trim() ||
    'This email is to inform you that task information has been updated.';
  const details = (p.detailLinesHtml || '').trim() ||
    `<a href="${escapeHtml(p.taskUrl)}" style="font-weight:bold;color:#1565C0;">${escapeHtml(p.taskName)}</a>`;
  const bodyFont =
    "font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;line-height:1.5;color:#000000;";
  return `<div style="margin:0;${bodyFont}">Dear ${safeHi},<br><br>
${intro}<br><br>
${details}<br><br>
Please review the updated task information in Project Tracker. ${eventInlineLinkHtml('Task link', p.taskUrl)}<br><br>
${projectTrackerEmailFooterHtml()}</div>`;
}

function buildTaskUpdatedAssigneeEmailText(p) {
  const intro = (p.introText || '').trim() ||
    'This email is to inform you that task information has been updated.';
  const details = (p.detailLinesText || '').trim() || `${p.taskName}\n${p.taskUrl}`;
  return `Dear ${p.recipientDisplayName || 'Assignees'},

${intro}

${details}

Please review the updated task information in Project Tracker. ${eventInlineLinkText('Task link', p.taskUrl)}

${projectTrackerEmailFooterText()}`;
}

/**
 * Sub-task-updated notify email (creator save only): Aptos 16px; `changeLines*` = `{A} is updated – {value}`;
 * optional `commentLine*` = `Sub-task comment is added – …`; title link; Updated by / at; Project Tracker.
 *
 * @param {{ recipientDisplayName: string, introHtml?: string, introText?: string, detailLinesHtml?: string, detailLinesText?: string, changeLinesHtml: string, changeLinesText: string, commentLineHtml: string, commentLineText: string, subtaskName: string, subtaskUrl: string, updaterName: string, updatedAtLine: string }} p
 */
function buildSubtaskUpdatedAssigneeEmailHtml(p) {
  const safeHi = escapeHtml(p.recipientDisplayName || 'Assignees');
  const intro = (p.introHtml || '').trim() ||
    'This email is to inform you that subtask information has been updated.';
  const details = (p.detailLinesHtml || '').trim() ||
    `<a href="${escapeHtml(p.subtaskUrl)}" style="font-weight:bold;color:#1565C0;">${escapeHtml(p.subtaskName)}</a>`;
  const bodyFont =
    "font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;line-height:1.5;color:#000000;";
  return `<div style="margin:0;${bodyFont}">Dear ${safeHi},<br><br>
${intro}<br><br>
${details}<br><br>
Please review the updated subtask information in Project Tracker. ${eventInlineLinkHtml('Subtask link', p.subtaskUrl)}<br><br>
${projectTrackerEmailFooterHtml()}</div>`;
}

function buildSubtaskUpdatedAssigneeEmailText(p) {
  const intro = (p.introText || '').trim() ||
    'This email is to inform you that subtask information has been updated.';
  const details = (p.detailLinesText || '').trim() || `${p.subtaskName}\n${p.subtaskUrl}`;
  return `Dear ${p.recipientDisplayName || 'Assignees'},

${intro}

${details}

Please review the updated subtask information in Project Tracker. ${eventInlineLinkText('Subtask link', p.subtaskUrl)}

${projectTrackerEmailFooterText()}`;
}

/** Task-comment emails (`handleNotifyTaskComment`). Default on; set `TASK_COMMENT_EMAIL_ENABLED=false` to disable. */
const TASK_COMMENT_EMAIL_ENABLED = (() => {
  const v = (process.env.TASK_COMMENT_EMAIL_ENABLED || 'true').trim().toLowerCase();
  return !['false', '0', 'no', 'off'].includes(v);
})();

/** POST /api/cron/* — optional shared secret (Railway / external scheduler). */
const CRON_SECRET = (process.env.CRON_SECRET || '').trim();

/** Master switch for outbound notification/cron email. Default off during HKU migration review. */
const EMAIL_SENDING_ENABLED = (() => {
  const v = (process.env.EMAIL_SENDING_ENABLED || 'false').trim().toLowerCase();
  return v === 'true' || v === '1' || v === 'yes';
})();

/** `/api/notify/*` — email off by default during on-prem migration (HKU SMTP later). */
function notifyEmailSkippedResponse(req, res) {
  sendJson(req, res, 200, { ok: true, skipped: true, reason: 'email_disabled' });
}

function cronEmailBlockedReason() {
  if (!EMAIL_SENDING_ENABLED) return null;
  if (!outboundEmailConfigured()) {
    return 'Outbound email transport not configured';
  }
  return null;
}

function outboundEmailConfigured() {
  return smtpMail.isSmtpConfigured();
}

// Container listen port (compose sets PORT=3000). Host publish uses HOST_BACKEND_PORT in .env.
const PORT = Number(process.env.PORT || 3000);
const DATABASE_URL = (process.env.DATABASE_URL || '').trim();

// Trim — copy/paste in Railway sometimes adds trailing newlines.
const FIREBASE_SERVICE_ACCOUNT_JSON = process.env.FIREBASE_SERVICE_ACCOUNT_JSON || '';
const ADMIN_EMAIL = (process.env.ADMIN_EMAIL || 'test-admin@test.com').toLowerCase();

/// Origins allowed to call this API from the browser (Flutter web).
/// Prefer CORS_ORIGINS / PUBLIC_WEB_APP_URL in .env — no hardcoded host ports here.
function localDevCorsOrigins() {
  const port = String(process.env.HOST_BACKEND_PORT || process.env.PORT || '').trim();
  if (!port) return [];
  return [`http://localhost:${port}`, `http://127.0.0.1:${port}`];
}

function allowedOriginsSet() {
  const fromEnv = (process.env.CORS_ORIGINS || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  const site = PUBLIC_WEB_APP_URL ? [PUBLIC_WEB_APP_URL] : [];
  const localApi = (process.env.LOCAL_API_BASE_URL || '').trim().replace(/\/+$/, '');
  const localExtra = localApi ? [localApi] : [];
  return new Set([...localDevCorsOrigins(), ...localExtra, ...fromEnv, ...site]);
}

/** Per-request CORS: echo preflight headers + allowlist Origin (required for browser + Authorization). */
function buildCorsHeaders(req) {
  const origin = req.headers.origin;
  const allow = allowedOriginsSet();
  const h = {
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Max-Age': '86400',
  };
  if (origin && allow.has(origin)) {
    h['Access-Control-Allow-Origin'] = origin;
    h['Access-Control-Allow-Credentials'] = 'true';
    h.Vary = 'Origin';
  } else {
    h['Access-Control-Allow-Origin'] = '*';
  }
  const reqHdr = req.headers['access-control-request-headers'];
  h['Access-Control-Allow-Headers'] =
    reqHdr || 'Authorization, Content-Type, Accept, X-Requested-With';
  return h;
}

function applyCors(req, res, statusCode, extraHeaders = {}) {
  res.writeHead(statusCode, { ...buildCorsHeaders(req), ...extraHeaders });
}

function sendJson(req, res, statusCode, data) {
  applyCors(req, res, statusCode, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(data));
}

let firebaseAdmin = null;
if (FIREBASE_SERVICE_ACCOUNT_JSON) {
  try {
    firebaseAdmin = require('firebase-admin');
    const serviceAccount = JSON.parse(FIREBASE_SERVICE_ACCOUNT_JSON);
    firebaseAdmin.initializeApp({ credential: firebaseAdmin.credential.cert(serviceAccount) });
  } catch (e) {
    console.warn('Firebase Admin init failed:', e.message);
  }
}

let pgPool = null;
if (DATABASE_URL) {
  try {
    const { Pool } = require('pg');
    pgPool = new Pool({ connectionString: DATABASE_URL });
  } catch (e) {
    console.warn('Postgres pool init failed:', e.message);
  }
}

const db = pgPool ? createDb(pgPool) : null;
localFiles.ensureUploadDir();

async function checkDatabaseHealth() {
  if (!pgPool) {
    return { configured: DATABASE_URL.length > 0, ok: false };
  }
  try {
    const result = await pgPool.query('SELECT 1 AS ok');
    return { configured: true, ok: result.rows[0]?.ok === 1 };
  } catch (e) {
    return { configured: true, ok: false, error: e.message };
  }
}

async function resolveStaffKeyForFirebaseSession(uid, email) {
  if (!db) return null;
  const firebaseUid = String(uid || '').trim();
  const emailNorm = String(email || '').trim().toLowerCase();
  if (!firebaseUid && !emailNorm) return null;
  const resolveByStaffEmail = async () => {
    if (!emailNorm) return null;
    const { data, error } = await db
      .from('staff')
      .select('app_id')
      .ilike('email', emailNorm)
      .limit(1)
      .maybeSingle();
    if (error || !data) return null;
    const appId = data.app_id;
    return typeof appId === 'string' && appId.trim() ? appId.trim() : null;
  };
  try {
    let query = db
      .from('app_users')
      .select('staff ( app_id )')
      .limit(1);
    if (firebaseUid) {
      query = query.eq('firebase_uid', firebaseUid);
    } else {
      query = query.eq('email', emailNorm);
    }
    let { data, error } = await query.maybeSingle();
    if ((!data || error) && emailNorm && firebaseUid) {
      const fallback = await db
        .from('app_users')
        .select('staff ( app_id )')
        .eq('email', emailNorm)
        .limit(1)
        .maybeSingle();
      data = fallback.data;
      error = fallback.error;
    }
    if (error || !data) return await resolveByStaffEmail();
    const staff = Array.isArray(data.staff) ? data.staff[0] : data.staff;
    const appId = staff?.app_id;
    return typeof appId === 'string' && appId.trim()
      ? appId.trim()
      : await resolveByStaffEmail();
  } catch (e) {
    return await resolveByStaffEmail();
  }
}

async function verifyFirebaseToken(reqOrAuthHeader) {
  const req =
    reqOrAuthHeader && typeof reqOrAuthHeader === 'object' && reqOrAuthHeader.headers
      ? reqOrAuthHeader
      : null;
  const authHeader = req ? req.headers.authorization : reqOrAuthHeader;

  if (oidcAuth.isConfigured()) {
    const oidcSession = oidcAuth.sessionFromRequest(
      req || { headers: { authorization: authHeader || '', cookie: '' } },
    );
    if (oidcSession) {
      const auth = oidcAuth.toAuthSession(oidcSession);
      const resolvedStaffKey = await resolveStaffKeyForFirebaseSession(auth.uid, auth.email);
      const staffKeys = resolvedStaffKey ? [resolvedStaffKey] : [];
      return {
        uid: auth.uid,
        email: auth.email,
        staffKey: staffKeys[0] || null,
        staffKeys,
      };
    }
  }

  if (!firebaseAdmin || !authHeader || !authHeader.startsWith('Bearer ')) return null;
  const idToken = authHeader.slice(7);
  try {
    const decoded = await firebaseAdmin.auth().verifyIdToken(idToken);
    const sk = decoded.staffKey;
    const tokenStaffKey =
      typeof sk === 'string' && sk.trim() ? sk.trim() : null;
    const email = (decoded.email || '').toLowerCase();
    const resolvedStaffKey = await resolveStaffKeyForFirebaseSession(
      decoded.uid,
      email,
    );
    const staffKeys = [...new Set([tokenStaffKey, resolvedStaffKey].filter(Boolean))];
    return {
      uid: decoded.uid,
      email,
      staffKey: staffKeys[0] || null,
      staffKeys,
    };
  } catch (_) {
    return null;
  }
}

async function fetchProfileByEmail(email) {
  if (!db || !email) return null;
  const { data: rows, error } = await db
    .from('app_users')
    .select(`
      id,
      firebase_uid,
      email,
      staff_id,
      staff ( app_id, name ),
      user_role_mapping ( roles ( app_id ) )
    `)
    .eq('email', email.toLowerCase())
    .limit(1);
  if (error || !rows || !rows[0]) return null;
  const u = rows[0];
  const urm = u.user_role_mapping;
  let roleAppId = null;
  if (Array.isArray(urm) && urm.length) {
    roleAppId = urm[0].roles?.app_id || null;
  } else if (urm && urm.roles) {
    roleAppId = urm.roles.app_id;
  }
  const staff = u.staff;
  const staffObj = Array.isArray(staff) ? staff[0] : staff;
  return {
    role_app_id: roleAppId,
    staff_id: u.staff_id,
    staff_app_id: staffObj?.app_id || null,
    staff_name: staffObj?.name || null,
    firebase_uid_for_rpc: u.firebase_uid,
  };
}

/**
 * `task.create_by` may be `staff.id` (uuid) or `staff.app_id` (matches Flutter insert resolution).
 */
async function fetchStaffRowForCreateBy(dbClient, createByRaw) {
  const key = String(createByRaw || '').trim();
  if (!key) return { data: null, error: null };
  const byId = await dbClient
    .from('staff')
    .select('id, email, name, active')
    .eq('id', key)
    .maybeSingle();
  if (byId.error) return { data: null, error: byId.error };
  if (byId.data) return { data: byId.data, error: null };
  const byApp = await dbClient
    .from('staff')
    .select('id, email, name, active')
    .eq('app_id', key)
    .maybeSingle();
  if (byApp.error) return { data: null, error: byApp.error };
  return { data: byApp.data || null, error: null };
}

/**
 * Prefer `staff.email`; if empty, use any `app_users.email` linked to `staff.id` (Firebase users often only have the latter).
 */
async function resolveStaffEmailForNotifications(dbClient, staffRow) {
  const direct = String(staffRow?.email || '').trim();
  if (direct) return direct;
  const sid = String(staffRow?.id || '').trim();
  if (!sid) return '';
  const { data: rows, error } = await dbClient
    .from('app_users')
    .select('email')
    .eq('staff_id', sid)
    .limit(5);
  if (error) return '';
  for (const r of rows || []) {
    const e = String(r?.email || '').trim();
    if (e) return e;
  }
  return '';
}

/**
 * True when [sessionEmailNorm] matches `staff.email` or any `app_users.email` for `staff.id`
 * (Firebase sign-in email often lives on `app_users`, not `staff.email`).
 */
async function sessionEmailBelongsToStaffRow(dbClient, staffRow, sessionEmailNorm) {
  const want = (sessionEmailNorm || '').trim().toLowerCase();
  if (!want) return false;
  const direct = String(staffRow?.email || '').trim().toLowerCase();
  if (direct && direct === want) return true;
  const sid = String(staffRow?.id || '').trim();
  if (!sid) return false;
  const { data: rows, error } = await dbClient
    .from('app_users')
    .select('email')
    .eq('staff_id', sid)
    .limit(20);
  if (error) return false;
  for (const r of rows || []) {
    const e = String(r?.email || '').trim().toLowerCase();
    if (e && e === want) return true;
  }
  return false;
}

async function handleApiMe(req, res) {
  const session = await verifyFirebaseToken(req);
  if (!session) {
    sendJson(req, res, 401, {
      error: 'Unauthorized',
      message: 'Invalid or missing auth session',
    });
    return;
  }
  if (!db) {
    sendJson(req, res, 503, { error: 'Database not configured' });
    return;
  }
  try {
    const { uid, email } = session;
    const profileRes = await db.rpc('get_user_profile', { p_firebase_uid: uid });
    let profileRow = profileRes.data && profileRes.data[0];
    let uidForAssignable = uid;

    if (!profileRow && email) {
      const byEmail = await fetchProfileByEmail(email);
      if (byEmail) {
        profileRow = {
          role_app_id: byEmail.role_app_id,
          staff_id: byEmail.staff_id,
          staff_app_id: byEmail.staff_app_id,
          staff_name: byEmail.staff_name,
        };
        uidForAssignable = byEmail.firebase_uid_for_rpc || uid;
      }
    }

    const assignableRes = await db.rpc('get_assignable_staff', {
      p_firebase_uid: uidForAssignable,
    });
    let assignableStaff = assignableRes.data || [];
    if ((!assignableStaff || assignableStaff.length === 0) && uidForAssignable !== uid) {
      const retry = await db.rpc('get_assignable_staff', { p_firebase_uid: uid });
      assignableStaff = retry.data || [];
    }

    if (!profileRow) {
      sendJson(req, res, 200, { role: null, staffId: null, staffAppId: null, assignableStaff: [] });
      return;
    }
    sendJson(req, res, 200, {
      role: profileRow.role_app_id,
      staffId: profileRow.staff_id,
      staffAppId: profileRow.staff_app_id || null,
      staffName: profileRow.staff_name || null,
      assignableStaff: assignableStaff.map((r) => ({
        staffId: r.staff_id,
        staffAppId: r.staff_app_id,
        staffName: r.staff_name,
        teamId: r.team_id,
        teamAppId: r.team_app_id,
        teamName: r.team_name,
      })),
    });
  } catch (e) {
    console.error('get_user_profile / get_assignable_staff:', e);
    sendJson(req, res, 500, { error: 'Server error', message: e.message });
  }
}

async function handleApiAssignableStaff(req, res) {
  const session = await verifyFirebaseToken(req);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!db) {
    sendJson(req, res, 503, { error: 'Database not configured' });
    return;
  }
  try {
    const byEmail = await fetchProfileByEmail(session.email);
    const uidForAssignable = byEmail?.firebase_uid_for_rpc || session.uid;
    const { data, error } = await db.rpc('get_assignable_staff', {
      p_firebase_uid: uidForAssignable,
    });
    if (error) throw error;
    sendJson(req, res, 200, { assignableStaff: data || [] });
  } catch (e) {
    console.error('get_assignable_staff:', e);
    sendJson(req, res, 500, { error: 'Server error', message: e.message });
  }
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (chunk) => { data += chunk; });
    req.on('end', () => {
      try {
        resolve(data ? JSON.parse(data) : {});
      } catch (e) {
        reject(e);
      }
    });
    req.on('error', reject);
  });
}

async function requireAdmin(req, res) {
  const session = await verifyFirebaseToken(req);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return null;
  }
  if ((session.email || '').toLowerCase() !== ADMIN_EMAIL) {
    sendJson(req, res, 403, { error: 'Forbidden', message: 'Admin only' });
    return null;
  }
  if (!db) {
    sendJson(req, res, 503, { error: 'Database not configured' });
    return null;
  }
  return session;
}

async function handleAdminSnapshot(req, res) {
  const session = await requireAdmin(req, res);
  if (!session) return;
  try {
    const [teams, roles, staff, appUsers, urm, tm, sub] = await Promise.all([
      db.from('teams').select('*').order('name'),
      db.from('roles').select('*').order('app_id'),
      db.from('staff').select('*').order('name'),
      db.from('app_users').select('*').order('email'),
      db.from('user_role_mapping').select('app_user_id, role_id'),
      db.from('team_members').select('team_id, staff_id, role'),
      db.from('subordinate_mapping').select('supervisor_staff_id, subordinate_staff_id'),
    ]);
    sendJson(req, res, 200, {
      teams: teams.data || [],
      roles: roles.data || [],
      staff: staff.data || [],
      appUsers: appUsers.data || [],
      userRoleMapping: urm.data || [],
      teamMembers: tm.data || [],
      subordinateMapping: sub.data || [],
    });
  } catch (e) {
    sendJson(req, res, 500, { error: e.message });
  }
}

async function handleAdminUpsertUser(req, res) {
  const session = await requireAdmin(req, res);
  if (!session) return;
  try {
    const body = await readBody(req);
    const { firebase_uid, email, display_name, staff_app_id, role_app_id } = body;
    if (!firebase_uid || !email || !role_app_id) {
      sendJson(req, res, 400, { error: 'firebase_uid, email, role_app_id required' });
      return;
    }
    let staffId = null;
    if (staff_app_id) {
      const { data: s } = await db.from('staff').select('id').eq('app_id', staff_app_id).maybeSingle();
      staffId = s?.id || null;
    }
    const { data: roleRow } = await db.from('roles').select('id').eq('app_id', role_app_id).maybeSingle();
    if (!roleRow) {
      sendJson(req, res, 400, { error: 'Invalid role_app_id' });
      return;
    }
    const { data: userRow, error: uErr } = await db
      .from('app_users')
      .upsert(
        { firebase_uid, email, display_name: display_name || email, staff_id: staffId },
        { onConflict: 'firebase_uid' },
      )
      .select('id')
      .single();
    if (uErr) throw uErr;
    await db.from('user_role_mapping').delete().eq('app_user_id', userRow.id);
    await db.from('user_role_mapping').insert({ app_user_id: userRow.id, role_id: roleRow.id });
    sendJson(req, res, 200, { ok: true, appUserId: userRow.id });
  } catch (e) {
    sendJson(req, res, 500, { error: e.message });
  }
}

async function handleAdminDeleteUser(req, res) {
  const session = await requireAdmin(req, res);
  if (!session) return;
  const url = new URL(req.url || '/', `http://${req.headers.host}`);
  const id = url.pathname.split('/').pop();
  if (!id) {
    sendJson(req, res, 400, { error: 'Missing id' });
    return;
  }
  try {
    await db.from('user_role_mapping').delete().eq('app_user_id', id);
    await db.from('app_users').delete().eq('id', id);
    sendJson(req, res, 200, { ok: true });
  } catch (e) {
    sendJson(req, res, 500, { error: e.message });
  }
}

async function handleAdminUpsertTeam(req, res) {
  const session = await requireAdmin(req, res);
  if (!session) return;
  try {
    const body = await readBody(req);
    const { name, app_id } = body;
    if (!name || !app_id) {
      sendJson(req, res, 400, { error: 'name, app_id required' });
      return;
    }
    const { error } = await db.from('teams').upsert(
      { name, app_id },
      { onConflict: 'app_id' },
    );
    if (error) throw error;
    sendJson(req, res, 200, { ok: true });
  } catch (e) {
    sendJson(req, res, 500, { error: e.message });
  }
}

async function handleAdminTeamMember(req, res) {
  const session = await requireAdmin(req, res);
  if (!session) return;
  try {
    const body = await readBody(req);
    const { team_app_id, staff_app_id, role } = body;
    if (!team_app_id || !staff_app_id || !role) {
      sendJson(req, res, 400, { error: 'team_app_id, staff_app_id, role required' });
      return;
    }
    const { data: t } = await db.from('teams').select('id').eq('app_id', team_app_id).maybeSingle();
    const { data: s } = await db.from('staff').select('id').eq('app_id', staff_app_id).maybeSingle();
    if (!t || !s) {
      sendJson(req, res, 400, { error: 'Team or staff not found' });
      return;
    }
    const { error } = await db.from('team_members').upsert(
      { team_id: t.id, staff_id: s.id, role },
      { onConflict: 'team_id,staff_id' },
    );
    if (error) throw error;
    sendJson(req, res, 200, { ok: true });
  } catch (e) {
    sendJson(req, res, 500, { error: e.message });
  }
}

async function handleAdminSubordinate(req, res) {
  const session = await requireAdmin(req, res);
  if (!session) return;
  try {
    const body = await readBody(req);
    const { supervisor_staff_app_id, subordinate_staff_app_id } = body;
    if (!supervisor_staff_app_id || !subordinate_staff_app_id) {
      sendJson(req, res, 400, { error: 'supervisor_staff_app_id, subordinate_staff_app_id required' });
      return;
    }
    const { data: sup } = await db.from('staff').select('id').eq('app_id', supervisor_staff_app_id).maybeSingle();
    const { data: sub } = await db.from('staff').select('id').eq('app_id', subordinate_staff_app_id).maybeSingle();
    if (!sup || !sub) {
      sendJson(req, res, 400, { error: 'Staff not found' });
      return;
    }
    const { error } = await db.from('subordinate_mapping').upsert(
      { supervisor_staff_id: sup.id, subordinate_staff_id: sub.id },
      { onConflict: 'supervisor_staff_id,subordinate_staff_id' },
    );
    if (error) throw error;
    sendJson(req, res, 200, { ok: true });
  } catch (e) {
    sendJson(req, res, 500, { error: e.message });
  }
}

async function handleApiTeams(req, res) {
  const session = await verifyFirebaseToken(req);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!db) {
    sendJson(req, res, 503, { error: 'Database not configured' });
    return;
  }
  try {
    const { data: teamsData, error: teamsError } = await db
      .from('teams')
      .select('id, app_id, name')
      .order('name');
    if (teamsError) {
      console.error('handleApiTeams: teams query error:', teamsError);
      throw teamsError;
    }
    console.log(`handleApiTeams: Found ${(teamsData || []).length} teams`);

    const { data: teamMembersData, error: tmError } = await db
      .from('team_members')
      .select('team_id, staff_id, role, staff ( app_id, name )')
      .order('role');
    if (tmError) {
      console.error('handleApiTeams: team_members query error:', tmError);
      throw tmError;
    }
    console.log(`handleApiTeams: Found ${(teamMembersData || []).length} team members`);

    const isDirectorRole = (r) =>
      r === 'director' || r === 'lead';
    const isOfficerRole = (r) =>
      r === 'officer' || r === 'member';

    const teams = (teamsData || []).map((team) => {
      const members = (teamMembersData || []).filter((tm) => tm.team_id === team.id);
      const directors = members
        .filter((tm) => isDirectorRole(tm.role))
        .map((tm) => {
          const staff = Array.isArray(tm.staff) ? tm.staff[0] : tm.staff;
          return staff?.app_id || null;
        })
        .filter((id) => id != null);
      const officers = members
        .filter((tm) => isOfficerRole(tm.role))
        .map((tm) => {
          const staff = Array.isArray(tm.staff) ? tm.staff[0] : tm.staff;
          return staff?.app_id || null;
        })
        .filter((id) => id != null);
      return {
        id: team.app_id,
        name: team.name,
        directorIds: directors,
        officerIds: officers,
      };
    });

    console.log(`handleApiTeams: Returning ${teams.length} teams with members`);
    sendJson(req, res, 200, { teams });
  } catch (e) {
    console.error('handleApiTeams:', e);
    sendJson(req, res, 500, { error: 'Server error', message: e.message });
  }
}

async function handleApiStaff(req, res) {
  const session = await verifyFirebaseToken(req);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!db) {
    sendJson(req, res, 503, { error: 'Database not configured' });
    return;
  }
  try {
    const { data, error } = await db
      .from('staff')
      .select('app_id, name')
      .order('name');
    if (error) {
      console.error('handleApiStaff: query error:', error);
      throw error;
    }
    const staff = (data || []).map((s) => ({
      id: s.app_id,
      name: s.name,
    }));
    console.log(`handleApiStaff: Returning ${staff.length} staff members`);
    sendJson(req, res, 200, { staff });
  } catch (e) {
    console.error('handleApiStaff:', e);
    sendJson(req, res, 500, { error: 'Server error', message: e.message });
  }
}

async function handleLlmChatCompletionsProxy(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  if (!LLM_PROXY_BASE_URL) {
    sendJson(req, res, 503, {
      error: 'LLM proxy is not configured',
      message: 'Set LLM_PROXY_BASE_URL in backend environment.',
    });
    return;
  }
  try {
    const body = await readBody(req);
    const upstreamBody = {
      stream: false,
      think: false,
      ...(body || {}),
    };
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), LLM_PROXY_TIMEOUT_MS);
    let upstream;
    try {
      upstream = await fetch(`${LLM_PROXY_BASE_URL}/chat/completions`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(upstreamBody),
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timeout);
    }
    const text = await upstream.text();
    applyCors(req, res, upstream.status, {
      'Content-Type':
        upstream.headers.get('content-type') || 'application/json',
    });
    res.end(text);
  } catch (e) {
    const aborted = e && e.name === 'AbortError';
    sendJson(req, res, aborted ? 504 : 500, {
      error: aborted ? 'LLM proxy timed out' : 'LLM proxy failed',
      message: e.message || String(e),
    });
  }
}

async function handleHealth(req, res) {
  const database = await checkDatabaseHealth();
  sendJson(req, res, 200, {
    ok: true,
    message: 'Project Tracker backend',
    timestamp: new Date().toISOString(),
    database,
    // Safe diagnostics (no secrets). If databaseConfigured is false, check Railway Variables on THIS service.
    firebaseConfigured: !!firebaseAdmin,
    databaseConfigured: !!db,
    emailSendingEnabled: EMAIL_SENDING_ENABLED,
    outboundEmailReady:
      EMAIL_SENDING_ENABLED && smtpMail.isSmtpConfigured(),
    smtpConfigured: smtpMail.isSmtpConfigured(),
    ssoConfigured: oidcAuth.isConfigured(),
    ssoIssuer: (process.env.SSO_ISSUER_URL || '').trim() || null,
    smtp: smtpMail.smtpConfigSummary(),
    dailyReminderCronEnabled: process.env.DAILY_REMINDER_CRON_ENABLED === 'true',
    cronSecretConfigured: CRON_SECRET.length > 0,
    env: {
      databaseUrlSet: DATABASE_URL.length > 0,
      databasePoolReady: !!pgPool,
    },
  });
}

/**
 * Single recipient for Email: trim, lowercase, first address if comma/semicolon-separated.
 */
function normalizeRecipientEmail(raw) {
  let s = String(raw ?? '').trim();
  if (!s) return '';
  if (/[,;]/.test(s)) {
    s = s.split(/[,;]/)[0].trim();
  }
  const firstToken = (s.split(/\s+/)[0] || '').trim();
  return firstToken.toLowerCase();
}

function formatEmailFailure(r) {
  const base = r.error || 'failed';
  const d = r.detail ? ` — ${String(r.detail).slice(0, 450)}` : '';
  return `${base}${d}`;
}

async function sendNotificationEmail({ to, subject, text, html, from: fromOverride, replyTo, cc }) {
  if (!EMAIL_SENDING_ENABLED) {
    console.log(
      `[email] skipped (EMAIL_SENDING_ENABLED=false): to=${normalizeRecipientEmail(to)} subject=${String(subject || '').slice(0, 80)}`,
    );
    return { ok: true, id: null, skipped: true, resolvedTo: normalizeRecipientEmail(to) };
  }
  if (!outboundEmailConfigured()) {
    return { ok: false, error: 'Outbound email transport not configured' };
  }
  const result = await smtpMail.sendSmtpMail({
    to,
    cc,
    subject,
    text,
    html,
    from: fromOverride || NOTIFICATION_EMAIL_FROM || undefined,
    replyTo,
  });
  return {
    ok: result.ok,
    id: result.messageId || '',
    error: result.error,
    detail: result.detail,
    resolvedTo: result.resolvedTo || normalizeRecipientEmail(to),
    transport: 'smtp',
  };
}

/** OFFLINE_DEV only: POST `{ "to": "you@hku.hk" }` — test HKU SMTP relay (mail7). */
async function handleTestSmtp(req, res) {
  if (!OFFLINE_DEV) {
    sendJson(req, res, 403, { error: 'Only available when OFFLINE_DEV=true on backend' });
    return;
  }
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  if (!smtpMail.isSmtpConfigured()) {
    sendJson(req, res, 503, {
      error: 'SMTP not configured',
      hint: 'Set SMTP_HOST=mail7.hku.hk SMTP_PORT=25 SMTP_FROM=daaoit.ops@hku.hk in .env',
    });
    return;
  }
  try {
    const body = await readBody(req);
    const to = (body.to || DEV_USER_EMAIL || '').trim();
    if (!to) {
      sendJson(req, res, 400, { error: 'JSON body must include "to" (recipient email)' });
      return;
    }
    const result = await smtpMail.sendSmtpMail({
      to,
      subject: 'Project Tracker — SMTP test (mail7.hku.hk)',
      text: `Test message sent at ${new Date().toISOString()}\n\nServer: ${smtpMail.smtpConfigSummary().host}:${smtpMail.smtpConfigSummary().port}`,
    });
    if (result.ok) {
      sendJson(req, res, 200, {
        ok: true,
        messageId: result.messageId || null,
        to: result.resolvedTo,
      });
    } else {
      sendJson(req, res, 502, { ok: false, error: result.error, detail: result.detail });
    }
  } catch (e) {
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/** Admin-only SMTP test (same as Email test). */
async function handleAdminTestSmtp(req, res) {
  const session = await requireAdmin(req, res);
  if (!session) return;
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  if (!smtpMail.isSmtpConfigured()) {
    sendJson(req, res, 503, { error: 'SMTP not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const to = (body.to || '').trim();
    if (!to) {
      sendJson(req, res, 400, { error: 'JSON body must include "to"' });
      return;
    }
    const result = await smtpMail.sendSmtpMail({
      to,
      subject: 'Project Tracker — admin SMTP test',
      text: `Admin test at ${new Date().toISOString()}`,
    });
    if (result.ok) {
      sendJson(req, res, 200, { ok: true, messageId: result.messageId || null });
    } else {
      sendJson(req, res, 502, { ok: false, error: result.error, detail: result.detail });
    }
  } catch (e) {
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function emailPlainValue(value) {
  const v = String(value ?? '').trim();
  return v || '-';
}

function emailChangeMap(rawChanges) {
  const map = new Map();
  for (const row of Array.isArray(rawChanges) ? rawChanges : []) {
    if (!row || typeof row !== 'object') continue;
    const field = String(row.field || '').trim();
    if (!field) continue;
    const oldValue = Object.prototype.hasOwnProperty.call(row, 'oldValue')
      ? String(row.oldValue ?? '')
      : '';
    const newValue = Object.prototype.hasOwnProperty.call(row, 'newValue')
      ? String(row.newValue ?? '')
      : String(row.value ?? '');
    map.set(field, { oldValue, newValue });
  }
  return map;
}

function workflowCompositeChangeMap(rawChanges) {
  const map = emailChangeMap(rawChanges);
  map.delete('status');
  map.delete('submission');
  return map;
}

function changedValueHtml(change, currentValue) {
  if (!change) return escapeHtml(emailPlainValue(currentValue));
  return `<strong><span style="color:#B00020;">${escapeHtml(emailPlainValue(change.oldValue))}</span></strong> -&gt; <strong><span style="color:#188038;">${escapeHtml(emailPlainValue(change.newValue))}</span></strong>`;
}

function changedValueText(change, currentValue) {
  if (!change) return emailPlainValue(currentValue);
  return `${emailPlainValue(change.oldValue)} -> ${emailPlainValue(change.newValue)}`;
}

function changedActionHtml(change) {
  if (!change) return '';
  const oldValue = emailPlainValue(change.oldValue);
  const newValue = emailPlainValue(change.newValue);
  const hasOld = oldValue !== '-';
  const hasNew = newValue !== '-';
  if (hasOld && hasNew) return changedValueHtml(change, '');
  if (hasNew) {
    return `<strong><span style="color:#188038;">${escapeHtml(newValue)}</span></strong>`;
  }
  return `<strong><span style="color:#B00020;">${escapeHtml(oldValue)}</span></strong>`;
}

function changedActionText(change) {
  if (!change) return '';
  const oldValue = emailPlainValue(change.oldValue);
  const newValue = emailPlainValue(change.newValue);
  const hasOld = oldValue !== '-';
  const hasNew = newValue !== '-';
  if (hasOld && hasNew) return changedValueText(change, '');
  return hasNew ? newValue : oldValue;
}

function eventEmailDateValue(value) {
  const raw = String(value ?? '').trim();
  if (!raw) return '-';
  const m = raw.match(/^(\d{4})-(\d{1,2})-(\d{1,2})/);
  if (m) {
    const d = new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])));
    return new Intl.DateTimeFormat('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      timeZone: 'UTC',
    }).format(d);
  }
  const parsed = new Date(raw);
  if (!Number.isNaN(parsed.getTime())) {
    return new Intl.DateTimeFormat('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      timeZone: 'UTC',
    }).format(parsed);
  }
  return raw;
}

function changedDateHtml(change, currentValue) {
  if (!change) return escapeHtml(eventEmailDateValue(currentValue));
  return `<strong><span style="color:#B00020;">${escapeHtml(eventEmailDateValue(change.oldValue))}</span></strong> -&gt; <strong><span style="color:#188038;">${escapeHtml(eventEmailDateValue(change.newValue))}</span></strong>`;
}

function changedDateText(change, currentValue) {
  if (!change) return eventEmailDateValue(currentValue);
  return `${eventEmailDateValue(change.oldValue)} -> ${eventEmailDateValue(change.newValue)}`;
}

function detailLineHtml(label, valueHtml) {
  return `<strong>${escapeHtml(label)}:</strong> ${valueHtml}`;
}

function detailLineText(label, valueText) {
  return `${label}: ${valueText}`;
}

function eventInlineLinkHtml(label, url) {
  const href = String(url || '').trim();
  if (!href) return '';
  return `${escapeHtml(label)}: <a href="${escapeHtml(href)}" style="color:#1565C0;">${escapeHtml(href)}</a>`;
}

function eventInlineLinkText(label, url) {
  const href = String(url || '').trim();
  if (!href) return '';
  return `${label}: ${href}`;
}

function eventTaskLinkHtml(taskId) {
  const url = taskWebAppUrl(taskId);
  return `Task link: <a href="${escapeHtml(url)}" style="color:#1565C0;">${escapeHtml(url)}</a>`;
}

function eventTaskLinkText(taskId) {
  return `Task link: ${taskWebAppUrl(taskId)}`;
}

function eventSubtaskLinkHtml(subtaskId) {
  const url = subtaskWebAppUrl(subtaskId);
  return `Subtask link: <a href="${escapeHtml(url)}" style="color:#1565C0;">${escapeHtml(url)}</a>`;
}

function eventSubtaskLinkText(subtaskId) {
  return `Subtask link: ${subtaskWebAppUrl(subtaskId)}`;
}

function projectTrackerEmailFooterHtml() {
  return `Best regards,<br>AI &amp; Data Lab<br>Institutional Advancement<br>The University of Hong Kong`;
}

function projectTrackerEmailFooterText() {
  return `Best regards,
AI & Data Lab
Institutional Advancement
The University of Hong Kong`;
}

function mailSubjectSingleLine(s) {
  return String(s)
    .replace(/[\r\n\u2028\u2029]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/** Deduped staff UUIDs from task.assignee_01 … assignee_10. */
function collectTaskAssigneeStaffIds(taskRow) {
  const assigneeIds = [];
  const seen = new Set();
  for (let i = 1; i <= 10; i++) {
    const key = `assignee_${String(i).padStart(2, '0')}`;
    const v = taskRow[key];
    if (v == null) continue;
    const u = String(v).trim();
    if (!u || seen.has(u)) continue;
    seen.add(u);
    assigneeIds.push(u);
  }
  return assigneeIds;
}

/** Deduped staff UUIDs from project.assignee_01 ... assignee_20. */
function collectProjectAssigneeStaffIds(projectRow) {
  const assigneeIds = [];
  const seen = new Set();
  for (let i = 1; i <= 20; i++) {
    const key = `assignee_${String(i).padStart(2, '0')}`;
    const v = (projectRow[key] || '').toString().trim();
    const k = v.toLowerCase();
    if (!v || seen.has(k)) continue;
    seen.add(k);
    assigneeIds.push(v);
  }
  return assigneeIds;
}

/**
 * Default recipients for task-updated emails: assignee_01..10 with values plus
 * create_by, deduped (normalized key -> canonical id string).
 * @param {Record<string, unknown>} taskRow
 * @returns {Map<string, string>}
 */
function buildTaskUpdatedDefaultRecipientStaffIds(taskRow) {
  const recipientByNorm = new Map();
  for (const id of collectTaskAssigneeStaffIds(taskRow)) {
    const raw = String(id).trim();
    if (!raw) continue;
    const key = raw.toLowerCase();
    if (!recipientByNorm.has(key)) recipientByNorm.set(key, raw);
  }
  const createBy = (taskRow.create_by || '').toString().trim();
  if (createBy) {
    const key = createBy.toLowerCase();
    if (!recipientByNorm.has(key)) recipientByNorm.set(key, createBy);
  }
  return recipientByNorm;
}

/** Same slot layout as [collectTaskAssigneeStaffIds] for `public.subtask`. */
function collectSubtaskAssigneeStaffIds(subtaskRow) {
  return collectTaskAssigneeStaffIds(subtaskRow);
}

async function staffNameForEmail(dbClient, staffKey) {
  const key = String(staffKey || '').trim();
  if (!key) return '';
  const { data } = await fetchStaffRowForCreateBy(dbClient, key);
  return (data?.name || '').toString().trim() || key;
}

async function staffNamesForEmail(dbClient, staffKeys) {
  const names = [];
  const seen = new Set();
  for (const keyRaw of staffKeys || []) {
    const key = String(keyRaw || '').trim();
    const norm = key.toLowerCase();
    if (!key || seen.has(norm)) continue;
    seen.add(norm);
    const name = await staffNameForEmail(dbClient, key);
    if (name) names.push(name);
  }
  return names.join(', ');
}

async function projectNameForEmail(dbClient, projectId) {
  const id = String(projectId || '').trim();
  if (!id) return '';
  const { data } = await dbClient
    .from('project')
    .select('name')
    .eq('id', id)
    .maybeSingle();
  return (data?.name || '').toString().trim() || id;
}

async function buildTaskUpdateDetailLines(dbClient, taskRow, changeMap, extra = {}) {
  const projectName = await projectNameForEmail(dbClient, taskRow.project_id);
  const creatorName = await staffNameForEmail(dbClient, taskRow.create_by);
  const assigneeNames = await staffNamesForEmail(dbClient, collectTaskAssigneeStaffIds(taskRow));
  const picName = await staffNameForEmail(dbClient, taskRow.pic);
  const rows = [
    ['Task', changedValueHtml(changeMap.get('taskName'), taskRow.task_name), changedValueText(changeMap.get('taskName'), taskRow.task_name)],
    ['Description', changedValueHtml(changeMap.get('description'), taskRow.description), changedValueText(changeMap.get('description'), taskRow.description)],
    ['Project', changedValueHtml(changeMap.get('project'), projectName), changedValueText(changeMap.get('project'), projectName)],
    ['Creator', escapeHtml(emailPlainValue(creatorName)), emailPlainValue(creatorName)],
    ['Assignees', changedValueHtml(changeMap.get('assignees'), assigneeNames), changedValueText(changeMap.get('assignees'), assigneeNames)],
    ['PIC', changedValueHtml(changeMap.get('pic'), picName), changedValueText(changeMap.get('pic'), picName)],
    ['Priority', changedValueHtml(changeMap.get('priority'), taskRow.priority), changedValueText(changeMap.get('priority'), taskRow.priority)],
    ['Complexity', changedValueHtml(changeMap.get('complexity'), taskRow.complexity), changedValueText(changeMap.get('complexity'), taskRow.complexity)],
    ['Status', changedValueHtml(changeMap.get('status'), taskRow.status), changedValueText(changeMap.get('status'), taskRow.status)],
    ['Commence', changedValueHtml(changeMap.get('commencementStatus'), taskRow.commencement_status), changedValueText(changeMap.get('commencementStatus'), taskRow.commencement_status)],
    ['Start date', changedDateHtml(changeMap.get('startDate'), taskRow.start_date), changedDateText(changeMap.get('startDate'), taskRow.start_date)],
    ['Due date', changedDateHtml(changeMap.get('dueDate'), taskRow.due_date), changedDateText(changeMap.get('dueDate'), taskRow.due_date)],
    ['Submission', changedValueHtml(changeMap.get('submission'), taskRow.submission), changedValueText(changeMap.get('submission'), taskRow.submission)],
  ];
  const commentText = extra.commentText || extra.commentAddedText;
  const filesChange = changeMap.get('files');
  if (filesChange) rows.push(['Files', changedActionHtml(filesChange), changedActionText(filesChange)]);
  const urlsChange = changeMap.get('urls');
  if (urlsChange) rows.push(['URLs', changedActionHtml(urlsChange), changedActionText(urlsChange)]);
  if (commentText) {
    rows.push([
      'Comment',
      `<strong><span style="color:#188038;">${escapeHtml(emailPlainValue(commentText))}</span></strong>`,
      emailPlainValue(commentText),
    ]);
  }
  return {
    html: rows.map(([label, html]) => detailLineHtml(label, html)).join('<br><br>'),
    text: rows.map(([label, _html, text]) => detailLineText(label, text)).join('\n\n'),
  };
}

async function buildSubtaskUpdateDetailLines(dbClient, row, changeMap, extra = {}) {
  const creatorName = await staffNameForEmail(dbClient, row.create_by);
  const assigneeNames = await staffNamesForEmail(dbClient, collectSubtaskAssigneeStaffIds(row));
  const picName = await staffNameForEmail(dbClient, row.pic);
  let projectName = '';
  let parentTaskName = '';
  if (row.task_id) {
    const { data: taskRow } = await dbClient
      .from('task')
      .select('task_name, project_id')
      .eq('id', row.task_id)
      .maybeSingle();
    parentTaskName = (taskRow?.task_name || '').toString().trim();
    projectName = await projectNameForEmail(dbClient, taskRow?.project_id);
  }
  const rows = [
    ['Subtask', changedValueHtml(changeMap.get('subtaskName'), row.subtask_name), changedValueText(changeMap.get('subtaskName'), row.subtask_name)],
    ['Description', changedValueHtml(changeMap.get('description'), row.description), changedValueText(changeMap.get('description'), row.description)],
    ['Project', changedValueHtml(changeMap.get('project'), projectName), changedValueText(changeMap.get('project'), projectName)],
    ['Task', escapeHtml(emailPlainValue(parentTaskName)), emailPlainValue(parentTaskName)],
    ['Creator', escapeHtml(emailPlainValue(creatorName)), emailPlainValue(creatorName)],
    ['Assignees', changedValueHtml(changeMap.get('assignees'), assigneeNames), changedValueText(changeMap.get('assignees'), assigneeNames)],
    ['PIC', changedValueHtml(changeMap.get('pic'), picName), changedValueText(changeMap.get('pic'), picName)],
    ['Priority', changedValueHtml(changeMap.get('priority'), row.priority), changedValueText(changeMap.get('priority'), row.priority)],
    ['Complexity', changedValueHtml(changeMap.get('complexity'), row.complexity), changedValueText(changeMap.get('complexity'), row.complexity)],
    ['Status', changedValueHtml(changeMap.get('status'), row.status), changedValueText(changeMap.get('status'), row.status)],
    ['Commence', changedValueHtml(changeMap.get('commencementStatus'), row.commencement_status), changedValueText(changeMap.get('commencementStatus'), row.commencement_status)],
    ['Start date', changedDateHtml(changeMap.get('startDate'), row.start_date), changedDateText(changeMap.get('startDate'), row.start_date)],
    ['Due date', changedDateHtml(changeMap.get('dueDate'), row.due_date), changedDateText(changeMap.get('dueDate'), row.due_date)],
    ['Submission', changedValueHtml(changeMap.get('submission'), row.submission), changedValueText(changeMap.get('submission'), row.submission)],
  ];
  const commentText = extra.commentText || extra.commentAddedText;
  const filesChange = changeMap.get('files');
  if (filesChange) rows.push(['Files', changedActionHtml(filesChange), changedActionText(filesChange)]);
  const urlsChange = changeMap.get('urls');
  if (urlsChange) rows.push(['URLs', changedActionHtml(urlsChange), changedActionText(urlsChange)]);
  if (commentText) {
    rows.push([
      'Comment',
      `<strong><span style="color:#188038;">${escapeHtml(emailPlainValue(commentText))}</span></strong>`,
      emailPlainValue(commentText),
    ]);
  }
  return {
    html: rows.map(([label, html]) => detailLineHtml(label, html)).join('<br><br>'),
    text: rows.map(([label, _html, text]) => detailLineText(label, text)).join('\n\n'),
  };
}

/**
 * Task-comment email to task creator only (`handleNotifyTaskComment`).
 * @param {{ recipientDisplayName: string, commentDescription: string, taskName: string, taskUrl: string }} p
 */
function buildTaskCommentCreatorEmailHtml(p) {
  const safeHi = escapeHtml(p.recipientDisplayName);
  let desc = String(p.commentDescription || '').trim();
  if (!desc) desc = '(no text)';
  if (desc.length > TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN) {
    desc = `${desc.slice(0, TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN)}…`;
  }
  const safeDesc = escapeHtml(desc);
  const safeTaskUrlAttr = escapeHtml(p.taskUrl);
  const safeTitle = escapeHtml(p.taskName);
  const safeLandingHref = escapeHtml(TASK_UPDATE_NOTIFY_PROJECT_TRACKER_HREF);
  const bodyFont =
    "font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;line-height:1.5;color:#000000;";
  return `<div style="margin:0;${bodyFont}">Hi ${safeHi},<br><br>
<span style="color:#000000;font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;">Comment is added – ${safeDesc}</span><br><br>
<a href="${safeTaskUrlAttr}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;font-weight:bold;text-decoration:underline;color:#1565C0;">${safeTitle}</a><br><br>
<a href="${safeLandingHref}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;color:#1565C0;">Project Tracker</a></div>`;
}

function buildTaskCommentCreatorEmailText(p) {
  let desc = String(p.commentDescription || '').trim();
  if (!desc) desc = '(no text)';
  if (desc.length > TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN) {
    desc = `${desc.slice(0, TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN)}…`;
  }
  return `Hi ${p.recipientDisplayName},

Comment is added – ${desc}

${p.taskName}
${p.taskUrl}

Project Tracker
${TASK_UPDATE_NOTIFY_PROJECT_TRACKER_HREF}`;
}

/**
 * Task comment **edited** notify (`handleNotifyTaskEditedComment`): Hi + edited line + task link +
 * Updated by / at + Project Tracker; Aptos 16px.
 *
 * @param {{ recipientDisplayName: string, commentDescription: string, taskName: string, taskUrl: string, updaterDisplayName: string, updatedAtLine: string }} p
 */
function buildTaskCommentEditedEmailHtml(p) {
  const safeHi = escapeHtml(p.recipientDisplayName);
  let desc = String(p.commentDescription || '').trim();
  if (!desc) desc = '(no text)';
  if (desc.length > TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN) {
    desc = `${desc.slice(0, TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN)}…`;
  }
  const safeDescHtml = desc
    .split(/\r?\n/)
    .map((line) => escapeHtml(line))
    .join('<br>');
  const safeTaskUrlAttr = escapeHtml(p.taskUrl);
  const safeTitle = escapeHtml(p.taskName);
  const safeUpdater = escapeHtml(p.updaterDisplayName);
  const safeUpdatedAt = escapeHtml(p.updatedAtLine);
  const safeLandingHref = escapeHtml(PROJECT_TRACKER_LANDING_URL);
  const bodyFont =
    "font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;line-height:1.5;color:#000000;";
  return `<div style="margin:0;${bodyFont}">Hi ${safeHi},<br><br>
<span style="color:#000000;font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;">Comment is edited – ${safeDescHtml}</span><br><br>
<a href="${safeTaskUrlAttr}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;font-weight:bold;text-decoration:underline;color:#1565C0;">${safeTitle}</a><br><br>
Updated by: ${safeUpdater}<br><br>
Updated at: ${safeUpdatedAt}<br><br>
<a href="${safeLandingHref}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;color:#1565C0;">Project Tracker</a></div>`;
}

function buildTaskCommentEditedEmailText(p) {
  let desc = String(p.commentDescription || '').trim();
  if (!desc) desc = '(no text)';
  if (desc.length > TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN) {
    desc = `${desc.slice(0, TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN)}…`;
  }
  return `Hi ${p.recipientDisplayName},

Comment is edited – ${desc}

${p.taskName}
${p.taskUrl}

Updated by: ${p.updaterDisplayName}

Updated at: ${p.updatedAtLine}

Project Tracker
${PROJECT_TRACKER_LANDING_URL}`;
}

/**
 * “Project Tracker” link in sub-task comment → creator emails (strict product URL, no trailing path).
 */
const SUBTASK_COMMENT_NOTIFY_PROJECT_TRACKER_HREF = PROJECT_TRACKER_LANDING_URL;

/** En dash (U+2013) after “Comment is added”, per product template. */
const SUBTASK_COMMENT_ADDED_LINE_EN_DASH = '\u2013';

/**
 * Plain text for email from `subtask_comment.description` (`text` column; also accepts JSON
 * `{"value":"..."}` when stored as a string or parsed object, matching `{description.value}`).
 */
function subtaskCommentDescriptionPlainText(raw) {
  if (raw == null || raw === '') return '';
  if (typeof raw === 'object' && raw !== null && !Array.isArray(raw)) {
    if (Object.prototype.hasOwnProperty.call(raw, 'value')) {
      return String(raw.value ?? '').trim();
    }
  }
  const s = String(raw).trim();
  if (s.startsWith('{') && s.includes('"value"')) {
    try {
      const o = JSON.parse(s);
      if (o && typeof o === 'object' && o.value != null) {
        return String(o.value).trim();
      }
    } catch (_) {
      /* use full string */
    }
  }
  return s;
}

/**
 * Sub-task comment email to sub-task creator only (`handleNotifySubtaskComment`).
 * Subject: `{comment author} comments on sub-task "{subtask.subtask_name}"`.
 * Body: Hi {creator staff.name}; Comment is added – {description}; bold+underlined
 * {subtask.subtask_name} → `subtaskWebAppUrl(subtask.id)`; “Project Tracker” → product URL; Aptos 16px.
 *
 * @param {{ recipientDisplayName: string, commentDescription: string, subtaskName: string, subtaskUrl: string }} p
 */
function buildSubtaskCommentCreatorEmailHtml(p) {
  const safeHi = escapeHtml(p.recipientDisplayName);
  let desc = subtaskCommentDescriptionPlainText(p.commentDescription);
  if (!desc) desc = '(no text)';
  if (desc.length > TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN) {
    desc = `${desc.slice(0, TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN)}…`;
  }
  const safeDesc = escapeHtml(desc);
  const safeSubtaskUrlAttr = escapeHtml(p.subtaskUrl);
  const safeTitle = escapeHtml(p.subtaskName);
  const safeLandingHref = escapeHtml(SUBTASK_COMMENT_NOTIFY_PROJECT_TRACKER_HREF);
  const bodyFont =
    "font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;line-height:1.5;color:#000000;";
  return `<div style="margin:0;${bodyFont}">Hi ${safeHi},<br><br>
Comment is added ${SUBTASK_COMMENT_ADDED_LINE_EN_DASH} ${safeDesc}<br><br>
<a href="${safeSubtaskUrlAttr}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;font-weight:bold;text-decoration:underline;color:#1565C0;">${safeTitle}</a><br><br>
<a href="${safeLandingHref}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;color:#1565C0;">Project Tracker</a></div>`;
}

function buildSubtaskCommentCreatorEmailText(p) {
  let desc = subtaskCommentDescriptionPlainText(p.commentDescription);
  if (!desc) desc = '(no text)';
  if (desc.length > TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN) {
    desc = `${desc.slice(0, TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN)}…`;
  }
  return `Hi ${p.recipientDisplayName},

Comment is added ${SUBTASK_COMMENT_ADDED_LINE_EN_DASH} ${desc}

${p.subtaskName}
${p.subtaskUrl}

Project Tracker
${SUBTASK_COMMENT_NOTIFY_PROJECT_TRACKER_HREF}`;
}

/**
 * Sub-task comment **edited** notify (`handleNotifySubtaskEditedComment`): Hi + edited line + sub-task link +
 * Updated by / at + Project Tracker; Aptos 16px. Description uses [subtaskCommentDescriptionPlainText].
 *
 * @param {{ recipientDisplayName: string, commentDescription: unknown, subtaskName: string, subtaskUrl: string, updaterDisplayName: string, updatedAtLine: string }} p
 */
function buildSubtaskCommentEditedEmailHtml(p) {
  const safeHi = escapeHtml(p.recipientDisplayName);
  let descPlain = subtaskCommentDescriptionPlainText(p.commentDescription);
  if (!descPlain) descPlain = '(no text)';
  if (descPlain.length > TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN) {
    descPlain = `${descPlain.slice(0, TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN)}…`;
  }
  const safeDescHtml = descPlain
    .split(/\r?\n/)
    .map((line) => escapeHtml(line))
    .join('<br>');
  const safeSubtaskUrlAttr = escapeHtml(p.subtaskUrl);
  const safeTitle = escapeHtml(p.subtaskName);
  const safeUpdater = escapeHtml(p.updaterDisplayName);
  const safeUpdatedAt = escapeHtml(p.updatedAtLine);
  const safeLandingHref = escapeHtml(PROJECT_TRACKER_LANDING_URL);
  const bodyFont =
    "font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;line-height:1.5;color:#000000;";
  return `<div style="margin:0;${bodyFont}">Hi ${safeHi},<br><br>
<span style="color:#000000;font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;">Comment is edited – ${safeDescHtml}</span><br><br>
<a href="${safeSubtaskUrlAttr}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;font-weight:bold;text-decoration:underline;color:#1565C0;">${safeTitle}</a><br><br>
Updated by: ${safeUpdater}<br><br>
Updated at: ${safeUpdatedAt}<br><br>
<a href="${safeLandingHref}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;color:#1565C0;">Project Tracker</a></div>`;
}

function buildSubtaskCommentEditedEmailText(p) {
  let descPlain = subtaskCommentDescriptionPlainText(p.commentDescription);
  if (!descPlain) descPlain = '(no text)';
  if (descPlain.length > TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN) {
    descPlain = `${descPlain.slice(0, TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN)}…`;
  }
  return `Hi ${p.recipientDisplayName},

Comment is edited – ${descPlain}

${p.subtaskName}
${p.subtaskUrl}

Updated by: ${p.updaterDisplayName}

Updated at: ${p.updatedAtLine}

Project Tracker
${PROJECT_TRACKER_LANDING_URL}`;
}

/** Formats task.update_date (timestamptz) as YYYY-MM-DD in Asia/Hong_Kong. */
function formatUpdateDateYYYYMMDD(raw) {
  if (raw == null || raw === '') return '—';
  const d = new Date(raw);
  if (Number.isNaN(d.getTime())) return '—';
  return d.toLocaleDateString('en-CA', { timeZone: 'Asia/Hong_Kong' });
}

/** Formats task.update_date as `yyyy-mm-dd hh:mm` (wall clock in Asia/Hong_Kong). */
function formatUpdateDateTimeYmdHm(raw) {
  if (raw == null || raw === '') return '—';
  const d = new Date(raw);
  if (Number.isNaN(d.getTime())) return '—';
  const datePart = d.toLocaleDateString('en-CA', { timeZone: 'Asia/Hong_Kong' });
  const timeParts = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Hong_Kong',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).formatToParts(d);
  let hh = '';
  let mm = '';
  for (const p of timeParts) {
    if (p.type === 'hour') hh = p.value.padStart(2, '0');
    if (p.type === 'minute') mm = p.value.padStart(2, '0');
  }
  const hm = hh && mm ? `${hh}:${mm}` : '—';
  return `${datePart} ${hm}`;
}

/** Formats task.due_date as YYYY-MM-DD for emails (avoids timezone shift on date-only strings). */
function formatTaskDueDateYYYYMMDD(raw) {
  if (raw == null || raw === '') return '—';
  const s = String(raw).trim();
  const m = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (m) return `${m[1]}-${m[2]}-${m[3]}`;
  const d = new Date(s);
  if (Number.isNaN(d.getTime())) return '—';
  const y = d.getUTCFullYear();
  const mo = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${y}-${mo}-${day}`;
}

function cronSecretFromRequest(req) {
  const headers = req.headers || {};
  const h =
    headers['x-cron-secret'] ||
    headers['X-Cron-Secret'] ||
    (() => {
      const k = Object.keys(headers).find((n) => n.toLowerCase() === 'x-cron-secret');
      return k ? headers[k] : '';
    })();
  return String(h || '').trim();
}

function verifyCronSecret(req) {
  if (!CRON_SECRET) return false;
  const h = cronSecretFromRequest(req);
  const auth = String(req.headers.authorization || '');
  const bearer = auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';
  return h === CRON_SECRET || bearer === CRON_SECRET;
}

/** Hong Kong calendar day bounds (ms) for a date/timestamptz from the DB. */
function hkDayStartEndMs(raw) {
  if (raw == null || raw === '') return null;
  const s = String(raw).trim();
  const m = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (m) {
    const dayStr = `${m[1]}-${m[2]}-${m[3]}`;
    return {
      startMs: new Date(`${dayStr}T00:00:00+08:00`).getTime(),
      endMs: new Date(`${dayStr}T23:59:59.999+08:00`).getTime(),
    };
  }
  const t = new Date(s).getTime();
  if (Number.isNaN(t)) return null;
  const d = new Date(s);
  const y = d.getUTCFullYear();
  const mo = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  const dayStr = `${y}-${mo}-${day}`;
  return {
    startMs: new Date(`${dayStr}T00:00:00+08:00`).getTime(),
    endMs: new Date(`${dayStr}T23:59:59.999+08:00`).getTime(),
  };
}

/** True when [now] is at or past 80% of the interval from start-date (HK 00:00) to due-date (HK 23:59:59.999). */
function hasReachedEightyPercentWindow(startRaw, dueRaw, nowMs) {
  const startB = hkDayStartEndMs(startRaw);
  const dueB = hkDayStartEndMs(dueRaw);
  if (!startB || !dueB) return false;
  const t0 = startB.startMs;
  const t1 = dueB.endMs;
  const total = t1 - t0;
  if (total <= 0) return false;
  const elapsed = nowMs - t0;
  return elapsed / total >= 0.8;
}

function taskStatusBlocksUrgentReminder(statusRaw) {
  const s = String(statusRaw || '')
    .trim()
    .toLowerCase();
  return s === 'completed' || s === 'deleted';
}

function isPausedStatus(pauseStatusRaw) {
  return String(pauseStatusRaw || '').trim().toLowerCase() === 'paused';
}

async function fetchPausedProjectIdSet(dbClient) {
  const { data, error } = await dbClient
    .from('project')
    .select('id,pause_status')
    .eq('pause_status', 'Paused');
  if (error || !data) return new Set();
  const set = new Set();
  for (const row of data) {
    const id = String(row.id || '').trim();
    if (id) set.add(id);
  }
  return set;
}

function taskReminderPaused(taskRow, pausedProjectIds) {
  if (isPausedStatus(taskRow?.pause_status)) return true;
  const projectId = String(taskRow?.project_id || '').trim();
  return !!projectId && pausedProjectIds.has(projectId);
}

/** Task ids whose parent row blocks sub-task reminder emails until it is restored/resumed. */
async function fetchSubtaskReminderBlockedParentTaskIdSet(dbClient) {
  const pausedProjectIds = await fetchPausedProjectIdSet(dbClient);
  const { data, error } = await dbClient.from('task').select('id,status,pause_status,project_id');
  if (error || !data) return new Set();
  const set = new Set();
  for (const row of data) {
    const st = String(row.status ?? '')
      .trim()
      .toLowerCase();
    if (st === 'deleted' || taskReminderPaused(row, pausedProjectIds)) {
      const id = String(row.id || '').trim();
      if (id) set.add(id);
    }
  }
  return set;
}

/**
 * AssigneeOverdueReminder + Subtask_AssigneeOverdueReminder — after `isCalendarPastDue`
 * (HK **today** > due_date). Same daily cron as other jobs: **09:00 Asia/Hong_Kong** (UTC+8).
 *
 * Task / sub-task rows:
 * - **Pending** (and null/empty, treated like Pending): send.
 * - **Submitted**: do not send.
 * - **Returned**: send.
 * - Any other value (e.g. Accepted): do not send.
 */
function submissionAllowsAssigneeOverdueReminder(submissionRaw) {
  const s =
    submissionRaw == null ? '' : String(submissionRaw).trim().toLowerCase();
  if (s === 'submitted') return false;
  if (s === 'pending' || s === 'returned' || s === '') return true;
  return false;
}

/** Today's calendar date (YYYY-MM-DD) in Asia/Hong_Kong. */
function hkTodayYyyyMmDd() {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Hong_Kong',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date());
}

/** Due date as YYYY-MM-DD for calendar comparison, or null. */
function dueDateYyyyMmDdOnly(raw) {
  if (raw == null || raw === '') return null;
  const s = formatTaskDueDateYYYYMMDD(raw);
  if (!s || s === '—') return null;
  return s;
}

function isCalendarOnOrBeforeDue(todayYmd, dueRaw) {
  const d = dueDateYyyyMmDdOnly(dueRaw);
  if (!d) return false;
  return todayYmd <= d;
}

/** Urgent 80% emails run only before the due calendar day (not on due date). */
function isCalendarStrictlyBeforeDue(todayYmd, dueRaw) {
  const d = dueDateYyyyMmDdOnly(dueRaw);
  if (!d) return false;
  return todayYmd < d;
}

function isCalendarDueToday(todayYmd, dueRaw) {
  const d = dueDateYyyyMmDdOnly(dueRaw);
  if (!d) return false;
  return todayYmd === d;
}

function isCalendarPastDue(todayYmd, dueRaw) {
  const d = dueDateYyyyMmDdOnly(dueRaw);
  if (!d) return false;
  return todayYmd > d;
}

/**
 * After the due calendar date (HK), reset reminder flags so rows are clean.
 */
async function resetUrgentReminderForPastDueTasks(dbClient, todayYmd, summary) {
  const { data: rows, error } = await dbClient
    .from('task')
    .select(
      'id, due_date, urgent_reminder_sent, urgent_reminder_last_sent_on, due_today_reminder_sent_on, creator_due_today_reminder_sent_on, creator_urgent_reminder_last_sent_on',
    )
    .not('due_date', 'is', null);
  if (error) {
    summary.errors.push(`past-due cleanup: ${error.message}`);
    return;
  }
  for (const row of rows || []) {
    if (!isCalendarPastDue(todayYmd, row.due_date)) continue;
    const sent = row.urgent_reminder_sent === true;
    const hasLast = row.urgent_reminder_last_sent_on != null && row.urgent_reminder_last_sent_on !== '';
    const hasDueToday =
      row.due_today_reminder_sent_on != null && row.due_today_reminder_sent_on !== '';
    const hasCreatorDue =
      row.creator_due_today_reminder_sent_on != null && row.creator_due_today_reminder_sent_on !== '';
    const hasCreatorUrgent =
      row.creator_urgent_reminder_last_sent_on != null && row.creator_urgent_reminder_last_sent_on !== '';
    if (!sent && !hasLast && !hasDueToday && !hasCreatorDue && !hasCreatorUrgent) continue;
    const id = String(row.id || '').trim();
    if (!id) continue;
    const { error: uErr } = await dbClient
      .from('task')
      .update({
        urgent_reminder_sent: false,
        urgent_reminder_last_sent_on: null,
        due_today_reminder_sent_on: null,
        creator_due_today_reminder_sent_on: null,
        creator_urgent_reminder_last_sent_on: null,
      })
      .eq('id', id);
    if (uErr) {
      summary.errors.push(`past-due reset ${id}: ${uErr.message}`);
    } else {
      summary.tasksResetPastDue += 1;
    }
  }
}

function buildUrgentTaskReminderEmail(displayName, taskName, taskUrl, dueYmd) {
  const safeName = escapeHtml(displayName);
  const safeTitle = escapeHtml(taskName);
  const safeUrl = escapeHtml(taskUrl);
  const safeDue = escapeHtml(dueYmd);
  const landing = `${String(PROJECT_TRACKER_LANDING_URL || '').replace(/\/$/, '')}/`;
  const safeLanding = escapeHtml(landing);
  const html = `Hi ${safeName}. You have an <b>upcoming</b> task due.<br><br>
<b><u><a href="${safeUrl}" style="color:#1565C0;">${safeTitle}</a></u></b><br><br>
Due Date: ${safeDue}<br><br>
<a href="${safeLanding}" style="color:#1565C0;">Project Tracker</a>`;
  const text = `Hi ${displayName}. You have an upcoming task due.

${taskName}
${taskUrl}

Due Date: ${dueYmd}

Project Tracker
${landing}`;
  return { html, text };
}

function buildDueTodayTaskReminderEmail(displayName, taskName, taskUrl, dueYmd) {
  const safeName = escapeHtml(displayName);
  const safeTitle = escapeHtml(taskName);
  const safeUrl = escapeHtml(taskUrl);
  const safeDue = escapeHtml(dueYmd);
  const landing = `${String(PROJECT_TRACKER_LANDING_URL || '').replace(/\/$/, '')}/`;
  const safeLanding = escapeHtml(landing);
  const html = `Hi ${safeName}. You have a task <b>due today</b><br><br>
<b><u><a href="${safeUrl}" style="color:#1565C0;">${safeTitle}</a></u></b><br><br>
Due Date: ${safeDue}<br><br>
<a href="${safeLanding}" style="color:#1565C0;">Project Tracker</a>`;
  const text = `Hi ${displayName}. You have a task due today.

${taskName}
${taskUrl}

Due Date: ${dueYmd}

Project Tracker
${landing}`;
  return { html, text };
}

/**
 * Due-today reminder for task creator only ([creator_due_today_reminder_sent_on]).
 * @param {string} recipientDisplayName — creator (`create_by` → staff.name)
 * @param {string} picDisplayName — PIC (`task.pic` → staff.name)
 */
function buildCreatorDueTodayTaskReminderEmail(
  recipientDisplayName,
  picDisplayName,
  taskName,
  taskUrl,
  dueYmd,
) {
  const safeRecipient = escapeHtml(recipientDisplayName);
  const safePic = escapeHtml(picDisplayName);
  const safeTitle = escapeHtml(taskName);
  const safeUrl = escapeHtml(taskUrl);
  const safeDue = escapeHtml(dueYmd);
  const landing = `${String(PROJECT_TRACKER_LANDING_URL || '').replace(/\/$/, '')}/`;
  const safeLanding = escapeHtml(landing);
  const html = `Hi ${safeRecipient},<br><br>
${safePic} has task due today.<br><br>
<b><u><a href="${safeUrl}" style="color:#1565C0;">${safeTitle}</a></u></b><br><br>
Due Date: ${safeDue}<br><br>
<a href="${safeLanding}" style="color:#1565C0;">Project Tracker</a>`;
  const text = `Hi ${recipientDisplayName},

${picDisplayName} has task due today.

${taskName}
${taskUrl}

Due Date: ${dueYmd}

Project Tracker
${landing}`;
  return { html, text };
}

/**
 * Due-today (HK) — sub-task creator only ([subtask_creator_due_today_reminder_sent_on]).
 * @param {string} recipientDisplayName — creator greeting (`create_by` → staff.name, else name)
 * @param {string} picDisplayName — PIC line (`subtask.pic` → staff.name, else name)
 */
function buildCreatorDueTodaySubtaskReminderEmail(
  recipientDisplayName,
  picDisplayName,
  subtaskName,
  subtaskUrl,
  dueYmd,
) {
  const safeRecipient = escapeHtml(recipientDisplayName);
  const safePic = escapeHtml(picDisplayName);
  const safeTitle = escapeHtml(subtaskName);
  const safeUrl = escapeHtml(subtaskUrl);
  const safeDue = escapeHtml(dueYmd);
  const safeLanding = escapeHtml(SUBTASK_COMMENT_NOTIFY_PROJECT_TRACKER_HREF);
  const html = `Hi ${safeRecipient}, <br><br>
${safePic} has sub-task due today.<br><br>
<b><u><a href="${safeUrl}" style="color:#1565C0;">${safeTitle}</a></u></b><br><br>
Due Date: ${safeDue}<br><br>
<a href="${safeLanding}" style="color:#1565C0;">Project Tracker</a>`;
  const text = `Hi ${recipientDisplayName},

${picDisplayName} has sub-task due today.

${subtaskName}
${subtaskUrl}

Due Date: ${dueYmd}

Project Tracker
${SUBTASK_COMMENT_NOTIFY_PROJECT_TRACKER_HREF}`;
  return { html, text };
}

/**
 * Overdue (HK) — task creator ([CreatorOverdueReminder]).
 * @param {string} recipientDisplayName — creator (`create_by` → staff.name)
 * @param {string} picDisplayName — PIC (`task.pic` → staff.name)
 */
function buildCreatorOverdueTaskReminderEmail(
  recipientDisplayName,
  picDisplayName,
  taskName,
  taskUrl,
  dueYmd,
) {
  const safeRecipient = escapeHtml(recipientDisplayName);
  const safePic = escapeHtml(picDisplayName);
  const safeTitle = escapeHtml(taskName);
  const safeUrl = escapeHtml(taskUrl);
  const safeDue = escapeHtml(dueYmd);
  const landing = `${String(PROJECT_TRACKER_LANDING_URL || '').replace(/\/$/, '')}/`;
  const safeLanding = escapeHtml(landing);
  const html = `Hi ${safeRecipient},<br><br>
${safePic} has a task overdue.<br><br>
<b><u><a href="${safeUrl}" style="color:#1565C0;">${safeTitle}</a></u></b><br><br>
Due Date: <span style="color:red;">${safeDue}</span><br><br>
<a href="${safeLanding}" style="color:#1565C0;">Project Tracker</a>`;
  const text = `Hi ${recipientDisplayName},

${picDisplayName} has a task overdue.

${taskName}
${taskUrl}

Due Date: ${dueYmd}

Project Tracker
${landing}`;
  return { html, text };
}

/** Overdue (HK) — task assignees. */
function buildAssigneeOverdueTaskReminderEmail(displayName, taskName, taskUrl, dueYmd) {
  const safeName = escapeHtml(displayName);
  const safeTitle = escapeHtml(taskName);
  const safeUrl = escapeHtml(taskUrl);
  const safeDue = escapeHtml(dueYmd);
  const landing = OVERDUE_REMINDER_LANDING_HREF;
  const safeLanding = escapeHtml(landing);
  const html = `Hi ${safeName}. You have a task <b>overdue</b><br><br>
<b><u><a href="${safeUrl}" style="color:#1565C0;">${safeTitle}</a></u></b><br><br>
Due Date: <span style="color:red;">${safeDue}</span><br><br>
<a href="${safeLanding}" style="color:#1565C0;">Project Tracker</a>`;
  const text = `Hi ${displayName}. You have a task overdue.

${taskName}
${taskUrl}

Due Date: ${dueYmd}

Project Tracker
${landing}`;
  return { html, text };
}

/**
 * Overdue (HK) — sub-task creator ([Subtask_CreatorOverdueReminder]).
 * @param {string} recipientDisplayName — creator (`create_by` → staff.name)
 * @param {string} picDisplayName — PIC (`subtask.pic` → staff.name)
 */
function buildCreatorOverdueSubtaskReminderEmail(
  recipientDisplayName,
  picDisplayName,
  subtaskName,
  subtaskUrl,
  dueYmd,
) {
  const safeRecipient = escapeHtml(recipientDisplayName);
  const safePic = escapeHtml(picDisplayName);
  const safeTitle = escapeHtml(subtaskName);
  const safeUrl = escapeHtml(subtaskUrl);
  const safeDue = escapeHtml(dueYmd);
  const landing = `${String(PROJECT_TRACKER_LANDING_URL || '').replace(/\/$/, '')}/`;
  const safeLanding = escapeHtml(landing);
  const html = `Hi ${safeRecipient},<br><br>
${safePic} has a sub-task overdue.<br><br>
<b><u><a href="${safeUrl}" style="color:#1565C0;">${safeTitle}</a></u></b><br><br>
Due Date: <span style="color:red;">${safeDue}</span><br><br>
<a href="${safeLanding}" style="color:#1565C0;">Project Tracker</a>`;
  const text = `Hi ${recipientDisplayName},

${picDisplayName} has a sub-task overdue.

${subtaskName}
${subtaskUrl}

Due Date: ${dueYmd}

Project Tracker
${landing}`;
  return { html, text };
}

/** Overdue (HK) — sub-task assignees. */
function buildAssigneeOverdueSubtaskReminderEmail(
  displayName,
  subtaskName,
  subtaskUrl,
  dueYmd,
) {
  const safeName = escapeHtml(displayName);
  const safeTitle = escapeHtml(subtaskName);
  const safeUrl = escapeHtml(subtaskUrl);
  const safeDue = escapeHtml(dueYmd);
  const landing = OVERDUE_REMINDER_LANDING_HREF;
  const safeLanding = escapeHtml(landing);
  const html = `Hi ${safeName}. You have a sub-task <b>overdue</b><br><br>
<b><u><a href="${safeUrl}" style="color:#1565C0;">${safeTitle}</a></u></b><br><br>
Due Date: <span style="color:red;">${safeDue}</span><br><br>
<a href="${safeLanding}" style="color:#1565C0;">Project Tracker</a>`;
  const text = `Hi ${displayName}. You have a sub-task overdue.

${subtaskName}
${subtaskUrl}

Due Date: ${dueYmd}

Project Tracker
${landing}`;
  return { html, text };
}

/**
 * 80% window — creator only. Subject/body format fixed for product spec.
 * @param {string} recipientDisplayName — task creator (`create_by` → staff.name)
 * @param {string} picDisplayName — PIC (`task.pic` → staff.name)
 */
function buildCreatorUrgentTaskReminderEmail(
  recipientDisplayName,
  picDisplayName,
  taskName,
  taskUrl,
  dueYmd,
) {
  const safeRecipient = escapeHtml(recipientDisplayName);
  const safePic = escapeHtml(picDisplayName);
  const safeTitle = escapeHtml(taskName);
  const safeUrl = escapeHtml(taskUrl);
  const safeDue = escapeHtml(dueYmd);
  const landing = `${String(PROJECT_TRACKER_LANDING_URL || '').replace(/\/$/, '')}/`;
  const safeLanding = escapeHtml(landing);
  const html = `Hi ${safeRecipient},<br><br>
${safePic} has an <b>upcoming</b> task due.<br><br>
<b><u><a href="${safeUrl}" style="color:#1565C0;">${safeTitle}</a></u></b><br><br>
Due Date: ${safeDue}<br><br>
<a href="${safeLanding}" style="color:#1565C0;">Project Tracker</a>`;
  const text = `Hi ${recipientDisplayName},

${picDisplayName} has an upcoming task due.

${taskName}
${taskUrl}

Due Date: ${dueYmd}

Project Tracker
${landing}`;
  return { html, text };
}

/**
 * 80% window — sub-task creator only ([runCreatorUrgentSubtaskReminderJob]).
 * @param {string} recipientDisplayName — creator (`create_by` → staff.name)
 * @param {string} picDisplayName — PIC (`subtask.pic` → staff.name)
 */
function buildCreatorUrgentSubtaskReminderEmail(
  recipientDisplayName,
  picDisplayName,
  subtaskName,
  subtaskUrl,
  dueYmd,
) {
  const safeRecipient = escapeHtml(recipientDisplayName);
  const safePic = escapeHtml(picDisplayName);
  const safeTitle = escapeHtml(subtaskName);
  const safeUrl = escapeHtml(subtaskUrl);
  const safeDue = escapeHtml(dueYmd);
  const landing = `${String(PROJECT_TRACKER_LANDING_URL || '').replace(/\/$/, '')}/`;
  const safeLanding = escapeHtml(landing);
  const html = `Hi ${safeRecipient}.<br><br>
${safePic} has an <b>upcoming</b> sub-task due.<br><br>
<b><u><a href="${safeUrl}" style="color:#1565C0;">${safeTitle}</a></u></b><br><br>
Due Date: ${safeDue}<br><br>
<a href="${safeLanding}" style="color:#1565C0;">Project Tracker</a>`;
  const text = `Hi ${recipientDisplayName}.

${picDisplayName} has an upcoming sub-task due.

${subtaskName}
${subtaskUrl}

Due Date: ${dueYmd}

Project Tracker
${landing}`;
  return { html, text };
}

/**
 * 80% window — sub-task assignees (assignee_01..10). Subject/body format fixed for product spec.
 */
function buildAssigneeUrgentSubtaskReminderEmail(
  displayName,
  subtaskName,
  subtaskUrl,
  dueYmd,
) {
  const safeName = escapeHtml(displayName);
  const safeTitle = escapeHtml(subtaskName);
  const safeUrl = escapeHtml(subtaskUrl);
  const safeDue = escapeHtml(dueYmd);
  const landing = `${String(PROJECT_TRACKER_LANDING_URL || '').replace(/\/$/, '')}/`;
  const safeLanding = escapeHtml(landing);
  const html = `Hi ${safeName}. You have an <b>upcoming</b> sub-task due.<br><br>
<b><u><a href="${safeUrl}" style="color:#1565C0;">${safeTitle}</a></u></b><br><br>
Due Date: ${safeDue}<br><br>
<a href="${safeLanding}" style="color:#1565C0;">Project Tracker</a>`;
  const text = `Hi ${displayName}. You have an upcoming sub-task due.

${subtaskName}
${subtaskUrl}

Due Date: ${dueYmd}

Project Tracker
${landing}`;
  return { html, text };
}

/**
 * Due-today (HK) — sub-task assignees. Subject/body format fixed for product spec.
 */
function buildAssigneeDueTodaySubtaskReminderEmail(
  displayName,
  subtaskName,
  subtaskUrl,
  dueYmd,
) {
  const safeName = escapeHtml(displayName);
  const safeTitle = escapeHtml(subtaskName);
  const safeUrl = escapeHtml(subtaskUrl);
  const safeDue = escapeHtml(dueYmd);
  const landing = `${String(PROJECT_TRACKER_LANDING_URL || '').replace(/\/$/, '')}/`;
  const safeLanding = escapeHtml(landing);
  const html = `Hi ${safeName}. You have a sub-task <b>due today</b><br><br>
<b><u><a href="${safeUrl}" style="color:#1565C0;">${safeTitle}</a></u></b><br><br>
Due Date: ${safeDue}<br><br>
<a href="${safeLanding}" style="color:#1565C0;">Project Tracker</a>`;
  const text = `Hi ${displayName}. You have a sub-task due today.

${subtaskName}
${subtaskUrl}

Due Date: ${dueYmd}

Project Tracker
${landing}`;
  return { html, text };
}

function subtaskStatusBlocksUrgentReminder(statusRaw) {
  const s = String(statusRaw || '')
    .trim()
    .toLowerCase();
  return s === 'completed' || s === 'deleted';
}

/**
 * After the due calendar date (HK), reset sub-task reminder columns.
 */
async function resetUrgentReminderForPastDueSubtasks(dbClient, todayYmd, summary) {
  const { data: rows, error } = await dbClient
    .from('subtask')
    .select(
      'id, due_date, urgent_reminder_sent, assignee_urgent_reminder_last_sent_on, creator_urgent_reminder_last_sent_on, subtask_creator_due_today_reminder_sent_on, subtask_assignee_due_today_reminder_sent_on',
    )
    .not('due_date', 'is', null);
  if (error) {
    summary.errors.push(`subtask past-due cleanup: ${error.message}`);
    return;
  }
  for (const row of rows || []) {
    if (!isCalendarPastDue(todayYmd, row.due_date)) continue;
    const sent = row.urgent_reminder_sent === true;
    const hasAssigneeLast =
      row.assignee_urgent_reminder_last_sent_on != null &&
      row.assignee_urgent_reminder_last_sent_on !== '';
    const hasLast =
      row.creator_urgent_reminder_last_sent_on != null &&
      row.creator_urgent_reminder_last_sent_on !== '';
    const hasCreatorDueToday =
      row.subtask_creator_due_today_reminder_sent_on != null &&
      row.subtask_creator_due_today_reminder_sent_on !== '';
    const hasAssigneeDueToday =
      row.subtask_assignee_due_today_reminder_sent_on != null &&
      row.subtask_assignee_due_today_reminder_sent_on !== '';
    if (!sent && !hasAssigneeLast && !hasLast && !hasCreatorDueToday && !hasAssigneeDueToday) {
      continue;
    }
    const id = String(row.id || '').trim();
    if (!id) continue;
    const { error: uErr } = await dbClient
      .from('subtask')
      .update({
        urgent_reminder_sent: false,
        assignee_urgent_reminder_last_sent_on: null,
        creator_urgent_reminder_last_sent_on: null,
        subtask_creator_due_today_reminder_sent_on: null,
        subtask_assignee_due_today_reminder_sent_on: null,
      })
      .eq('id', id);
    if (uErr) {
      summary.errors.push(`subtask past-due reset ${id}: ${uErr.message}`);
    } else {
      summary.subtasksResetPastDue += 1;
    }
  }
}

/**
 * 80% window — each assignee with assignee_01..10 set gets one Email message per HK day.
 * Uses [urgent_reminder_sent] + [assignee_urgent_reminder_last_sent_on] like task assignee urgent.
 * Runs past-due reset first. **Not** sent when HK today equals [due_date] (assignee due-today uses
 * [runAssigneeDueTodaySubtaskReminderJob] that day instead).
 */
async function runAssigneeUrgentSubtaskReminderJob() {
  const nowMs = Date.now();
  const todayYmd = hkTodayYyyyMmDd();
  const summary = {
    todayHk: todayYmd,
    scanned: 0,
    eligible: 0,
    emailsAttempted: 0,
    emailsOk: 0,
    subtasksUpdatedAfterSend: 0,
    subtasksResetPastDue: 0,
    errors: [],
  };
  if (!db) {
    summary.errors.push('Database not configured');
    return summary;
  }
  if (!EMAIL_SENDING_ENABLED) {
    return summary;
  }
  const cronEmailBlock = cronEmailBlockedReason();
  if (cronEmailBlock) {
    summary.errors.push(cronEmailBlock);
    return summary;
  }

  await resetUrgentReminderForPastDueSubtasks(db, todayYmd, summary);

  const { data: subtasks, error: qErr } = await db
    .from('subtask')
    .select('*')
    .not('start_date', 'is', null)
    .not('due_date', 'is', null);

  if (qErr) {
    summary.errors.push(qErr.message || String(qErr));
    return summary;
  }

  const list = subtasks || [];
  summary.scanned = list.length;
  const blockedParentIds = await fetchSubtaskReminderBlockedParentTaskIdSet(db);

  for (const row of list) {
    if (subtaskStatusBlocksUrgentReminder(row.status)) continue;
    if (isPausedStatus(row.pause_status)) continue;
    const taskFk = String(row.task_id || '').trim();
    if (taskFk && blockedParentIds.has(taskFk)) continue;
    if (isCalendarDueToday(todayYmd, row.due_date)) continue;
    if (!isCalendarStrictlyBeforeDue(todayYmd, row.due_date)) continue;
    if (!hasReachedEightyPercentWindow(row.start_date, row.due_date, nowMs)) {
      continue;
    }

    const lastAssignee = row.assignee_urgent_reminder_last_sent_on;
    const lastAssigneeStr =
      lastAssignee == null || lastAssignee === ''
        ? null
        : String(lastAssignee).trim().slice(0, 10);
    if (lastAssigneeStr === todayYmd) {
      continue;
    }

    const assigneeIds = collectSubtaskAssigneeStaffIds(row);
    if (assigneeIds.length === 0) {
      continue;
    }

    const subtaskId = String(row.id || '').trim();
    const subtaskName = String(row.subtask_name || '').trim() || '(no title)';
    const subtaskUrl = subtaskWebAppUrl(subtaskId);
    const dueYmd = formatTaskDueDateYYYYMMDD(row.due_date);

    summary.eligible += 1;
    const sendResults = [];
    for (const staffId of assigneeIds) {
      const { data: staffRow } = await db
        .from('staff')
        .select('id, email, name')
        .eq('id', staffId)
        .maybeSingle();
      if (!staffRow) {
        sendResults.push({ staffId, ok: false, skipped: 'staff not found' });
        continue;
      }
      const to = await resolveStaffEmailForNotifications(db, staffRow);
      if (!to) {
        sendResults.push({ staffId, ok: false, skipped: 'no email' });
        continue;
      }
      const displayName =
        (staffRow.name || '').trim() ||
        to;
      const { html, text } = buildAssigneeUrgentSubtaskReminderEmail(
        displayName,
        subtaskName,
        subtaskUrl,
        dueYmd,
      );
      const r = await sendNotificationEmail({
        to,
        subject: mailSubjectSingleLine('You have upcoming sub-tasks due'),
        text,
        html,
        from: NOTIFICATION_EMAIL_FROM,
      });
      summary.emailsAttempted += 1;
      if (r.ok) summary.emailsOk += 1;
      sendResults.push({ to, ok: r.ok, error: r.ok ? null : r.error });
    }

    const failedEmail = sendResults.some((x) => !x.ok && !x.skipped);
    if (!failedEmail) {
      const { error: uErr } = await db
        .from('subtask')
        .update({
          urgent_reminder_sent: true,
          assignee_urgent_reminder_last_sent_on: todayYmd,
        })
        .eq('id', subtaskId);
      if (uErr) {
        summary.errors.push(`assignee urgent subtask update ${subtaskId}: ${uErr.message}`);
      } else {
        summary.subtasksUpdatedAfterSend += 1;
      }
    }
  }

  return summary;
}

/**
 * Same 80% window as task creator urgent: email subtask.create_by once per HK day while
 * [isCalendarStrictlyBeforeDue] and [hasReachedEightyPercentWindow]. Uses
 * [creator_urgent_reminder_last_sent_on] only (assignee batch uses [urgent_reminder_sent]).
 * Skips if create_by === assignee_01. **Not** sent when HK today equals [due_date] — that day uses
 * [runCreatorDueTodaySubtaskReminderJob] only.
 */
async function runCreatorUrgentSubtaskReminderJob() {
  const nowMs = Date.now();
  const todayYmd = hkTodayYyyyMmDd();
  const summary = {
    todayHk: todayYmd,
    scanned: 0,
    eligible: 0,
    emailsAttempted: 0,
    emailsOk: 0,
    subtasksUpdatedAfterSend: 0,
    subtasksResetPastDue: 0,
    errors: [],
  };
  if (!db) {
    summary.errors.push('Database not configured');
    return summary;
  }
  if (!EMAIL_SENDING_ENABLED) {
    return summary;
  }
  const cronEmailBlock = cronEmailBlockedReason();
  if (cronEmailBlock) {
    summary.errors.push(cronEmailBlock);
    return summary;
  }

  const { data: subtasks, error: qErr } = await db
    .from('subtask')
    .select('*')
    .not('start_date', 'is', null)
    .not('due_date', 'is', null);

  if (qErr) {
    summary.errors.push(qErr.message || String(qErr));
    return summary;
  }

  const list = subtasks || [];
  summary.scanned = list.length;
  const blockedParentIds = await fetchSubtaskReminderBlockedParentTaskIdSet(db);

  for (const row of list) {
    if (subtaskStatusBlocksUrgentReminder(row.status)) continue;
    if (isPausedStatus(row.pause_status)) continue;
    const taskFk = String(row.task_id || '').trim();
    if (taskFk && blockedParentIds.has(taskFk)) continue;
    // HK due date = today: only runCreatorDueTodaySubtaskReminderJob (not this urgent job).
    if (isCalendarDueToday(todayYmd, row.due_date)) continue;
    if (!isCalendarStrictlyBeforeDue(todayYmd, row.due_date)) continue;
    if (!hasReachedEightyPercentWindow(row.start_date, row.due_date, nowMs)) {
      continue;
    }

    const lastCreator = row.creator_urgent_reminder_last_sent_on;
    const lastCreatorStr =
      lastCreator == null || lastCreator === ''
        ? null
        : String(lastCreator).trim().slice(0, 10);
    if (lastCreatorStr === todayYmd) {
      continue;
    }

    const subtaskId = String(row.id || '').trim();
    const creatorId = (row.create_by || '').toString().trim();
    if (!creatorId) {
      continue;
    }

    const { data: staffRow, error: staffErr } = await fetchStaffRowForCreateBy(db, creatorId);
    if (staffErr) {
      summary.errors.push(`subtask creator urgent staff lookup ${subtaskId}: ${staffErr.message}`);
      continue;
    }
    if (!staffRow) {
      summary.errors.push(
        `creator staff not found for subtask ${subtaskId} (create_by=${creatorId})`,
      );
      continue;
    }
    const resolvedCreatorStaffId = String(staffRow.id || '').trim();
    const assignee01 = (row.assignee_01 || '').toString().trim();
    if (
      assignee01 &&
      resolvedCreatorStaffId.toLowerCase() === assignee01.toLowerCase()
    ) {
      continue;
    }

    summary.eligible += 1;
    const subtaskName = String(row.subtask_name || '').trim() || '(no title)';
    const subtaskUrl = subtaskWebAppUrl(subtaskId);
    const dueYmd = formatTaskDueDateYYYYMMDD(row.due_date);
    const to = await resolveStaffEmailForNotifications(db, staffRow);
    if (!to) {
      summary.errors.push(
        `subtask creator has no email (subtask ${subtaskId}, staff.id=${resolvedCreatorStaffId})`,
      );
      continue;
    }
    const recipientDisplayName =
      (staffRow.name || '').trim() ||
      to;

    const picId = (row.pic || '').toString().trim();
    let picDisplayName = 'PIC';
    if (picId) {
      const { data: picStaff } = await db
        .from('staff')
        .select('name')
        .eq('id', picId)
        .maybeSingle();
      if (picStaff) {
        picDisplayName =
          (picStaff.name || '').trim() ||
          picDisplayName;
      }
    }

    const { html, text } = buildCreatorUrgentSubtaskReminderEmail(
      recipientDisplayName,
      picDisplayName,
      subtaskName,
      subtaskUrl,
      dueYmd,
    );
    const r = await sendNotificationEmail({
      to,
      subject: mailSubjectSingleLine(
        `${picDisplayName} has an upcoming sub-task due`,
      ),
      text,
      html,
      from: NOTIFICATION_EMAIL_FROM,
    });
    summary.emailsAttempted += 1;
    if (r.ok) summary.emailsOk += 1;
    else {
      summary.errors.push(
        `Email subtask creator urgent subtask=${subtaskId} to=${r.resolvedTo ?? to}: ${formatEmailFailure(r)}`,
      );
      continue;
    }

    const { error: uErr } = await db
      .from('subtask')
      .update({
        creator_urgent_reminder_last_sent_on: todayYmd,
      })
      .eq('id', subtaskId);
    if (uErr) {
      summary.errors.push(`subtask creator urgent update ${subtaskId}: ${uErr.message}`);
    } else {
      summary.subtasksUpdatedAfterSend += 1;
    }
  }

  return summary;
}

/**
 * Daily urgent emails (09:00 Asia/Hong_Kong + manual POST): send each HK day while
 * 80%–due window applies; [urgent_reminder_last_sent_on] prevents duplicate sends same day.
 * Does not run on the due calendar day (that day uses due-today emails only).
 * Past-due tasks: reset [urgent_reminder_sent] false and clear last_sent_on.
 */
async function runUrgentTaskReminderJob() {
  const nowMs = Date.now();
  const todayYmd = hkTodayYyyyMmDd();
  const summary = {
    todayHk: todayYmd,
    scanned: 0,
    eligible: 0,
    emailsAttempted: 0,
    emailsOk: 0,
    tasksUpdatedAfterSend: 0,
    tasksResetPastDue: 0,
    errors: [],
  };
  if (!db) {
    summary.errors.push('Database not configured');
    return summary;
  }
  if (!EMAIL_SENDING_ENABLED) {
    return summary;
  }
  const cronEmailBlock = cronEmailBlockedReason();
  if (cronEmailBlock) {
    summary.errors.push(cronEmailBlock);
    return summary;
  }

  await resetUrgentReminderForPastDueTasks(db, todayYmd, summary);

  const { data: tasks, error: qErr } = await db
    .from('task')
    .select('*')
    .not('start_date', 'is', null)
    .not('due_date', 'is', null);

  if (qErr) {
    summary.errors.push(qErr.message || String(qErr));
    return summary;
  }

  const list = tasks || [];
  summary.scanned = list.length;
  const pausedProjectIds = await fetchPausedProjectIdSet(db);

  for (const taskRow of list) {
    if (taskStatusBlocksUrgentReminder(taskRow.status)) continue;
    if (taskReminderPaused(taskRow, pausedProjectIds)) continue;
    if (!isCalendarStrictlyBeforeDue(todayYmd, taskRow.due_date)) continue;
    if (!hasReachedEightyPercentWindow(taskRow.start_date, taskRow.due_date, nowMs)) {
      continue;
    }

    const lastSent = taskRow.urgent_reminder_last_sent_on;
    const lastSentStr =
      lastSent == null || lastSent === ''
        ? null
        : String(lastSent).trim().slice(0, 10);
    if (lastSentStr === todayYmd) {
      continue;
    }

    summary.eligible += 1;
    const taskId = String(taskRow.id || '').trim();
    const taskName = String(taskRow.task_name || '').trim() || '(no title)';
    const taskUrl = `${PUBLIC_WEB_APP_URL}/?task=${encodeURIComponent(taskId)}`;
    const dueYmd = formatTaskDueDateYYYYMMDD(taskRow.due_date);
    const assigneeIds = collectTaskAssigneeStaffIds(taskRow);

    const sendResults = [];
    for (const staffId of assigneeIds) {
      const { data: staffRow } = await db
        .from('staff')
        .select('email, name')
        .eq('id', staffId)
        .maybeSingle();
      const to = (staffRow?.email || '').trim();
      if (!to) {
        sendResults.push({ staffId, ok: false, skipped: 'no email' });
        continue;
      }
      const displayName =
        (staffRow.name || '').trim() ||
        to;
      const { html, text } = buildUrgentTaskReminderEmail(
        displayName,
        taskName,
        taskUrl,
        dueYmd,
      );
      const r = await sendNotificationEmail({
        to,
        subject: 'You have upcoming tasks due',
        text,
        html,
        from: NOTIFICATION_EMAIL_FROM,
      });
      summary.emailsAttempted += 1;
      if (r.ok) summary.emailsOk += 1;
      sendResults.push({ to, ok: r.ok, error: r.ok ? null : r.error });
    }

    const failedEmail = sendResults.some((x) => !x.ok && !x.skipped);
    if (!failedEmail) {
      const { error: uErr } = await db
        .from('task')
        .update({
          urgent_reminder_sent: true,
          urgent_reminder_last_sent_on: todayYmd,
        })
        .eq('id', taskId);
      if (uErr) {
        summary.errors.push(`Update ${taskId}: ${uErr.message}`);
      } else {
        summary.tasksUpdatedAfterSend += 1;
      }
    }
  }

  return summary;
}

/**
 * Same 80% window as assignee urgent reminders: email task.create_by once per HK day while
 * [isCalendarStrictlyBeforeDue] and [hasReachedEightyPercentWindow]. Uses [creator_urgent_reminder_last_sent_on].
 * Does not run when HK today is the due date (that day uses creator due-today + [creator_due_today_reminder_sent_on]).
 * Skips if create_by === assignee_01.
 */
async function runCreatorUrgentTaskReminderJob() {
  const nowMs = Date.now();
  const todayYmd = hkTodayYyyyMmDd();
  const summary = {
    todayHk: todayYmd,
    scanned: 0,
    eligible: 0,
    emailsAttempted: 0,
    emailsOk: 0,
    tasksUpdatedAfterSend: 0,
    errors: [],
  };
  if (!db) {
    summary.errors.push('Database not configured');
    return summary;
  }
  if (!EMAIL_SENDING_ENABLED) {
    return summary;
  }
  const cronEmailBlock = cronEmailBlockedReason();
  if (cronEmailBlock) {
    summary.errors.push(cronEmailBlock);
    return summary;
  }

  const { data: tasks, error: qErr } = await db
    .from('task')
    .select('*')
    .not('start_date', 'is', null)
    .not('due_date', 'is', null);

  if (qErr) {
    summary.errors.push(qErr.message || String(qErr));
    return summary;
  }

  const list = tasks || [];
  summary.scanned = list.length;
  const pausedProjectIds = await fetchPausedProjectIdSet(db);

  for (const taskRow of list) {
    if (taskStatusBlocksUrgentReminder(taskRow.status)) continue;
    if (taskReminderPaused(taskRow, pausedProjectIds)) continue;
    // On the due calendar day (HK), do not run creator urgent — use creator due-today only.
    if (isCalendarDueToday(todayYmd, taskRow.due_date)) continue;
    if (!isCalendarStrictlyBeforeDue(todayYmd, taskRow.due_date)) continue;
    if (!hasReachedEightyPercentWindow(taskRow.start_date, taskRow.due_date, nowMs)) {
      continue;
    }

    const lastCreator = taskRow.creator_urgent_reminder_last_sent_on;
    const lastCreatorStr =
      lastCreator == null || lastCreator === ''
        ? null
        : String(lastCreator).trim().slice(0, 10);
    if (lastCreatorStr === todayYmd) {
      continue;
    }

    const taskId = String(taskRow.id || '').trim();
    const creatorId = (taskRow.create_by || '').toString().trim();
    if (!creatorId) {
      continue;
    }

    const { data: staffRow, error: staffErr } = await fetchStaffRowForCreateBy(
      db,
      creatorId,
    );
    if (staffErr) {
      summary.errors.push(`creator urgent staff lookup ${taskId}: ${staffErr.message}`);
      continue;
    }
    if (!staffRow) {
      summary.errors.push(
        `creator staff not found for task ${taskId} (create_by=${creatorId}; try staff.id or staff.app_id)`,
      );
      continue;
    }
    const resolvedCreatorStaffId = String(staffRow.id || '').trim();
    const assignee01 = (taskRow.assignee_01 || '').toString().trim();
    if (
      assignee01 &&
      resolvedCreatorStaffId.toLowerCase() === assignee01.toLowerCase()
    ) {
      continue;
    }

    summary.eligible += 1;
    const taskName = String(taskRow.task_name || '').trim() || '(no title)';
    const taskUrl = `${PUBLIC_WEB_APP_URL}/?task=${encodeURIComponent(taskId)}`;
    const dueYmd = formatTaskDueDateYYYYMMDD(taskRow.due_date);
    const to = await resolveStaffEmailForNotifications(db, staffRow);
    if (!to) {
      summary.errors.push(
        `creator has no email (task ${taskId}, staff.id=${resolvedCreatorStaffId}; set staff.email or link app_users.email)`,
      );
      continue;
    }
    const recipientDisplayName =
      (staffRow.name || '').trim() ||
      to;

    const picId = (taskRow.pic || '').toString().trim();
    let picDisplayName = 'PIC';
    if (picId) {
      const { data: picStaff } = await db
        .from('staff')
        .select('name')
        .eq('id', picId)
        .maybeSingle();
      if (picStaff) {
        picDisplayName =
          (picStaff.name || '').trim() ||
          picDisplayName;
      }
    }

    const { html, text } = buildCreatorUrgentTaskReminderEmail(
      recipientDisplayName,
      picDisplayName,
      taskName,
      taskUrl,
      dueYmd,
    );
    const r = await sendNotificationEmail({
      to,
      subject: mailSubjectSingleLine(`${picDisplayName}'s upcoming task due`),
      text,
      html,
      from: NOTIFICATION_EMAIL_FROM,
    });
    summary.emailsAttempted += 1;
    if (r.ok) summary.emailsOk += 1;
    else {
      summary.errors.push(
        `Email creator urgent task=${taskId} to=${r.resolvedTo ?? to}: ${formatEmailFailure(r)}`,
      );
      continue;
    }

    const { error: uErr } = await db
      .from('task')
      .update({ creator_urgent_reminder_last_sent_on: todayYmd })
      .eq('id', taskId);
    if (uErr) {
      summary.errors.push(`creator urgent update ${taskId}: ${uErr.message}`);
    } else {
      summary.tasksUpdatedAfterSend += 1;
    }
  }

  return summary;
}

/**
 * Due-date = today (HK calendar): one batch per task per day to assignees.
 * Runs at 09:00 Asia/Hong_Kong with urgent job; not sent on days covered by urgent-only window.
 */
async function runDueTodayTaskReminderJob() {
  const todayYmd = hkTodayYyyyMmDd();
  const summary = {
    todayHk: todayYmd,
    scanned: 0,
    eligible: 0,
    emailsAttempted: 0,
    emailsOk: 0,
    tasksUpdatedAfterSend: 0,
    errors: [],
  };
  if (!db) {
    summary.errors.push('Database not configured');
    return summary;
  }
  if (!EMAIL_SENDING_ENABLED) {
    return summary;
  }
  const cronEmailBlock = cronEmailBlockedReason();
  if (cronEmailBlock) {
    summary.errors.push(cronEmailBlock);
    return summary;
  }

  const { data: tasks, error: qErr } = await db
    .from('task')
    .select('*')
    .not('due_date', 'is', null);

  if (qErr) {
    summary.errors.push(qErr.message || String(qErr));
    return summary;
  }

  const list = tasks || [];
  summary.scanned = list.length;
  const pausedProjectIds = await fetchPausedProjectIdSet(db);

  for (const taskRow of list) {
    if (taskStatusBlocksUrgentReminder(taskRow.status)) continue;
    if (taskReminderPaused(taskRow, pausedProjectIds)) continue;
    if (!isCalendarDueToday(todayYmd, taskRow.due_date)) continue;

    const lastDue = taskRow.due_today_reminder_sent_on;
    const lastDueStr =
      lastDue == null || lastDue === ''
        ? null
        : String(lastDue).trim().slice(0, 10);
    if (lastDueStr === todayYmd) {
      continue;
    }

    summary.eligible += 1;
    const taskId = String(taskRow.id || '').trim();
    const taskName = String(taskRow.task_name || '').trim() || '(no title)';
    const taskUrl = `${PUBLIC_WEB_APP_URL}/?task=${encodeURIComponent(taskId)}`;
    const dueYmd = formatTaskDueDateYYYYMMDD(taskRow.due_date);
    const assigneeIds = collectTaskAssigneeStaffIds(taskRow);

    const sendResults = [];
    for (const staffId of assigneeIds) {
      const { data: staffRow } = await db
        .from('staff')
        .select('email, name')
        .eq('id', staffId)
        .maybeSingle();
      const to = (staffRow?.email || '').trim();
      if (!to) {
        sendResults.push({ staffId, ok: false, skipped: 'no email' });
        continue;
      }
      const displayName =
        (staffRow.name || '').trim() ||
        to;
      const { html, text } = buildDueTodayTaskReminderEmail(
        displayName,
        taskName,
        taskUrl,
        dueYmd,
      );
      const r = await sendNotificationEmail({
        to,
        subject: 'You have tasks due today',
        text,
        html,
        from: NOTIFICATION_EMAIL_FROM,
      });
      summary.emailsAttempted += 1;
      if (r.ok) summary.emailsOk += 1;
      sendResults.push({ to, ok: r.ok, error: r.ok ? null : r.error });
    }

    const failedEmail = sendResults.some((x) => !x.ok && !x.skipped);
    if (!failedEmail) {
      const { error: uErr } = await db
        .from('task')
        .update({ due_today_reminder_sent_on: todayYmd })
        .eq('id', taskId);
      if (uErr) {
        summary.errors.push(`due-today update ${taskId}: ${uErr.message}`);
      } else {
        summary.tasksUpdatedAfterSend += 1;
      }
    }
  }

  return summary;
}

/**
 * HK calendar due date = today: one batch per sub-task per day to assignee_01..10.
 * Uses [subtask_assignee_due_today_reminder_sent_on]. Skips completed/deleted.
 */
async function runAssigneeDueTodaySubtaskReminderJob() {
  const todayYmd = hkTodayYyyyMmDd();
  const summary = {
    todayHk: todayYmd,
    scanned: 0,
    eligible: 0,
    emailsAttempted: 0,
    emailsOk: 0,
    subtasksUpdatedAfterSend: 0,
    errors: [],
  };
  if (!db) {
    summary.errors.push('Database not configured');
    return summary;
  }
  if (!EMAIL_SENDING_ENABLED) {
    return summary;
  }
  const cronEmailBlock = cronEmailBlockedReason();
  if (cronEmailBlock) {
    summary.errors.push(cronEmailBlock);
    return summary;
  }

  const { data: subtasks, error: qErr } = await db
    .from('subtask')
    .select('*')
    .not('due_date', 'is', null);

  if (qErr) {
    summary.errors.push(qErr.message || String(qErr));
    return summary;
  }

  const list = subtasks || [];
  summary.scanned = list.length;
  const blockedParentIds = await fetchSubtaskReminderBlockedParentTaskIdSet(db);

  for (const row of list) {
    if (subtaskStatusBlocksUrgentReminder(row.status)) continue;
    if (isPausedStatus(row.pause_status)) continue;
    const taskFk = String(row.task_id || '').trim();
    if (taskFk && blockedParentIds.has(taskFk)) continue;
    if (!isCalendarDueToday(todayYmd, row.due_date)) continue;

    const lastDue = row.subtask_assignee_due_today_reminder_sent_on;
    const lastDueStr =
      lastDue == null || lastDue === ''
        ? null
        : String(lastDue).trim().slice(0, 10);
    if (lastDueStr === todayYmd) {
      continue;
    }

    const assigneeIds = collectSubtaskAssigneeStaffIds(row);
    if (assigneeIds.length === 0) {
      continue;
    }

    const subtaskId = String(row.id || '').trim();
    const subtaskName = String(row.subtask_name || '').trim() || '(no title)';
    const subtaskUrl = subtaskWebAppUrl(subtaskId);
    const dueYmd = formatTaskDueDateYYYYMMDD(row.due_date);

    summary.eligible += 1;
    const sendResults = [];
    for (const staffId of assigneeIds) {
      const { data: staffRow } = await db
        .from('staff')
        .select('id, email, name')
        .eq('id', staffId)
        .maybeSingle();
      if (!staffRow) {
        sendResults.push({ staffId, ok: false, skipped: 'staff not found' });
        continue;
      }
      const to = await resolveStaffEmailForNotifications(db, staffRow);
      if (!to) {
        sendResults.push({ staffId, ok: false, skipped: 'no email' });
        continue;
      }
      const displayName =
        (staffRow.name || '').trim() ||
        to;
      const { html, text } = buildAssigneeDueTodaySubtaskReminderEmail(
        displayName,
        subtaskName,
        subtaskUrl,
        dueYmd,
      );
      const r = await sendNotificationEmail({
        to,
        subject: mailSubjectSingleLine('You have sub-tasks due today'),
        text,
        html,
        from: NOTIFICATION_EMAIL_FROM,
      });
      summary.emailsAttempted += 1;
      if (r.ok) summary.emailsOk += 1;
      sendResults.push({ to, ok: r.ok, error: r.ok ? null : r.error });
    }

    const failedEmail = sendResults.some((x) => !x.ok && !x.skipped);
    if (!failedEmail) {
      const { error: uErr } = await db
        .from('subtask')
        .update({ subtask_assignee_due_today_reminder_sent_on: todayYmd })
        .eq('id', subtaskId);
      if (uErr) {
        summary.errors.push(`subtask assignee due-today update ${subtaskId}: ${uErr.message}`);
      } else {
        summary.subtasksUpdatedAfterSend += 1;
      }
    }
  }

  return summary;
}

/**
 * HK calendar due date = today: one email per task to task.create_by (staff).
 * Independent of assignee [due_today_reminder_sent_on]; uses [creator_due_today_reminder_sent_on].
 * Skips when status is completed/deleted (same as other due-today jobs).
 * Skips when create_by is the same as assignee_01 (creator is primary assignee — assignee due-today email suffices).
 */
async function runCreatorDueTodayReminderJob() {
  const todayYmd = hkTodayYyyyMmDd();
  const summary = {
    todayHk: todayYmd,
    scanned: 0,
    eligible: 0,
    emailsAttempted: 0,
    emailsOk: 0,
    tasksUpdatedAfterSend: 0,
    errors: [],
  };
  if (!db) {
    summary.errors.push('Database not configured');
    return summary;
  }
  if (!EMAIL_SENDING_ENABLED) {
    return summary;
  }
  const cronEmailBlock = cronEmailBlockedReason();
  if (cronEmailBlock) {
    summary.errors.push(cronEmailBlock);
    return summary;
  }

  const { data: tasks, error: qErr } = await db
    .from('task')
    .select('*')
    .not('due_date', 'is', null);

  if (qErr) {
    summary.errors.push(qErr.message || String(qErr));
    return summary;
  }

  const list = tasks || [];
  summary.scanned = list.length;
  const pausedProjectIds = await fetchPausedProjectIdSet(db);

  for (const taskRow of list) {
    if (taskStatusBlocksUrgentReminder(taskRow.status)) continue;
    if (taskReminderPaused(taskRow, pausedProjectIds)) continue;
    if (!isCalendarDueToday(todayYmd, taskRow.due_date)) continue;

    const lastCreator = taskRow.creator_due_today_reminder_sent_on;
    const lastCreatorStr =
      lastCreator == null || lastCreator === ''
        ? null
        : String(lastCreator).trim().slice(0, 10);
    if (lastCreatorStr === todayYmd) {
      continue;
    }

    const taskId = String(taskRow.id || '').trim();
    const creatorId = (taskRow.create_by || '').toString().trim();
    if (!creatorId) {
      continue;
    }

    const { data: staffRow, error: staffErr } = await fetchStaffRowForCreateBy(
      db,
      creatorId,
    );
    if (staffErr) {
      summary.errors.push(`creator due-today staff lookup ${taskId}: ${staffErr.message}`);
      continue;
    }
    if (!staffRow) {
      summary.errors.push(
        `creator staff not found for task ${taskId} (create_by=${creatorId}; try staff.id or staff.app_id)`,
      );
      continue;
    }
    const resolvedCreatorStaffId = String(staffRow.id || '').trim();
    const assignee01 = (taskRow.assignee_01 || '').toString().trim();
    if (
      assignee01 &&
      resolvedCreatorStaffId.toLowerCase() === assignee01.toLowerCase()
    ) {
      continue;
    }

    summary.eligible += 1;
    const taskName = String(taskRow.task_name || '').trim() || '(no title)';
    const taskUrl = `${PUBLIC_WEB_APP_URL}/?task=${encodeURIComponent(taskId)}`;
    const dueYmd = formatTaskDueDateYYYYMMDD(taskRow.due_date);
    const to = await resolveStaffEmailForNotifications(db, staffRow);
    if (!to) {
      summary.errors.push(
        `creator has no email (task ${taskId}, staff.id=${resolvedCreatorStaffId}; set staff.email or link app_users.email)`,
      );
      continue;
    }
    const recipientDisplayName =
      (staffRow.name || '').trim() ||
      to;

    const picId = (taskRow.pic || '').toString().trim();
    let picDisplayName = 'PIC';
    if (picId) {
      const { data: picStaff } = await db
        .from('staff')
        .select('name')
        .eq('id', picId)
        .maybeSingle();
      if (picStaff) {
        picDisplayName =
          (picStaff.name || '').trim() ||
          picDisplayName;
      }
    }

    const { html, text } = buildCreatorDueTodayTaskReminderEmail(
      recipientDisplayName,
      picDisplayName,
      taskName,
      taskUrl,
      dueYmd,
    );
    const r = await sendNotificationEmail({
      to,
      subject: mailSubjectSingleLine(`${picDisplayName}'s task due today`),
      text,
      html,
      from: NOTIFICATION_EMAIL_FROM,
    });
    summary.emailsAttempted += 1;
    if (r.ok) summary.emailsOk += 1;
    else {
      summary.errors.push(
        `Email creator due-today task=${taskId} to=${r.resolvedTo ?? to}: ${formatEmailFailure(r)}`,
      );
      continue;
    }

    const { error: uErr } = await db
      .from('task')
      .update({ creator_due_today_reminder_sent_on: todayYmd })
      .eq('id', taskId);
    if (uErr) {
      summary.errors.push(`creator due-today update ${taskId}: ${uErr.message}`);
    } else {
      summary.tasksUpdatedAfterSend += 1;
    }
  }

  return summary;
}

/**
 * HK calendar due date = today: one email per sub-task to subtask.create_by.
 * Uses [subtask_creator_due_today_reminder_sent_on]. Skips completed/deleted.
 * Skips when create_by is the same as assignee_01.
 */
async function runCreatorDueTodaySubtaskReminderJob() {
  const todayYmd = hkTodayYyyyMmDd();
  const summary = {
    todayHk: todayYmd,
    scanned: 0,
    eligible: 0,
    emailsAttempted: 0,
    emailsOk: 0,
    subtasksUpdatedAfterSend: 0,
    errors: [],
  };
  if (!db) {
    summary.errors.push('Database not configured');
    return summary;
  }
  if (!EMAIL_SENDING_ENABLED) {
    return summary;
  }
  const cronEmailBlock = cronEmailBlockedReason();
  if (cronEmailBlock) {
    summary.errors.push(cronEmailBlock);
    return summary;
  }

  const { data: subtasks, error: qErr } = await db
    .from('subtask')
    .select('*')
    .not('due_date', 'is', null);

  if (qErr) {
    summary.errors.push(qErr.message || String(qErr));
    return summary;
  }

  const list = subtasks || [];
  summary.scanned = list.length;
  const blockedParentIds = await fetchSubtaskReminderBlockedParentTaskIdSet(db);

  for (const row of list) {
    if (subtaskStatusBlocksUrgentReminder(row.status)) continue;
    if (isPausedStatus(row.pause_status)) continue;
    const taskFk = String(row.task_id || '').trim();
    if (taskFk && blockedParentIds.has(taskFk)) continue;
    if (!isCalendarDueToday(todayYmd, row.due_date)) continue;

    const lastCreator = row.subtask_creator_due_today_reminder_sent_on;
    const lastCreatorStr =
      lastCreator == null || lastCreator === ''
        ? null
        : String(lastCreator).trim().slice(0, 10);
    if (lastCreatorStr === todayYmd) {
      continue;
    }

    const subtaskId = String(row.id || '').trim();
    const creatorId = (row.create_by || '').toString().trim();
    if (!creatorId) {
      continue;
    }

    const { data: staffRow, error: staffErr } = await fetchStaffRowForCreateBy(db, creatorId);
    if (staffErr) {
      summary.errors.push(`subtask creator due-today staff lookup ${subtaskId}: ${staffErr.message}`);
      continue;
    }
    if (!staffRow) {
      summary.errors.push(
        `creator staff not found for subtask ${subtaskId} (create_by=${creatorId})`,
      );
      continue;
    }
    const resolvedCreatorStaffId = String(staffRow.id || '').trim();
    const assignee01 = (row.assignee_01 || '').toString().trim();
    if (
      assignee01 &&
      resolvedCreatorStaffId.toLowerCase() === assignee01.toLowerCase()
    ) {
      continue;
    }

    summary.eligible += 1;
    const subtaskName = String(row.subtask_name || '').trim() || '(no title)';
    const subtaskUrl = subtaskWebAppUrl(subtaskId);
    const dueYmd = formatTaskDueDateYYYYMMDD(row.due_date);
    const to = await resolveStaffEmailForNotifications(db, staffRow);
    if (!to) {
      summary.errors.push(
        `subtask creator has no email (subtask ${subtaskId}, staff.id=${resolvedCreatorStaffId})`,
      );
      continue;
    }
    const recipientDisplayName =
      (staffRow.name || '').trim() ||
      to;

    const picId = (row.pic || '').toString().trim();
    let picDisplayName = 'PIC';
    if (picId) {
      const { data: picStaff } = await db
        .from('staff')
        .select('name')
        .eq('id', picId)
        .maybeSingle();
      if (picStaff) {
        picDisplayName =
          (picStaff.name || '').trim() ||
          picDisplayName;
      }
    }

    const { html, text } = buildCreatorDueTodaySubtaskReminderEmail(
      recipientDisplayName,
      picDisplayName,
      subtaskName,
      subtaskUrl,
      dueYmd,
    );
    const r = await sendNotificationEmail({
      to,
      subject: mailSubjectSingleLine(
        `${picDisplayName}'s sub-task due today`,
      ),
      text,
      html,
      from: NOTIFICATION_EMAIL_FROM,
    });
    summary.emailsAttempted += 1;
    if (r.ok) summary.emailsOk += 1;
    else {
      summary.errors.push(
        `Email subtask creator due-today subtask=${subtaskId} to=${r.resolvedTo ?? to}: ${formatEmailFailure(r)}`,
      );
      continue;
    }

    const { error: uErr } = await db
      .from('subtask')
      .update({ subtask_creator_due_today_reminder_sent_on: todayYmd })
      .eq('id', subtaskId);
    if (uErr) {
      summary.errors.push(`subtask creator due-today update ${subtaskId}: ${uErr.message}`);
    } else {
      summary.subtasksUpdatedAfterSend += 1;
    }
  }

  return summary;
}

/**
 * HK calendar: today > due_date. CreatorOverdueReminder → task.create_by (not when create_by = assignee_01).
 */
async function runCreatorOverdueTaskReminderJob() {
  const todayYmd = hkTodayYyyyMmDd();
  const summary = {
    todayHk: todayYmd,
    scanned: 0,
    eligible: 0,
    emailsAttempted: 0,
    emailsOk: 0,
    tasksUpdatedAfterSend: 0,
    errors: [],
  };
  if (!db) {
    summary.errors.push('Database not configured');
    return summary;
  }
  if (!EMAIL_SENDING_ENABLED) {
    return summary;
  }
  const cronEmailBlock = cronEmailBlockedReason();
  if (cronEmailBlock) {
    summary.errors.push(cronEmailBlock);
    return summary;
  }

  const { data: tasks, error: qErr } = await db
    .from('task')
    .select('*')
    .not('due_date', 'is', null);

  if (qErr) {
    summary.errors.push(qErr.message || String(qErr));
    return summary;
  }

  const list = tasks || [];
  summary.scanned = list.length;
  const pausedProjectIds = await fetchPausedProjectIdSet(db);

  for (const taskRow of list) {
    if (taskStatusBlocksUrgentReminder(taskRow.status)) continue;
    if (taskReminderPaused(taskRow, pausedProjectIds)) continue;
    if (!isCalendarPastDue(todayYmd, taskRow.due_date)) continue;

    const lastCreator = taskRow.creator_overdue_reminder_last_sent_on;
    const lastCreatorStr =
      lastCreator == null || lastCreator === ''
        ? null
        : String(lastCreator).trim().slice(0, 10);
    if (lastCreatorStr === todayYmd) {
      continue;
    }

    const taskId = String(taskRow.id || '').trim();
    const creatorId = (taskRow.create_by || '').toString().trim();
    if (!creatorId) {
      continue;
    }

    const { data: staffRow, error: staffErr } = await fetchStaffRowForCreateBy(
      db,
      creatorId,
    );
    if (staffErr) {
      summary.errors.push(`creator overdue staff lookup ${taskId}: ${staffErr.message}`);
      continue;
    }
    if (!staffRow) {
      summary.errors.push(
        `creator staff not found for task ${taskId} (create_by=${creatorId}; try staff.id or staff.app_id)`,
      );
      continue;
    }
    const resolvedCreatorStaffId = String(staffRow.id || '').trim();
    const assignee01 = (taskRow.assignee_01 || '').toString().trim();
    if (
      assignee01 &&
      resolvedCreatorStaffId.toLowerCase() === assignee01.toLowerCase()
    ) {
      continue;
    }

    summary.eligible += 1;
    const taskName = String(taskRow.task_name || '').trim() || '(no title)';
    const taskUrl = `${PUBLIC_WEB_APP_URL}/?task=${encodeURIComponent(taskId)}`;
    const dueYmd = formatTaskDueDateYYYYMMDD(taskRow.due_date);
    const to = await resolveStaffEmailForNotifications(db, staffRow);
    if (!to) {
      summary.errors.push(
        `creator has no email (task ${taskId}, staff.id=${resolvedCreatorStaffId}; set staff.email or link app_users.email)`,
      );
      continue;
    }
    const recipientDisplayName =
      (staffRow.name || '').trim() ||
      to;

    const picId = (taskRow.pic || '').toString().trim();
    let picDisplayName = 'PIC';
    if (picId) {
      const { data: picStaff } = await db
        .from('staff')
        .select('name')
        .eq('id', picId)
        .maybeSingle();
      if (picStaff) {
        picDisplayName =
          (picStaff.name || '').trim() ||
          picDisplayName;
      }
    }

    const { html, text } = buildCreatorOverdueTaskReminderEmail(
      recipientDisplayName,
      picDisplayName,
      taskName,
      taskUrl,
      dueYmd,
    );
    const r = await sendNotificationEmail({
      to,
      subject: mailSubjectSingleLine(`${picDisplayName}'s task overdue`),
      text,
      html,
      from: NOTIFICATION_EMAIL_FROM,
    });
    summary.emailsAttempted += 1;
    if (r.ok) summary.emailsOk += 1;
    else {
      summary.errors.push(
        `Email creator overdue task=${taskId} to=${r.resolvedTo ?? to}: ${formatEmailFailure(r)}`,
      );
      continue;
    }

    const { error: uErr } = await db
      .from('task')
      .update({ creator_overdue_reminder_last_sent_on: todayYmd })
      .eq('id', taskId);
    if (uErr) {
      summary.errors.push(`creator overdue update ${taskId}: ${uErr.message}`);
    } else {
      summary.tasksUpdatedAfterSend += 1;
    }
  }

  return summary;
}

/**
 * HK calendar: today > due_date. AssigneeOverdueReminder → each non-empty assignee_01..10 (per slot / day).
 * Runs daily at 09:00 Asia/Hong_Kong (internal cron). Pending or Returned → send; Submitted → do not send.
 */
async function runAssigneeOverdueTaskReminderJob() {
  const todayYmd = hkTodayYyyyMmDd();
  const summary = {
    todayHk: todayYmd,
    scanned: 0,
    eligible: 0,
    emailsAttempted: 0,
    emailsOk: 0,
    tasksUpdatedAfterSend: 0,
    errors: [],
  };
  if (!db) {
    summary.errors.push('Database not configured');
    return summary;
  }
  if (!EMAIL_SENDING_ENABLED) {
    return summary;
  }
  const cronEmailBlock = cronEmailBlockedReason();
  if (cronEmailBlock) {
    summary.errors.push(cronEmailBlock);
    return summary;
  }

  const { data: tasks, error: qErr } = await db
    .from('task')
    .select('*')
    .not('due_date', 'is', null);

  if (qErr) {
    summary.errors.push(qErr.message || String(qErr));
    return summary;
  }

  const list = tasks || [];
  summary.scanned = list.length;
  const pausedProjectIds = await fetchPausedProjectIdSet(db);

  for (const taskRow of list) {
    if (taskStatusBlocksUrgentReminder(taskRow.status)) continue;
    if (taskReminderPaused(taskRow, pausedProjectIds)) continue;
    if (!isCalendarPastDue(todayYmd, taskRow.due_date)) continue;
    if (!submissionAllowsAssigneeOverdueReminder(taskRow.submission)) continue;

    const taskId = String(taskRow.id || '').trim();
    const taskName = String(taskRow.task_name || '').trim() || '(no title)';
    const taskUrl = `${PUBLIC_WEB_APP_URL}/?task=${encodeURIComponent(taskId)}`;
    const dueYmd = formatTaskDueDateYYYYMMDD(taskRow.due_date);

    let anySlotThisTask = false;
    for (let slot = 1; slot <= 10; slot++) {
      const assigneeKey = `assignee_${String(slot).padStart(2, '0')}`;
      const sentCol = `${assigneeKey}_overdue_reminder_last_sent_on`;
      const staffId = (taskRow[assigneeKey] || '').toString().trim();
      if (!staffId) continue;

      const lastSent = taskRow[sentCol];
      const lastStr =
        lastSent == null || lastSent === ''
          ? null
          : String(lastSent).trim().slice(0, 10);
      if (lastStr === todayYmd) continue;

      if (!anySlotThisTask) {
        summary.eligible += 1;
        anySlotThisTask = true;
      }

      const { data: staffRow } = await db
        .from('staff')
        .select('id, email, name')
        .eq('id', staffId)
        .maybeSingle();
      if (!staffRow) {
        summary.errors.push(`assignee overdue staff not found (task ${taskId}, ${assigneeKey})`);
        continue;
      }
      const to = await resolveStaffEmailForNotifications(db, staffRow);
      if (!to) {
        summary.errors.push(
          `assignee has no email (task ${taskId}, ${assigneeKey}, staff.id=${staffId})`,
        );
        continue;
      }
      const displayName =
        (staffRow.name || '').trim() ||
        to;

      const { html, text } = buildAssigneeOverdueTaskReminderEmail(
        displayName,
        taskName,
        taskUrl,
        dueYmd,
      );
      const r = await sendNotificationEmail({
        to,
        subject: mailSubjectSingleLine('You have tasks overdue'),
        text,
        html,
        from: NOTIFICATION_EMAIL_FROM,
      });
      summary.emailsAttempted += 1;
      if (r.ok) summary.emailsOk += 1;
      else {
        summary.errors.push(
          `Email assignee overdue task=${taskId} slot=${assigneeKey} to=${r.resolvedTo ?? to}: ${formatEmailFailure(r)}`,
        );
        continue;
      }

      const { error: uErr } = await db
        .from('task')
        .update({ [sentCol]: todayYmd })
        .eq('id', taskId);
      if (uErr) {
        summary.errors.push(`assignee overdue update ${taskId} ${sentCol}: ${uErr.message}`);
      } else {
        summary.tasksUpdatedAfterSend += 1;
      }
    }
  }

  return summary;
}

/**
 * HK calendar: today > subtask.due_date. Subtask_CreatorOverdueReminder → subtask.create_by (skip if = assignee_01).
 */
async function runCreatorOverdueSubtaskReminderJob() {
  const todayYmd = hkTodayYyyyMmDd();
  const summary = {
    todayHk: todayYmd,
    scanned: 0,
    eligible: 0,
    emailsAttempted: 0,
    emailsOk: 0,
    subtasksUpdatedAfterSend: 0,
    errors: [],
  };
  if (!db) {
    summary.errors.push('Database not configured');
    return summary;
  }
  if (!EMAIL_SENDING_ENABLED) {
    return summary;
  }
  const cronEmailBlock = cronEmailBlockedReason();
  if (cronEmailBlock) {
    summary.errors.push(cronEmailBlock);
    return summary;
  }

  const { data: subtasks, error: qErr } = await db
    .from('subtask')
    .select('*')
    .not('due_date', 'is', null);

  if (qErr) {
    summary.errors.push(qErr.message || String(qErr));
    return summary;
  }

  const list = subtasks || [];
  summary.scanned = list.length;
  const blockedParentIds = await fetchSubtaskReminderBlockedParentTaskIdSet(db);

  for (const row of list) {
    if (subtaskStatusBlocksUrgentReminder(row.status)) continue;
    if (isPausedStatus(row.pause_status)) continue;
    const taskFk = String(row.task_id || '').trim();
    if (taskFk && blockedParentIds.has(taskFk)) continue;
    if (!isCalendarPastDue(todayYmd, row.due_date)) continue;

    const lastCreator = row.subtask_creator_overdue_reminder_last_sent_on;
    const lastCreatorStr =
      lastCreator == null || lastCreator === ''
        ? null
        : String(lastCreator).trim().slice(0, 10);
    if (lastCreatorStr === todayYmd) {
      continue;
    }

    const subtaskId = String(row.id || '').trim();
    const creatorId = (row.create_by || '').toString().trim();
    if (!creatorId) {
      continue;
    }

    const { data: staffRow, error: staffErr } = await fetchStaffRowForCreateBy(db, creatorId);
    if (staffErr) {
      summary.errors.push(`subtask creator overdue staff lookup ${subtaskId}: ${staffErr.message}`);
      continue;
    }
    if (!staffRow) {
      summary.errors.push(
        `creator staff not found for subtask ${subtaskId} (create_by=${creatorId})`,
      );
      continue;
    }
    const resolvedCreatorStaffId = String(staffRow.id || '').trim();
    const assignee01 = (row.assignee_01 || '').toString().trim();
    if (
      assignee01 &&
      resolvedCreatorStaffId.toLowerCase() === assignee01.toLowerCase()
    ) {
      continue;
    }

    summary.eligible += 1;
    const subtaskName = String(row.subtask_name || '').trim() || '(no title)';
    const subtaskUrl = subtaskWebAppUrl(subtaskId);
    const dueYmd = formatTaskDueDateYYYYMMDD(row.due_date);
    const to = await resolveStaffEmailForNotifications(db, staffRow);
    if (!to) {
      summary.errors.push(
        `subtask creator has no email (subtask ${subtaskId}, staff.id=${resolvedCreatorStaffId})`,
      );
      continue;
    }
    const recipientDisplayName =
      (staffRow.name || '').trim() ||
      to;

    const picId = (row.pic || '').toString().trim();
    let picDisplayName = 'PIC';
    if (picId) {
      const { data: picStaff } = await db
        .from('staff')
        .select('name')
        .eq('id', picId)
        .maybeSingle();
      if (picStaff) {
        picDisplayName =
          (picStaff.name || '').trim() ||
          picDisplayName;
      }
    }

    const { html, text } = buildCreatorOverdueSubtaskReminderEmail(
      recipientDisplayName,
      picDisplayName,
      subtaskName,
      subtaskUrl,
      dueYmd,
    );
    const r = await sendNotificationEmail({
      to,
      subject: mailSubjectSingleLine(
        `${picDisplayName}'s sub-task overdue`,
      ),
      text,
      html,
      from: NOTIFICATION_EMAIL_FROM,
    });
    summary.emailsAttempted += 1;
    if (r.ok) summary.emailsOk += 1;
    else {
      summary.errors.push(
        `Email subtask creator overdue subtask=${subtaskId} to=${r.resolvedTo ?? to}: ${formatEmailFailure(r)}`,
      );
      continue;
    }

    const { error: uErr } = await db
      .from('subtask')
      .update({ subtask_creator_overdue_reminder_last_sent_on: todayYmd })
      .eq('id', subtaskId);
    if (uErr) {
      summary.errors.push(`subtask creator overdue update ${subtaskId}: ${uErr.message}`);
    } else {
      summary.subtasksUpdatedAfterSend += 1;
    }
  }

  return summary;
}

/**
 * HK calendar: today > subtask.due_date. Subtask_AssigneeOverdueReminder → each assignee slot (per slot / day).
 * Runs daily at 09:00 Asia/Hong_Kong (internal cron). Pending or Returned → send; Submitted → do not send.
 */
async function runAssigneeOverdueSubtaskReminderJob() {
  const todayYmd = hkTodayYyyyMmDd();
  const summary = {
    todayHk: todayYmd,
    scanned: 0,
    eligible: 0,
    emailsAttempted: 0,
    emailsOk: 0,
    subtasksUpdatedAfterSend: 0,
    errors: [],
  };
  if (!db) {
    summary.errors.push('Database not configured');
    return summary;
  }
  if (!EMAIL_SENDING_ENABLED) {
    return summary;
  }
  const cronEmailBlock = cronEmailBlockedReason();
  if (cronEmailBlock) {
    summary.errors.push(cronEmailBlock);
    return summary;
  }

  const { data: subtasks, error: qErr } = await db
    .from('subtask')
    .select('*')
    .not('due_date', 'is', null);

  if (qErr) {
    summary.errors.push(qErr.message || String(qErr));
    return summary;
  }

  const list = subtasks || [];
  summary.scanned = list.length;
  const blockedParentIds = await fetchSubtaskReminderBlockedParentTaskIdSet(db);

  for (const row of list) {
    if (subtaskStatusBlocksUrgentReminder(row.status)) continue;
    if (isPausedStatus(row.pause_status)) continue;
    const taskFk = String(row.task_id || '').trim();
    if (taskFk && blockedParentIds.has(taskFk)) continue;
    if (!isCalendarPastDue(todayYmd, row.due_date)) continue;
    if (!submissionAllowsAssigneeOverdueReminder(row.submission)) continue;

    const subtaskId = String(row.id || '').trim();
    const subtaskName = String(row.subtask_name || '').trim() || '(no title)';
    const subtaskUrl = subtaskWebAppUrl(subtaskId);
    const dueYmd = formatTaskDueDateYYYYMMDD(row.due_date);

    let anySlotThisRow = false;
    for (let slot = 1; slot <= 10; slot++) {
      const assigneeKey = `assignee_${String(slot).padStart(2, '0')}`;
      const sentCol = `${assigneeKey}_overdue_reminder_last_sent_on`;
      const staffId = (row[assigneeKey] || '').toString().trim();
      if (!staffId) continue;

      const lastSent = row[sentCol];
      const lastStr =
        lastSent == null || lastSent === ''
          ? null
          : String(lastSent).trim().slice(0, 10);
      if (lastStr === todayYmd) continue;

      if (!anySlotThisRow) {
        summary.eligible += 1;
        anySlotThisRow = true;
      }

      const { data: staffRow } = await db
        .from('staff')
        .select('id, email, name')
        .eq('id', staffId)
        .maybeSingle();
      if (!staffRow) {
        summary.errors.push(`subtask assignee overdue staff not found (subtask ${subtaskId}, ${assigneeKey})`);
        continue;
      }
      const to = await resolveStaffEmailForNotifications(db, staffRow);
      if (!to) {
        summary.errors.push(
          `subtask assignee has no email (subtask ${subtaskId}, ${assigneeKey}, staff.id=${staffId})`,
        );
        continue;
      }
      const displayName =
        (staffRow.name || '').trim() ||
        to;

      const { html, text } = buildAssigneeOverdueSubtaskReminderEmail(
        displayName,
        subtaskName,
        subtaskUrl,
        dueYmd,
      );
      const r = await sendNotificationEmail({
        to,
        subject: mailSubjectSingleLine('You have sub-tasks overdue'),
        text,
        html,
        from: NOTIFICATION_EMAIL_FROM,
      });
      summary.emailsAttempted += 1;
      if (r.ok) summary.emailsOk += 1;
      else {
        summary.errors.push(
          `Email subtask assignee overdue subtask=${subtaskId} slot=${assigneeKey} to=${r.resolvedTo ?? to}: ${formatEmailFailure(r)}`,
        );
        continue;
      }

      const { error: uErr } = await db
        .from('subtask')
        .update({ [sentCol]: todayYmd })
        .eq('id', subtaskId);
      if (uErr) {
        summary.errors.push(`subtask assignee overdue update ${subtaskId} ${sentCol}: ${uErr.message}`);
      } else {
        summary.subtasksUpdatedAfterSend += 1;
      }
    }
  }

  return summary;
}

function picReminderDirectTaskUrl(taskId) {
  const id = String(taskId || '').trim();
  const base = String(PUBLIC_WEB_APP_URL || '').trim().replace(/\/$/, '');
  return `${base}/?task=${encodeURIComponent(id)}`;
}

function picReminderDirectSubtaskUrl(subtaskId) {
  const id = String(subtaskId || '').trim();
  const base = String(PUBLIC_WEB_APP_URL || '').trim().replace(/\/$/, '');
  return `${base}/?subtask=${encodeURIComponent(id)}`;
}

function reminderTextValue(raw) {
  const s = String(raw || '').trim();
  return s || '—';
}

function reminderDescription(raw) {
  const s = String(raw || '').trim();
  if (!s) return '—';
  return s.length > 1800 ? `${s.slice(0, 1800)}...` : s;
}

function staffActiveForReminder(staffRow) {
  return staffRow?.active !== false;
}

function submissionBlocksOverdueSummaryReminder(submissionRaw) {
  return String(submissionRaw || '').trim().toLowerCase() === 'submitted';
}

function overdueDaysText(todayYmd, dueYmd) {
  const todayMs = new Date(`${todayYmd}T00:00:00Z`).getTime();
  const dueMs = new Date(`${dueYmd}T00:00:00Z`).getTime();
  if (Number.isNaN(todayMs) || Number.isNaN(dueMs) || todayMs <= dueMs) {
    return '';
  }
  const days = Math.round((todayMs - dueMs) / 86400000);
  return ` (Overdue by ${days} ${days === 1 ? 'day' : 'days'})`;
}

function buildPicOverdueSummaryEmail(displayName, items) {
  const greetingName = reminderTextValue(displayName);
  const subject = 'Project Tracker overdue PIC reminder';
  const taskCount = items.filter((item) => item.kind === 'Task').length;
  const subtaskCount = items.filter((item) => item.kind === 'Subtask').length;
  const introText = `You have ${taskCount} overdue ${taskCount === 1 ? 'Task' : 'Tasks'} and ${subtaskCount} overdue ${subtaskCount === 1 ? 'Subtask' : 'Subtasks'} where you are PIC. Please review the details below:`;
  const textLines = [
    `Dear ${greetingName},`,
    '',
    introText,
    '',
  ];

  const htmlItems = [];
  items.forEach((item) => {
    const titleColor = item.kind === 'Task' ? '#2563eb' : '#16a34a';
    const overdueText = item.overdueText || '';
    textLines.push(item.title);
    textLines.push(item.description);
    textLines.push(`Creator: ${item.creatorName}`);
    textLines.push(`Due date: ${item.dueYmd}${overdueText}`);
    textLines.push(`URL: ${item.url}`);
    textLines.push('');

    htmlItems.push(`
      <div style="margin:0 0 20px 0;">
        <div style="font-size:16px;font-weight:700;color:${titleColor};">${escapeHtml(item.title)}</div>
        <div style="white-space:pre-line;">${escapeHtml(item.description)}</div>
        <div>Creator: ${escapeHtml(item.creatorName)}</div>
        <div>Due date: ${escapeHtml(`${item.dueYmd}${overdueText}`)}</div>
        <div>URL: <a href="${escapeHtml(item.url)}">${escapeHtml(item.url)}</a></div>
      </div>`);
  });

  textLines.push('Please review and update the above overdue item(s) in Project Tracker.');
  textLines.push('');
  textLines.push('Best regards,');
  textLines.push('AI & Data Lab');
  textLines.push('Institutional Advancement');
  textLines.push('The University of Hong Kong');

  const html = `
  <div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;line-height:1.5;color:#111827;">
    <p>Dear ${escapeHtml(greetingName)},</p>
    <p>You have <strong style="color:#2563eb;">${taskCount} overdue ${taskCount === 1 ? 'Task' : 'Tasks'}</strong> and <strong style="color:#16a34a;">${subtaskCount} overdue ${subtaskCount === 1 ? 'Subtask' : 'Subtasks'}</strong> where you are PIC. Please review the details below:</p>
    ${htmlItems.join('\n')}
    <p>Please review and update the above overdue item(s) in Project Tracker.</p>
    <p>
      Best regards,<br>
      AI &amp; Data Lab<br>
      Institutional Advancement<br>
      The University of Hong Kong
    </p>
  </div>`;

  return { subject, text: textLines.join('\n'), html };
}

function buildCreatorOverdueSummaryEmail(displayName, items) {
  const greetingName = reminderTextValue(displayName);
  const subject = 'Project Tracker overdue items created by you';
  const taskCount = items.filter((item) => item.kind === 'Task').length;
  const subtaskCount = items.filter((item) => item.kind === 'Subtask').length;
  const introText = `You have created ${taskCount} overdue ${taskCount === 1 ? 'Task' : 'Tasks'} and ${subtaskCount} overdue ${subtaskCount === 1 ? 'Subtask' : 'Subtasks'} that are still pending delivery. Please review the details below and follow up with the PIC where appropriate.`;
  const textLines = [`Dear ${greetingName},`, '', introText, ''];

  const htmlItems = [];
  items.forEach((item) => {
    const titleColor = item.kind === 'Task' ? '#2563eb' : '#16a34a';
    const overdueText = item.overdueText || '';
    textLines.push(item.title);
    textLines.push(item.description);
    textLines.push(`PIC: ${item.picName}`);
    textLines.push(`Due date: ${item.dueYmd}${overdueText}`);
    textLines.push(`URL: ${item.url}`);
    textLines.push('');

    htmlItems.push(`
      <div style="margin:0 0 20px 0;">
        <div style="font-size:16px;font-weight:700;color:${titleColor};">${escapeHtml(item.title)}</div>
        <div style="white-space:pre-line;">${escapeHtml(item.description)}</div>
        <div>PIC: ${escapeHtml(item.picName)}</div>
        <div>Due date: ${escapeHtml(`${item.dueYmd}${overdueText}`)}</div>
        <div>URL: <a href="${escapeHtml(item.url)}">${escapeHtml(item.url)}</a></div>
      </div>`);
  });

  const actionText =
    'Please follow up with the PIC to support delivery. If the original requirement or timeline is no longer suitable, please discuss with the PIC and update the task/subtask requirement or delivery date in Project Tracker.';
  textLines.push(actionText);
  textLines.push('');
  textLines.push('Best regards,');
  textLines.push('AI & Data Lab');
  textLines.push('Institutional Advancement');
  textLines.push('The University of Hong Kong');

  const html = `
  <div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;line-height:1.5;color:#111827;">
    <p>Dear ${escapeHtml(greetingName)},</p>
    <p>You have created <strong style="color:#2563eb;">${taskCount} overdue ${taskCount === 1 ? 'Task' : 'Tasks'}</strong> and <strong style="color:#16a34a;">${subtaskCount} overdue ${subtaskCount === 1 ? 'Subtask' : 'Subtasks'}</strong> that are still pending delivery. Please review the details below and follow up with the PIC where appropriate.</p>
    ${htmlItems.join('\n')}
    <p>${escapeHtml(actionText)}</p>
    <p>
      Best regards,<br>
      AI &amp; Data Lab<br>
      Institutional Advancement<br>
      The University of Hong Kong
    </p>
  </div>`;

  return { subject, text: textLines.join('\n'), html };
}

async function sendPicOverdueSummaryEmail({ to, subject, text, html }) {
  if (smtpMail.isSmtpConfigured()) {
    const r = await smtpMail.sendSmtpMail({ to, subject, text, html });
    return { ...r, transport: 'smtp' };
  }
  const r = await sendNotificationEmail({
    to,
    subject,
    text,
    html,
    from: NOTIFICATION_EMAIL_FROM,
  });
  return { ...r, transport: 'email' };
}

async function runPicOverdueSummaryReminderJob(options = {}) {
  const todayYmd = hkTodayYyyyMmDd();
  const dryRun = options.dryRun === true;
  const sendToOverride = normalizeRecipientEmail(options.sendToOverride);
  const targetEmail = normalizeRecipientEmail(options.targetEmail);
  console.log(
    `[pic-overdue] start today=${todayYmd} dryRun=${dryRun} targetEmail=${targetEmail || 'all'}`,
  );
  const summary = {
    todayHk: todayYmd,
    scannedTasks: 0,
    scannedSubtasks: 0,
    eligibleItems: 0,
    recipientGroups: 0,
    emailsAttempted: 0,
    emailsOk: 0,
    dryRun,
    transport: 'smtp',
    errors: [],
  };
  if (dryRun) {
    summary.previews = [];
  }
  if (!db) {
    summary.errors.push('Database not configured');
    return summary;
  }
  if (!EMAIL_SENDING_ENABLED && !dryRun) {
    return summary;
  }
  if (!dryRun && !outboundEmailConfigured()) {
    summary.errors.push(
      'Outbound email transport not configured (set SMTP_HOST and SMTP_FROM)',
    );
    return summary;
  }

  const staffByKey = new Map();
  const { data: staffRows, error: staffErr } = await db
    .from('staff')
    .select('id, app_id, email, name, active');
  if (staffErr) {
    summary.errors.push(staffErr.message || String(staffErr));
    return summary;
  }
  for (const row of staffRows || []) {
    const id = String(row.id || '').trim();
    const appId = String(row.app_id || '').trim();
    if (id) staffByKey.set(id, row);
    if (appId) staffByKey.set(appId, row);
  }
  console.log(`[pic-overdue] loaded staff rows=${(staffRows || []).length}`);

  function staffForKey(key) {
    const normalized = String(key || '').trim();
    if (!normalized) return null;
    return staffByKey.get(normalized) || null;
  }

  const groups = new Map();
  async function addItemForPic(picKey, item) {
    const picStaff = staffForKey(picKey);
    if (!picStaff) {
      summary.errors.push(`${item.kind.toLowerCase()} ${item.id}: PIC staff not found (${picKey})`);
      return;
    }
    if (!staffActiveForReminder(picStaff)) return;
    const to = await resolveStaffEmailForNotifications(db, picStaff);
    if (!to) {
      summary.errors.push(`${item.kind.toLowerCase()} ${item.id}: PIC has no email (${picKey})`);
      return;
    }
    const normalizedTo = normalizeRecipientEmail(to);
    if (targetEmail && normalizedTo !== targetEmail) return;
    const staffId = String(picStaff.id || picKey).trim();
    if (!groups.has(staffId)) {
      groups.set(staffId, {
        staff: picStaff,
        to: normalizedTo,
        items: [],
      });
    }
    groups.get(staffId).items.push(item);
    summary.eligibleItems += 1;
  }

  const pausedProjectIds = await fetchPausedProjectIdSet(db);
  const blockedParentTaskIds = await fetchSubtaskReminderBlockedParentTaskIdSet(db);
  console.log(
    `[pic-overdue] loaded blocked sets pausedProjects=${pausedProjectIds.size} blockedParentTasks=${blockedParentTaskIds.size}`,
  );

  const { data: tasks, error: taskErr } = await db
    .from('task')
    .select('id, task_name, description, create_by, due_date, pic, submission, status, pause_status, project_id');
  if (taskErr) {
    summary.errors.push(taskErr.message || String(taskErr));
    return summary;
  }
  console.log(`[pic-overdue] loaded task rows=${(tasks || []).length}`);

  for (const taskRow of tasks || []) {
    summary.scannedTasks += 1;
    if (taskRow.due_date == null || taskRow.due_date === '') continue;
    if (submissionBlocksOverdueSummaryReminder(taskRow.submission)) continue;
    if (taskStatusBlocksUrgentReminder(taskRow.status)) continue;
    if (taskReminderPaused(taskRow, pausedProjectIds)) continue;
    if (!isCalendarPastDue(todayYmd, taskRow.due_date)) continue;
    const picKey = String(taskRow.pic || '').trim();
    if (!picKey) continue;
    const taskId = String(taskRow.id || '').trim();
    const creatorStaff = staffForKey(taskRow.create_by);
    await addItemForPic(picKey, {
      id: taskId,
      kind: 'Task',
      typeRank: 0,
      title: reminderTextValue(taskRow.task_name),
      description: reminderDescription(taskRow.description),
      creatorName: reminderTextValue(creatorStaff?.name || taskRow.create_by),
      dueYmd: formatTaskDueDateYYYYMMDD(taskRow.due_date),
      overdueText: overdueDaysText(todayYmd, formatTaskDueDateYYYYMMDD(taskRow.due_date)),
      url: picReminderDirectTaskUrl(taskId),
    });
  }

  const { data: subtasks, error: subtaskErr } = await db
    .from('subtask')
    .select('id, task_id, subtask_name, description, create_by, due_date, pic, submission, status, pause_status');
  if (subtaskErr) {
    summary.errors.push(subtaskErr.message || String(subtaskErr));
    return summary;
  }
  console.log(`[pic-overdue] loaded subtask rows=${(subtasks || []).length}`);

  for (const row of subtasks || []) {
    summary.scannedSubtasks += 1;
    if (row.due_date == null || row.due_date === '') continue;
    if (submissionBlocksOverdueSummaryReminder(row.submission)) continue;
    if (subtaskStatusBlocksUrgentReminder(row.status)) continue;
    if (isPausedStatus(row.pause_status)) continue;
    const taskFk = String(row.task_id || '').trim();
    if (taskFk && blockedParentTaskIds.has(taskFk)) continue;
    if (!isCalendarPastDue(todayYmd, row.due_date)) continue;
    const picKey = String(row.pic || '').trim();
    if (!picKey) continue;
    const subtaskId = String(row.id || '').trim();
    const creatorStaff = staffForKey(row.create_by);
    await addItemForPic(picKey, {
      id: subtaskId,
      kind: 'Subtask',
      typeRank: 1,
      title: reminderTextValue(row.subtask_name),
      description: reminderDescription(row.description),
      creatorName: reminderTextValue(creatorStaff?.name || row.create_by),
      dueYmd: formatTaskDueDateYYYYMMDD(row.due_date),
      overdueText: overdueDaysText(todayYmd, formatTaskDueDateYYYYMMDD(row.due_date)),
      url: picReminderDirectSubtaskUrl(subtaskId),
    });
  }

  for (const group of groups.values()) {
    group.items.sort((a, b) => {
      if (a.dueYmd !== b.dueYmd) return a.dueYmd.localeCompare(b.dueYmd);
      if (a.typeRank !== b.typeRank) return a.typeRank - b.typeRank;
      return a.title.localeCompare(b.title);
    });
  }

  summary.recipientGroups = groups.size;
  console.log(
    `[pic-overdue] grouped eligibleItems=${summary.eligibleItems} recipientGroups=${summary.recipientGroups}`,
  );
  for (const group of groups.values()) {
    const displayName = reminderTextValue(group.staff.name || group.to);
    const { subject, text, html } = buildPicOverdueSummaryEmail(displayName, group.items);
    const sendTo = sendToOverride || group.to;
    if (dryRun) {
      summary.previews.push({
        to: group.to,
        sendTo,
        displayName,
        itemCount: group.items.length,
        text,
      });
      continue;
    }
    const r = await sendPicOverdueSummaryEmail({
      to: sendTo,
      subject: mailSubjectSingleLine(subject),
      text,
      html,
    });
    summary.emailsAttempted += 1;
    if (r.ok) {
      summary.emailsOk += 1;
    } else {
      summary.errors.push(
        `${r.transport || summary.transport} PIC overdue summary to=${r.resolvedTo ?? sendTo}: ${formatEmailFailure(r)}`,
      );
    }
  }

  return summary;
}

async function runCreatorOverdueSummaryReminderJob(options = {}) {
  const todayYmd = hkTodayYyyyMmDd();
  const dryRun = options.dryRun === true;
  const sendToOverride = normalizeRecipientEmail(options.sendToOverride);
  const targetEmail = normalizeRecipientEmail(options.targetEmail);
  console.log(
    `[creator-overdue] start today=${todayYmd} dryRun=${dryRun} targetEmail=${targetEmail || 'all'}`,
  );
  const summary = {
    todayHk: todayYmd,
    scannedTasks: 0,
    scannedSubtasks: 0,
    eligibleItems: 0,
    recipientGroups: 0,
    emailsAttempted: 0,
    emailsOk: 0,
    dryRun,
    transport: 'smtp',
    errors: [],
  };
  if (dryRun) {
    summary.previews = [];
  }
  if (!db) {
    summary.errors.push('Database not configured');
    return summary;
  }
  if (!EMAIL_SENDING_ENABLED && !dryRun) {
    return summary;
  }
  if (!dryRun && !outboundEmailConfigured()) {
    summary.errors.push(
      'Outbound email transport not configured (set SMTP_HOST and SMTP_FROM)',
    );
    return summary;
  }

  const staffByKey = new Map();
  const { data: staffRows, error: staffErr } = await db
    .from('staff')
    .select('id, app_id, email, name, active');
  if (staffErr) {
    summary.errors.push(staffErr.message || String(staffErr));
    return summary;
  }
  for (const row of staffRows || []) {
    const id = String(row.id || '').trim();
    const appId = String(row.app_id || '').trim();
    if (id) staffByKey.set(id, row);
    if (appId) staffByKey.set(appId, row);
  }

  function staffForKey(key) {
    const normalized = String(key || '').trim();
    if (!normalized) return null;
    return staffByKey.get(normalized) || null;
  }

  const groups = new Map();
  async function addItemForCreator(creatorKey, item) {
    const creatorStaff = staffForKey(creatorKey);
    if (!creatorStaff) {
      summary.errors.push(
        `${item.kind.toLowerCase()} ${item.id}: creator staff not found (${creatorKey})`,
      );
      return;
    }
    if (!staffActiveForReminder(creatorStaff)) return;
    const to = await resolveStaffEmailForNotifications(db, creatorStaff);
    if (!to) {
      summary.errors.push(
        `${item.kind.toLowerCase()} ${item.id}: creator has no email (${creatorKey})`,
      );
      return;
    }
    const normalizedTo = normalizeRecipientEmail(to);
    if (targetEmail && normalizedTo !== targetEmail) return;
    const staffId = String(creatorStaff.id || creatorKey).trim();
    if (!groups.has(staffId)) {
      groups.set(staffId, {
        staff: creatorStaff,
        to: normalizedTo,
        items: [],
      });
    }
    groups.get(staffId).items.push(item);
    summary.eligibleItems += 1;
  }

  const pausedProjectIds = await fetchPausedProjectIdSet(db);
  const blockedParentTaskIds = await fetchSubtaskReminderBlockedParentTaskIdSet(db);

  const { data: tasks, error: taskErr } = await db
    .from('task')
    .select('id, task_name, description, create_by, due_date, pic, submission, status, pause_status, project_id');
  if (taskErr) {
    summary.errors.push(taskErr.message || String(taskErr));
    return summary;
  }

  for (const taskRow of tasks || []) {
    summary.scannedTasks += 1;
    if (taskRow.due_date == null || taskRow.due_date === '') continue;
    if (submissionBlocksOverdueSummaryReminder(taskRow.submission)) continue;
    if (taskStatusBlocksUrgentReminder(taskRow.status)) continue;
    if (taskReminderPaused(taskRow, pausedProjectIds)) continue;
    if (!isCalendarPastDue(todayYmd, taskRow.due_date)) continue;
    const creatorKey = String(taskRow.create_by || '').trim();
    if (!creatorKey) continue;
    const taskId = String(taskRow.id || '').trim();
    const picStaff = staffForKey(taskRow.pic);
    const dueYmd = formatTaskDueDateYYYYMMDD(taskRow.due_date);
    await addItemForCreator(creatorKey, {
      id: taskId,
      kind: 'Task',
      typeRank: 0,
      title: reminderTextValue(taskRow.task_name),
      description: reminderDescription(taskRow.description),
      picName: reminderTextValue(picStaff?.name || taskRow.pic),
      dueYmd,
      overdueText: overdueDaysText(todayYmd, dueYmd),
      url: picReminderDirectTaskUrl(taskId),
    });
  }

  const { data: subtasks, error: subtaskErr } = await db
    .from('subtask')
    .select('id, task_id, subtask_name, description, create_by, due_date, pic, submission, status, pause_status');
  if (subtaskErr) {
    summary.errors.push(subtaskErr.message || String(subtaskErr));
    return summary;
  }

  for (const row of subtasks || []) {
    summary.scannedSubtasks += 1;
    if (row.due_date == null || row.due_date === '') continue;
    if (submissionBlocksOverdueSummaryReminder(row.submission)) continue;
    if (subtaskStatusBlocksUrgentReminder(row.status)) continue;
    if (isPausedStatus(row.pause_status)) continue;
    const taskFk = String(row.task_id || '').trim();
    if (taskFk && blockedParentTaskIds.has(taskFk)) continue;
    if (!isCalendarPastDue(todayYmd, row.due_date)) continue;
    const creatorKey = String(row.create_by || '').trim();
    if (!creatorKey) continue;
    const subtaskId = String(row.id || '').trim();
    const picStaff = staffForKey(row.pic);
    const dueYmd = formatTaskDueDateYYYYMMDD(row.due_date);
    await addItemForCreator(creatorKey, {
      id: subtaskId,
      kind: 'Subtask',
      typeRank: 1,
      title: reminderTextValue(row.subtask_name),
      description: reminderDescription(row.description),
      picName: reminderTextValue(picStaff?.name || row.pic),
      dueYmd,
      overdueText: overdueDaysText(todayYmd, dueYmd),
      url: picReminderDirectSubtaskUrl(subtaskId),
    });
  }

  for (const group of groups.values()) {
    group.items.sort((a, b) => {
      if (a.dueYmd !== b.dueYmd) return a.dueYmd.localeCompare(b.dueYmd);
      if (a.typeRank !== b.typeRank) return a.typeRank - b.typeRank;
      return a.title.localeCompare(b.title);
    });
  }

  summary.recipientGroups = groups.size;
  console.log(
    `[creator-overdue] grouped eligibleItems=${summary.eligibleItems} recipientGroups=${summary.recipientGroups}`,
  );
  for (const group of groups.values()) {
    const displayName = reminderTextValue(group.staff.name || group.to);
    const { subject, text, html } = buildCreatorOverdueSummaryEmail(displayName, group.items);
    const sendTo = sendToOverride || group.to;
    if (dryRun) {
      summary.previews.push({
        to: group.to,
        sendTo,
        displayName,
        itemCount: group.items.length,
        text,
      });
      continue;
    }
    const r = await sendPicOverdueSummaryEmail({
      to: sendTo,
      subject: mailSubjectSingleLine(subject),
      text,
      html,
    });
    summary.emailsAttempted += 1;
    if (r.ok) {
      summary.emailsOk += 1;
    } else {
      summary.errors.push(
        `${r.transport || summary.transport} creator overdue summary to=${r.resolvedTo ?? sendTo}: ${formatEmailFailure(r)}`,
      );
    }
  }

  return summary;
}

function submissionIsSubmittedForDailyReminder(submissionRaw) {
  return String(submissionRaw || '').trim().toLowerCase() === 'submitted';
}

function submissionAllowsOverdueDailyReminder(submissionRaw) {
  const s = String(submissionRaw || '').trim().toLowerCase();
  return s === '' || s === 'pending' || s === 'returned';
}

const DAILY_REMINDER_SECTIONS = [
  {
    key: 'submittedTasks',
    title: 'Submitted Tasks Awaiting Your Review',
    color: '#2563eb',
    itemType: 'Task',
  },
  {
    key: 'submittedSubtasks',
    title: 'Submitted Subtasks Awaiting Your Review',
    color: '#16a34a',
    itemType: 'Subtask',
  },
  {
    key: 'picOverdueTasks',
    title: 'Overdue Tasks Where You Are PIC',
    color: '#dc2626',
    itemType: 'Task',
  },
  {
    key: 'picOverdueSubtasks',
    title: 'Overdue Subtasks Where You Are PIC',
    color: '#ea580c',
    itemType: 'Subtask',
  },
  {
    key: 'creatorOverdueTasks',
    title: 'Overdue Tasks Created By You',
    color: '#7c3aed',
    itemType: 'Task',
  },
  {
    key: 'creatorOverdueSubtasks',
    title: 'Overdue Subtasks Created By You',
    color: '#0891b2',
    itemType: 'Subtask',
  },
];

function emptyDailyReminderSections() {
  const out = {};
  for (const section of DAILY_REMINDER_SECTIONS) {
    out[section.key] = [];
  }
  return out;
}

function dailyReminderSummaryLabel(sectionTitle) {
  const s = String(sectionTitle || '')
    .replace('Awaiting Your Review', 'awaiting your review')
    .replace('Where You Are PIC', 'where you are PIC')
    .replace('Created By You', 'created by you');
  return `${s.charAt(0).toLowerCase()}${s.slice(1)}`;
}

function buildCombinedDailyReminderEmail(displayName, sections) {
  const greetingName = reminderTextValue(displayName);
  const subject = '[Project Tracker] Daily Reminder: Overdue and Submitted Items';
  const activeSections = DAILY_REMINDER_SECTIONS
    .map((section) => ({ ...section, items: sections[section.key] || [] }))
    .filter((section) => section.items.length > 0);

  const textLines = [
    `Dear ${greetingName},`,
    '',
    'This is your daily Project Tracker reminder.',
    '',
    'You have:',
  ];
  for (const section of activeSections) {
    textLines.push(`- ${section.items.length} ${dailyReminderSummaryLabel(section.title)}`);
  }
  textLines.push('');
  textLines.push('Please review the details below.');
  textLines.push('');

  const htmlSummary = activeSections
    .map(
      (section) =>
        `<li><strong style="color:${section.color};">${section.items.length} ${escapeHtml(dailyReminderSummaryLabel(section.title))}</strong></li>`,
    )
    .join('\n');

  const htmlSections = [];
  for (const section of activeSections) {
    textLines.push(`${section.title}: ${section.items.length}`);
    textLines.push('');
    const itemHtml = [];
    section.items.forEach((item, idx) => {
      const prefix = `(${idx + 1}/${section.items.length})`;
      const dueDisplay = eventEmailDateValue(item.dueYmd);
      const dueLine = `${dueDisplay}${item.overdueText || ''}`;
      textLines.push(`${prefix} ${item.title}`);
      textLines.push(`Description: ${item.description}`);
      if (item.creatorName) textLines.push(`Creator: ${item.creatorName}`);
      if (item.picName) textLines.push(`PIC: ${item.picName}`);
      textLines.push(`Due date: ${dueLine}`);
      textLines.push(`Submission: ${item.submission}`);
      textLines.push(`URL: ${item.url}`);
      textLines.push('');

      itemHtml.push(`
        <div style="margin:0 0 18px 0;">
          <div style="font-size:16px;font-weight:700;color:${section.color};">${escapeHtml(`${prefix} ${item.title}`)}</div>
          <div style="white-space:pre-line;">Description: ${escapeHtml(item.description)}</div>
          ${item.creatorName ? `<div>Creator: ${escapeHtml(item.creatorName)}</div>` : ''}
          ${item.picName ? `<div>PIC: ${escapeHtml(item.picName)}</div>` : ''}
          <div>Due date: ${escapeHtml(dueLine)}</div>
          <div>Submission: ${escapeHtml(item.submission)}</div>
          <div>URL: <a href="${escapeHtml(item.url)}">${escapeHtml(item.url)}</a></div>
        </div>`);
    });

    htmlSections.push(`
      <div style="margin:24px 0 10px 0;font-size:18px;font-weight:700;color:${section.color};">
        ${escapeHtml(`${section.title}: ${section.items.length}`)}
      </div>
      ${itemHtml.join('\n')}`);
  }

  textLines.push(
    'For submitted items, please review the submitted work and make a judgement: Accept or Return.',
  );
  textLines.push('');
  textLines.push('For overdue items where you are PIC, please review and update the delivery status.');
  textLines.push('');
  textLines.push(
    'For overdue items created by you, please follow up with the PIC. If the original requirement or timeline is no longer suitable, please discuss with the PIC and update the task/subtask requirement or delivery date in Project Tracker.',
  );
  textLines.push('');
  textLines.push('Best regards,');
  textLines.push('AI & Data Lab');
  textLines.push('Institutional Advancement');
  textLines.push('The University of Hong Kong');

  const html = `
  <div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;line-height:1.5;color:#111827;">
    <p>Dear ${escapeHtml(greetingName)},</p>
    <p>This is your daily Project Tracker reminder.</p>
    <p>You have:</p>
    <ul>${htmlSummary}</ul>
    <p>Please review the details below.</p>
    ${htmlSections.join('\n')}
    <p>For submitted items, please review the submitted work and make a judgement: Accept or Return.</p>
    <p>For overdue items where you are PIC, please review and update the delivery status.</p>
    <p>For overdue items created by you, please follow up with the PIC. If the original requirement or timeline is no longer suitable, please discuss with the PIC and update the task/subtask requirement or delivery date in Project Tracker.</p>
    <p>
      Best regards,<br>
      AI &amp; Data Lab<br>
      Institutional Advancement<br>
      The University of Hong Kong
    </p>
  </div>`;

  return { subject, text: textLines.join('\n'), html };
}

async function runCombinedDailyReminderJob(options = {}) {
  const todayYmd = hkTodayYyyyMmDd();
  const dryRun = options.dryRun === true;
  const sendToOverride = normalizeRecipientEmail(options.sendToOverride);
  const targetEmail = normalizeRecipientEmail(options.targetEmail);
  console.log(
    `[daily-reminder] start today=${todayYmd} dryRun=${dryRun} targetEmail=${targetEmail || 'all'}`,
  );
  const summary = {
    todayHk: todayYmd,
    scannedTasks: 0,
    scannedSubtasks: 0,
    eligibleItems: 0,
    recipientGroups: 0,
    emailsAttempted: 0,
    emailsOk: 0,
    dryRun,
    transport: 'smtp',
    errors: [],
  };
  if (dryRun) summary.previews = [];
  if (!db) {
    summary.errors.push('Database not configured');
    return summary;
  }
  if (!EMAIL_SENDING_ENABLED && !dryRun) return summary;
  if (!dryRun && !outboundEmailConfigured()) {
    summary.errors.push(
      'Outbound email transport not configured (set SMTP_HOST and SMTP_FROM)',
    );
    return summary;
  }

  const staffByKey = new Map();
  const { data: staffRows, error: staffErr } = await db
    .from('staff')
    .select('id, app_id, email, name, active');
  if (staffErr) {
    summary.errors.push(staffErr.message || String(staffErr));
    return summary;
  }
  for (const row of staffRows || []) {
    const id = String(row.id || '').trim();
    const appId = String(row.app_id || '').trim();
    if (id) staffByKey.set(id, row);
    if (appId) staffByKey.set(appId, row);
  }

  function staffForKey(key) {
    const normalized = String(key || '').trim();
    if (!normalized) return null;
    return staffByKey.get(normalized) || null;
  }

  const groups = new Map();
  async function addSectionItem(staffKey, sectionKey, item) {
    const staff = staffForKey(staffKey);
    if (!staff || !staffActiveForReminder(staff)) return;
    const to = await resolveStaffEmailForNotifications(db, staff);
    if (!to) {
      summary.errors.push(`${sectionKey} ${item.id}: recipient has no email (${staffKey})`);
      return;
    }
    const normalizedTo = normalizeRecipientEmail(to);
    if (targetEmail && normalizedTo !== targetEmail) return;
    const staffId = String(staff.id || staffKey).trim();
    if (!groups.has(staffId)) {
      groups.set(staffId, {
        staff,
        to: normalizedTo,
        sections: emptyDailyReminderSections(),
      });
    }
    groups.get(staffId).sections[sectionKey].push(item);
    summary.eligibleItems += 1;
  }

  const pausedProjectIds = await fetchPausedProjectIdSet(db);
  const blockedParentTaskIds = await fetchSubtaskReminderBlockedParentTaskIdSet(db);

  const { data: tasks, error: taskErr } = await db
    .from('task')
    .select('id, task_name, description, create_by, due_date, pic, submission, status, pause_status, project_id');
  if (taskErr) {
    summary.errors.push(taskErr.message || String(taskErr));
    return summary;
  }

  for (const taskRow of tasks || []) {
    summary.scannedTasks += 1;
    if (taskStatusBlocksUrgentReminder(taskRow.status)) continue;
    if (taskReminderPaused(taskRow, pausedProjectIds)) continue;
    const taskId = String(taskRow.id || '').trim();
    const dueYmd = formatTaskDueDateYYYYMMDD(taskRow.due_date);
    const baseItem = {
      id: taskId,
      title: reminderTextValue(taskRow.task_name),
      description: reminderDescription(taskRow.description),
      dueYmd,
      overdueText: overdueDaysText(todayYmd, dueYmd),
      submission: reminderTextValue(taskRow.submission || 'Pending'),
      url: picReminderDirectTaskUrl(taskId),
    };
    const creatorStaff = staffForKey(taskRow.create_by);
    const picStaff = staffForKey(taskRow.pic);
    if (submissionIsSubmittedForDailyReminder(taskRow.submission)) {
      await addSectionItem(taskRow.create_by, 'submittedTasks', {
        ...baseItem,
        picName: reminderTextValue(picStaff?.name || taskRow.pic),
      });
      continue;
    }
    if (
      taskRow.due_date != null &&
      taskRow.due_date !== '' &&
      isCalendarPastDue(todayYmd, taskRow.due_date) &&
      submissionAllowsOverdueDailyReminder(taskRow.submission)
    ) {
      await addSectionItem(taskRow.pic, 'picOverdueTasks', {
        ...baseItem,
        creatorName: reminderTextValue(creatorStaff?.name || taskRow.create_by),
      });
      await addSectionItem(taskRow.create_by, 'creatorOverdueTasks', {
        ...baseItem,
        picName: reminderTextValue(picStaff?.name || taskRow.pic),
      });
    }
  }

  const { data: subtasks, error: subtaskErr } = await db
    .from('subtask')
    .select('id, task_id, subtask_name, description, create_by, due_date, pic, submission, status, pause_status');
  if (subtaskErr) {
    summary.errors.push(subtaskErr.message || String(subtaskErr));
    return summary;
  }

  for (const row of subtasks || []) {
    summary.scannedSubtasks += 1;
    if (subtaskStatusBlocksUrgentReminder(row.status)) continue;
    if (isPausedStatus(row.pause_status)) continue;
    const taskFk = String(row.task_id || '').trim();
    if (taskFk && blockedParentTaskIds.has(taskFk)) continue;
    const subtaskId = String(row.id || '').trim();
    const dueYmd = formatTaskDueDateYYYYMMDD(row.due_date);
    const baseItem = {
      id: subtaskId,
      title: reminderTextValue(row.subtask_name),
      description: reminderDescription(row.description),
      dueYmd,
      overdueText: overdueDaysText(todayYmd, dueYmd),
      submission: reminderTextValue(row.submission || 'Pending'),
      url: picReminderDirectSubtaskUrl(subtaskId),
    };
    const creatorStaff = staffForKey(row.create_by);
    const picStaff = staffForKey(row.pic);
    if (submissionIsSubmittedForDailyReminder(row.submission)) {
      await addSectionItem(row.create_by, 'submittedSubtasks', {
        ...baseItem,
        picName: reminderTextValue(picStaff?.name || row.pic),
      });
      continue;
    }
    if (
      row.due_date != null &&
      row.due_date !== '' &&
      isCalendarPastDue(todayYmd, row.due_date) &&
      submissionAllowsOverdueDailyReminder(row.submission)
    ) {
      await addSectionItem(row.pic, 'picOverdueSubtasks', {
        ...baseItem,
        creatorName: reminderTextValue(creatorStaff?.name || row.create_by),
      });
      await addSectionItem(row.create_by, 'creatorOverdueSubtasks', {
        ...baseItem,
        picName: reminderTextValue(picStaff?.name || row.pic),
      });
    }
  }

  for (const group of groups.values()) {
    for (const section of DAILY_REMINDER_SECTIONS) {
      group.sections[section.key].sort((a, b) => {
        if (a.dueYmd !== b.dueYmd) return a.dueYmd.localeCompare(b.dueYmd);
        return a.title.localeCompare(b.title);
      });
    }
  }

  summary.recipientGroups = groups.size;
  for (const group of groups.values()) {
    const displayName = reminderTextValue(group.staff.name || group.to);
    const { subject, text, html } = buildCombinedDailyReminderEmail(
      displayName,
      group.sections,
    );
    const sendTo = sendToOverride || group.to;
    if (dryRun) {
      summary.previews.push({
        to: group.to,
        sendTo,
        displayName,
        text,
      });
      continue;
    }
    const r = await sendPicOverdueSummaryEmail({
      to: sendTo,
      subject: mailSubjectSingleLine(subject),
      text,
      html,
    });
    summary.emailsAttempted += 1;
    if (r.ok) summary.emailsOk += 1;
    else {
      summary.errors.push(
        `${r.transport || summary.transport} daily reminder to=${r.resolvedTo ?? sendTo}: ${formatEmailFailure(r)}`,
      );
    }
  }

  return summary;
}

/** Returns true if the request was rejected (response already sent). */
function cronUnauthorized(req, res) {
  if (!CRON_SECRET) {
    sendJson(req, res, 503, {
      error:
        'CRON_SECRET is not set on this server. In Railway → your service → Variables, add CRON_SECRET (any long random string), redeploy, then send the same value in the X-Cron-Secret header.',
    });
    return true;
  }
  if (!verifyCronSecret(req)) {
    sendJson(req, res, 401, {
      error:
        'X-Cron-Secret does not match CRON_SECRET on the server. Fix the header value or Railway Variables.',
    });
    return true;
  }
  return false;
}

async function handleCronUrgentTaskReminders(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  if (cronUnauthorized(req, res)) return;
  try {
    const urgent = await runUrgentTaskReminderJob();
    const assigneeUrgentSubtask = await runAssigneeUrgentSubtaskReminderJob();
    const creatorUrgent = await runCreatorUrgentTaskReminderJob();
    const creatorUrgentSubtask = await runCreatorUrgentSubtaskReminderJob();
    const dueToday = await runDueTodayTaskReminderJob();
    const assigneeDueTodaySubtask = await runAssigneeDueTodaySubtaskReminderJob();
    const creatorDueToday = await runCreatorDueTodayReminderJob();
    const creatorDueTodaySubtask = await runCreatorDueTodaySubtaskReminderJob();
    const creatorOverdue = await runCreatorOverdueTaskReminderJob();
    const assigneeOverdue = await runAssigneeOverdueTaskReminderJob();
    const creatorOverdueSubtask = await runCreatorOverdueSubtaskReminderJob();
    const assigneeOverdueSubtask = await runAssigneeOverdueSubtaskReminderJob();
    sendJson(req, res, 200, {
      ok: true,
      urgent,
      assigneeUrgentSubtask,
      creatorUrgent,
      creatorUrgentSubtask,
      dueToday,
      assigneeDueTodaySubtask,
      creatorDueToday,
      creatorDueTodaySubtask,
      creatorOverdue,
      assigneeOverdue,
      creatorOverdueSubtask,
      assigneeOverdueSubtask,
    });
  } catch (e) {
    console.error('handleCronUrgentTaskReminders:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/** POST — only the due-today reminder job (HK calendar: today = due_date). Same CRON_SECRET as other cron routes. */
async function handleCronDueTodayOnly(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  if (cronUnauthorized(req, res)) return;
  try {
    const dueToday = await runDueTodayTaskReminderJob();
    const assigneeDueTodaySubtask = await runAssigneeDueTodaySubtaskReminderJob();
    const creatorDueToday = await runCreatorDueTodayReminderJob();
    const creatorDueTodaySubtask = await runCreatorDueTodaySubtaskReminderJob();
    sendJson(req, res, 200, {
      ok: true,
      dueToday,
      assigneeDueTodaySubtask,
      creatorDueToday,
      creatorDueTodaySubtask,
    });
  } catch (e) {
    console.error('handleCronDueTodayOnly:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/** POST — grouped overdue task/subtask summary by PIC. */
async function handleCronPicOverdueReminders(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  if (cronUnauthorized(req, res)) return;
  try {
    console.log('[pic-overdue] handler authorized; reading body');
    const body = await readBody(req);
    console.log('[pic-overdue] handler body read');
    const summary = await runPicOverdueSummaryReminderJob({
      dryRun: body.dryRun === true,
      targetEmail: body.targetEmail,
      sendToOverride: body.sendToOverride,
    });
    sendJson(req, res, 200, { ok: true, picOverdue: summary });
  } catch (e) {
    console.error('handleCronPicOverdueReminders:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/** POST — grouped overdue task/subtask summary by creator. */
async function handleCronCreatorOverdueReminders(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  if (cronUnauthorized(req, res)) return;
  try {
    console.log('[creator-overdue] handler authorized; reading body');
    const body = await readBody(req);
    console.log('[creator-overdue] handler body read');
    const summary = await runCreatorOverdueSummaryReminderJob({
      dryRun: body.dryRun === true,
      targetEmail: body.targetEmail,
      sendToOverride: body.sendToOverride,
    });
    sendJson(req, res, 200, { ok: true, creatorOverdue: summary });
  } catch (e) {
    console.error('handleCronCreatorOverdueReminders:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/** POST — one combined daily reminder email per user. */
async function handleCronDailyReminder(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  if (cronUnauthorized(req, res)) return;
  try {
    console.log('[daily-reminder] handler authorized; reading body');
    const body = await readBody(req);
    console.log('[daily-reminder] handler body read');
    const summary = await runCombinedDailyReminderJob({
      dryRun: body.dryRun === true,
      targetEmail: body.targetEmail,
      sendToOverride: body.sendToOverride,
    });
    sendJson(req, res, 200, { ok: true, dailyReminder: summary });
  } catch (e) {
    console.error('handleCronDailyReminder:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * POST { taskId } — creator only; emails each assignee (assignee_01..10) with Email.
 */
async function handleNotifyTaskAssigned(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!db) {
    sendJson(req, res, 503, { error: 'Database not configured' });
    return;
  }
  if (!EMAIL_SENDING_ENABLED) {
    notifyEmailSkippedResponse(req, res);
    return;
  }
  if (!outboundEmailConfigured()) {
    sendJson(req, res, 503, { error: 'Outbound email transport not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const taskId = (body.taskId || '').trim();
    if (!taskId) {
      sendJson(req, res, 400, { error: 'taskId required' });
      return;
    }
    const { data: taskRow, error: tErr } = await db
      .from('task')
      .select('*')
      .eq('id', taskId)
      .maybeSingle();
    if (tErr || !taskRow) {
      sendJson(req, res, 404, { error: 'Task not found' });
      return;
    }
    const creatorId = taskRow.create_by?.toString().trim();
    if (!creatorId) {
      sendJson(req, res, 400, { error: 'Task has no create_by' });
      return;
    }
    const { data: creatorStaff, error: cErr } = await db
      .from('staff')
      .select('id, name, email')
      .eq('id', creatorId)
      .maybeSingle();
    if (cErr || !creatorStaff) {
      sendJson(req, res, 400, { error: 'Creator staff not found' });
      return;
    }
    const creatorEmail = (creatorStaff.email || '').trim().toLowerCase();
    const sessionEmail = (session.email || '').trim().toLowerCase();
    if (!creatorEmail || creatorEmail !== sessionEmail) {
      sendJson(req, res, 403, {
        error: 'Only the task creator (staff email must match signed-in user) can send assignment emails',
      });
      return;
    }
    const staffDisplayName =
      (creatorStaff.name || '').trim() ||
      creatorEmail;
    const taskName = (taskRow.task_name || '').toString().trim() || '(no title)';
    const detailLines = await buildTaskUpdateDetailLines(
      db,
      taskRow,
      emailChangeMap(body.changes),
      { commentAddedText: body.commentAddedText },
    );

    const assigneeIds = collectTaskAssigneeStaffIds(taskRow);

    const subject = `[Project Tracker] New Task Assigned: ${mailSubjectSingleLine(taskName)}`;

    const results = [];
    const creatorNorm = creatorId.toLowerCase();

    for (const staffUuid of assigneeIds) {
      if (String(staffUuid).trim().toLowerCase() === creatorNorm) {
        results.push({
          staffId: staffUuid,
          ok: true,
          skipped: 'task creator is excluded from task creation email',
        });
        continue;
      }
      const { data: s } = await fetchStaffRowForCreateBy(db, staffUuid);
      const to = (
        (await resolveStaffEmailForNotifications(db, s)) ||
        (s?.email || '').trim()
      ).trim();
      if (!to) {
        results.push({ staffId: staffUuid, ok: false, skipped: 'no email on staff row' });
        continue;
      }
      const recipientName = (s?.name || '').trim() || to;
      const html = `<div style="margin:0;font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;line-height:1.5;color:#000000;">Dear ${escapeHtml(recipientName)},<br><br>
This email is to inform you that a new task has been created and assigned to you.<br><br>
${detailLines.html}<br><br>
Please review the new task in Project Tracker. ${eventTaskLinkHtml(taskId)}<br><br>
${projectTrackerEmailFooterHtml()}</div>`;
      const text = `Dear ${recipientName},

This email is to inform you that a new task has been created and assigned to you.

${detailLines.text}

Please review the new task in Project Tracker. ${eventTaskLinkText(taskId)}

${projectTrackerEmailFooterText()}`;
      const r = await sendNotificationEmail({
        to,
        subject,
        text,
        html,
        from: NOTIFICATION_EMAIL_FROM,
        replyTo: creatorEmail,
      });
      results.push({
        to,
        ok: r.ok,
        messageId: r.ok ? r.id : null,
        error: r.ok ? null : r.error,
        detail: r.ok ? null : r.detail,
      });
    }

    sendJson(req, res, 200, {
      ok: true,
      taskId,
      recipients: results.length,
      results,
    });
  } catch (e) {
    console.error('handleNotifyTaskAssigned:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * Project assignment email (`handleNotifyProjectAssigned`): creator line + project link + Project Tracker; Aptos 16px.
 *
 * @param {{ creatorDisplayName: string, projectName: string, projectUrl: string }} p
 */
function buildProjectAssignedEmailHtml(p) {
  const safeCreator = escapeHtml(p.creatorDisplayName);
  const safeTitle = escapeHtml(p.projectName);
  const safeUrlAttr = escapeHtml(p.projectUrl);
  const safeLandingHref = escapeHtml(PROJECT_TRACKER_LANDING_URL);
  const bodyFont =
    "font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;line-height:1.5;color:#000000;";
  return `<div style="margin:0;${bodyFont}">${safeCreator} assigned you a project.<br><br>
<a href="${safeUrlAttr}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;font-weight:bold;text-decoration:underline;color:#1565C0;">${safeTitle}</a><br><br>
<a href="${safeLandingHref}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;color:#1565C0;">Project Tracker</a></div>`;
}

function buildProjectAssignedEmailText(p) {
  return `${p.creatorDisplayName} assigned you a project.

${p.projectName}
${p.projectUrl}

Project Tracker
${PROJECT_TRACKER_LANDING_URL}`;
}

/**
 * POST { projectId } — creator only; emails each project assignee (assignee_01..20). Reply-To: creator email.
 * Duplicate assignee slots / create_by also an assignee: one message per distinct recipient email.
 */
async function handleNotifyProjectAssigned(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!db) {
    sendJson(req, res, 503, { error: 'Database not configured' });
    return;
  }
  if (!EMAIL_SENDING_ENABLED) {
    notifyEmailSkippedResponse(req, res);
    return;
  }
  if (!outboundEmailConfigured()) {
    sendJson(req, res, 503, { error: 'Outbound email transport not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const projectId = (body.projectId || '').trim();
    if (!projectId) {
      sendJson(req, res, 400, { error: 'projectId required' });
      return;
    }
    const { data: projectRow, error: pErr } = await db
      .from('project')
      .select('*')
      .eq('id', projectId)
      .maybeSingle();
    if (pErr || !projectRow) {
      sendJson(req, res, 404, { error: 'Project not found' });
      return;
    }
    const creatorId = projectRow.create_by?.toString().trim();
    if (!creatorId) {
      sendJson(req, res, 400, { error: 'Project has no create_by' });
      return;
    }
    const { data: creatorStaff, error: cErr } = await db
      .from('staff')
      .select('id, name, email')
      .eq('id', creatorId)
      .maybeSingle();
    if (cErr || !creatorStaff) {
      sendJson(req, res, 400, { error: 'Creator staff not found' });
      return;
    }
    const sessionEmail = (session.email || '').trim().toLowerCase();
    const creatorMatchesSession = await sessionEmailBelongsToStaffRow(
      db,
      creatorStaff,
      sessionEmail,
    );
    if (!creatorMatchesSession) {
      sendJson(req, res, 403, {
        error:
          'Only the project creator (signed-in email must match staff.email or linked app_users email) can send assignment emails',
      });
      return;
    }
    const creatorReplyTo = (
      (await resolveStaffEmailForNotifications(db, creatorStaff)) ||
      (creatorStaff.email || '').trim()
    ).trim();
    const staffDisplayName =
      (creatorStaff.name || '').trim() ||
      creatorReplyTo ||
      sessionEmail ||
      'Colleague';
    const projectName = (projectRow.name || '').toString().trim() || '(no title)';
    const projectUrl = projectWebAppUrl(projectId);
    const assigneeUuids = collectProjectAssigneeStaffIds(projectRow);
    const subject = "You've been assigned a project";
    const results = [];
    const seenEmails = new Set();

    if (assigneeUuids.length === 0) {
      sendJson(req, res, 200, {
        ok: true,
        projectId,
        recipients: 0,
        results: [{ ok: true, skipped: 'no assignees on project' }],
      });
      return;
    }

    for (const staffUuid of assigneeUuids) {
      const { data: s } = await db
        .from('staff')
        .select('id, email, name')
        .eq('id', staffUuid)
        .maybeSingle();
      if (!s) {
        results.push({ staffId: staffUuid, ok: false, skipped: 'assignee staff not found' });
        continue;
      }
      const to = (
        (await resolveStaffEmailForNotifications(db, s)) ||
        (s.email || '').trim()
      ).trim();
      if (!to) {
        results.push({ staffId: staffUuid, ok: false, skipped: 'no email on staff row' });
        continue;
      }
      const toNorm = to.toLowerCase();
      if (seenEmails.has(toNorm)) {
        results.push({
          staffId: staffUuid,
          ok: true,
          skipped: 'duplicate recipient email (same inbox already notified)',
        });
        continue;
      }
      seenEmails.add(toNorm);
      const html = buildProjectAssignedEmailHtml({
        creatorDisplayName: staffDisplayName,
        projectName,
        projectUrl,
      });
      const text = buildProjectAssignedEmailText({
        creatorDisplayName: staffDisplayName,
        projectName,
        projectUrl,
      });
      const r = await sendNotificationEmail({
        to,
        subject,
        text,
        html,
        from: NOTIFICATION_EMAIL_FROM,
        replyTo: creatorReplyTo || undefined,
      });
      results.push({
        to,
        ok: r.ok,
        messageId: r.ok ? r.id : null,
        error: r.ok ? null : r.error,
        detail: r.ok ? null : r.detail,
      });
    }

    sendJson(req, res, 200, {
      ok: true,
      projectId,
      recipients: results.filter((x) => x.ok && !x.skipped).length,
      results,
    });
  } catch (e) {
    console.error('handleNotifyProjectAssigned:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * POST { projectId, changes } — signed-in email must match `project.update_by` (`staff` / `app_users`).
 * Emails each non-empty project assignee slot (assignee_01..20) only (deduped); skips updater when they are an assignee.
 */
async function handleNotifyProjectUpdated(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!db) {
    sendJson(req, res, 503, { error: 'Database not configured' });
    return;
  }
  if (!EMAIL_SENDING_ENABLED) {
    notifyEmailSkippedResponse(req, res);
    return;
  }
  if (!outboundEmailConfigured()) {
    sendJson(req, res, 503, { error: 'Outbound email transport not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const projectId = (body.projectId || '').trim();
    if (!projectId) {
      sendJson(req, res, 400, { error: 'projectId required' });
      return;
    }
    const { data: projectRow, error: pErr } = await db
      .from('project')
      .select('*')
      .eq('id', projectId)
      .maybeSingle();
    if (pErr || !projectRow) {
      sendJson(req, res, 404, { error: 'Project not found' });
      return;
    }
    const updaterId = (projectRow.update_by || '').toString().trim();
    if (!updaterId) {
      sendJson(req, res, 400, { error: 'Project has no update_by' });
      return;
    }
    const { data: updaterStaff, error: uErr } = await fetchStaffRowForCreateBy(db, updaterId);
    if (uErr || !updaterStaff) {
      sendJson(req, res, 400, { error: 'Updater staff not found' });
      return;
    }
    const sessionEmail = (session.email || '').trim().toLowerCase();
    const updaterMatchesSession = await sessionEmailBelongsToStaffRow(
      db,
      updaterStaff,
      sessionEmail,
    );
    if (!updaterMatchesSession) {
      sendJson(req, res, 403, {
        error:
          'Only the user who updated the project (signed-in email must match staff.email or linked app_users email for update_by) can send update emails',
      });
      return;
    }
    const updaterReplyTo = (
      (await resolveStaffEmailForNotifications(db, updaterStaff)) ||
      (updaterStaff.email || '').trim()
    ).trim();
    const updaterNameForBody =
      (updaterStaff.name || '').trim() ||
      updaterReplyTo ||
      sessionEmail ||
      'Colleague';
    const projectName = (projectRow.name || '').toString().trim() || '(no title)';
    const projectTitleForSubject = mailSubjectSingleLine(projectName).replace(/"/g, '');
    const subject = `Project updated - ${projectTitleForSubject}`;
    const projectUrl = projectWebAppUrl(projectId);
    const updatedAtLine = formatUpdateDateTimeYmdHm(projectRow.update_date);

    const changeLinesHtmlParts = [];
    const changeLinesTextParts = [];
    const rawChanges = Array.isArray(body.changes) ? body.changes : [];
    let nCh = 0;
    for (const row of rawChanges) {
      if (nCh >= TASK_UPDATE_NOTIFY_MAX_CHANGES) break;
      if (!row || typeof row !== 'object') continue;
      const field = String(row.field || '').trim();
      const label = PROJECT_UPDATE_NOTIFY_FIELD_LABELS[field];
      if (!label) continue;
      let value = row.value;
      if (value == null) value = '';
      value = String(value);
      if (value.length > TASK_UPDATE_NOTIFY_MAX_VALUE_LEN) {
        value = `${value.slice(0, TASK_UPDATE_NOTIFY_MAX_VALUE_LEN)}…`;
      }
      const safeVal = escapeHtml(value);
      const safeLbl = escapeHtml(label);
      changeLinesHtmlParts.push(
        `<span style="color:#000000;font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;">${safeLbl} is updated – ${safeVal}</span>`,
      );
      changeLinesTextParts.push(`${label} is updated – ${value}`);
      nCh += 1;
    }
    const changeLinesHtml = changeLinesHtmlParts.join('<br><br>');
    const changeLinesText = changeLinesTextParts.join('\n\n');

    if (changeLinesHtmlParts.length === 0) {
      sendJson(req, res, 200, {
        ok: true,
        skipped: true,
        projectId,
        message: 'No notifyable column changes in the request.',
        recipients: 0,
        results: [],
      });
      return;
    }

    const assigneeUuids = collectProjectAssigneeStaffIds(projectRow);
    const updaterNorm = updaterId.toLowerCase();
    const results = [];
    const replyTo = updaterReplyTo || sessionEmail || undefined;
    const seenEmails = new Set();

    for (const staffUuid of assigneeUuids) {
      if (String(staffUuid).trim().toLowerCase() === updaterNorm) {
        results.push({
          staffId: staffUuid,
          ok: true,
          skipped: 'updater is assignee; no self-email',
        });
        continue;
      }
      const { data: s } = await db
        .from('staff')
        .select('id, email, name')
        .eq('id', staffUuid)
        .maybeSingle();
      if (!s) {
        results.push({ staffId: staffUuid, ok: false, skipped: 'assignee staff not found' });
        continue;
      }
      const to = (
        (await resolveStaffEmailForNotifications(db, s)) ||
        (s.email || '').trim()
      ).trim();
      if (!to) {
        results.push({ staffId: staffUuid, ok: false, skipped: 'no email on staff row' });
        continue;
      }
      const toNorm = to.toLowerCase();
      if (seenEmails.has(toNorm)) {
        results.push({
          staffId: staffUuid,
          ok: true,
          skipped: 'duplicate recipient email',
        });
        continue;
      }
      seenEmails.add(toNorm);
      const displayNameForHi =
        (s.name || '').trim() ||
        to;
      const html = buildSubtaskUpdatedAssigneeEmailHtml({
        recipientDisplayName: displayNameForHi,
        changeLinesHtml,
        changeLinesText,
        commentLineHtml: '',
        commentLineText: '',
        subtaskName: projectName,
        subtaskUrl: projectUrl,
        updaterName: updaterNameForBody,
        updatedAtLine,
      });
      const text = buildSubtaskUpdatedAssigneeEmailText({
        recipientDisplayName: displayNameForHi,
        changeLinesHtml,
        changeLinesText,
        commentLineHtml: '',
        commentLineText: '',
        subtaskName: projectName,
        subtaskUrl: projectUrl,
        updaterName: updaterNameForBody,
        updatedAtLine,
      });
      const r = await sendNotificationEmail({
        to,
        subject,
        text,
        html,
        from: NOTIFICATION_EMAIL_FROM,
        replyTo,
      });
      results.push({
        to,
        ok: r.ok,
        messageId: r.ok ? r.id : null,
        error: r.ok ? null : r.error,
        detail: r.ok ? null : r.detail,
      });
    }

    sendJson(req, res, 200, {
      ok: true,
      projectId,
      recipients: results.filter((x) => x.ok && !x.skipped).length,
      results,
    });
  } catch (e) {
    console.error('handleNotifyProjectUpdated:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * POST { subtaskId } — creator only; emails each subtask assignee (assignee_01..10) with Email.
 * Creator receives mail only if they appear in assignee slots. Reply-To: creator email.
 */
async function handleNotifySubtaskAssigned(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!db) {
    sendJson(req, res, 503, { error: 'Database not configured' });
    return;
  }
  if (!EMAIL_SENDING_ENABLED) {
    notifyEmailSkippedResponse(req, res);
    return;
  }
  if (!outboundEmailConfigured()) {
    sendJson(req, res, 503, { error: 'Outbound email transport not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const subtaskId = (body.subtaskId || '').trim();
    if (!subtaskId) {
      sendJson(req, res, 400, { error: 'subtaskId required' });
      return;
    }
    const { data: row, error: tErr } = await db
      .from('subtask')
      .select('*')
      .eq('id', subtaskId)
      .maybeSingle();
    if (tErr || !row) {
      sendJson(req, res, 404, { error: 'Sub-task not found' });
      return;
    }
    const creatorId = row.create_by?.toString().trim();
    if (!creatorId) {
      sendJson(req, res, 400, { error: 'Sub-task has no create_by' });
      return;
    }
    const { data: creatorStaff, error: cErr } = await db
      .from('staff')
      .select('id, name, email')
      .eq('id', creatorId)
      .maybeSingle();
    if (cErr || !creatorStaff) {
      sendJson(req, res, 400, { error: 'Creator staff not found' });
      return;
    }
    const creatorEmail = (creatorStaff.email || '').trim().toLowerCase();
    const sessionEmail = (session.email || '').trim().toLowerCase();
    if (!creatorEmail || creatorEmail !== sessionEmail) {
      sendJson(req, res, 403, {
        error:
          'Only the sub-task creator (staff email must match signed-in user) can send assignment emails',
      });
      return;
    }
    const staffDisplayName =
      (creatorStaff.name || '').trim() ||
      creatorEmail;
    const subtaskName =
      (row.subtask_name || '').toString().trim() || '(no title)';
    const detailLines = await buildSubtaskUpdateDetailLines(db, row, new Map());
    const assigneeUuids = collectSubtaskAssigneeStaffIds(row);
    const subject = `[Project Tracker] New Subtask Assigned: ${mailSubjectSingleLine(subtaskName)}`;
    const results = [];
    const seenEmails = new Set();
    const creatorNorm = creatorId.toLowerCase();

    for (const staffUuid of assigneeUuids) {
      if (String(staffUuid).trim().toLowerCase() === creatorNorm) {
        results.push({
          staffId: staffUuid,
          ok: true,
          skipped: 'subtask creator is excluded from subtask creation email',
        });
        continue;
      }
      const { data: s } = await db
        .from('staff')
        .select('email, name')
        .eq('id', staffUuid)
        .maybeSingle();
      const to = (s?.email || '').trim().toLowerCase();
      if (!to) {
        results.push({ staffId: staffUuid, ok: false, skipped: 'no email on staff row' });
        continue;
      }
      if (seenEmails.has(to)) continue;
      seenEmails.add(to);
      const recipientName = (s?.name || '').trim() || to;
      const html = `<div style="margin:0;font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;line-height:1.5;color:#000000;">Dear ${escapeHtml(recipientName)},<br><br>
This email is to inform you that a new subtask has been created and assigned to you.<br><br>
${detailLines.html}<br><br>
Please review the new subtask in Project Tracker. ${eventSubtaskLinkHtml(subtaskId)}<br><br>
${projectTrackerEmailFooterHtml()}</div>`;
      const text = `Dear ${recipientName},

This email is to inform you that a new subtask has been created and assigned to you.

${detailLines.text}

Please review the new subtask in Project Tracker. ${eventSubtaskLinkText(subtaskId)}

${projectTrackerEmailFooterText()}`;
      const r = await sendNotificationEmail({
        to,
        subject,
        text,
        html,
        from: NOTIFICATION_EMAIL_FROM,
        replyTo: creatorEmail,
      });
      results.push({
        to,
        ok: r.ok,
        messageId: r.ok ? r.id : null,
        error: r.ok ? null : r.error,
        detail: r.ok ? null : r.detail,
      });
    }

    sendJson(req, res, 200, {
      ok: true,
      subtaskId,
      recipients: results.length,
      results,
    });
  } catch (e) {
    console.error('handleNotifySubtaskAssigned:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * POST { commentId } — comment author only; emails task creator (`create_by`) only when they are
 * not the comment author (no self-email when creator comments).
 */
async function handleNotifyTaskComment(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!TASK_COMMENT_EMAIL_ENABLED) {
    sendJson(req, res, 200, {
      ok: true,
      skipped: true,
      message: 'Task comment email notifications are disabled.',
    });
    return;
  }
  if (!db) {
    sendJson(req, res, 503, { error: 'Database not configured' });
    return;
  }
  if (!EMAIL_SENDING_ENABLED) {
    notifyEmailSkippedResponse(req, res);
    return;
  }
  if (!outboundEmailConfigured()) {
    sendJson(req, res, 503, { error: 'Outbound email transport not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const commentId = (body.commentId || '').trim();
    if (!commentId) {
      sendJson(req, res, 400, { error: 'commentId required' });
      return;
    }
    const { data: commentRow, error: cErr } = await db
      .from('comment')
      .select('id, task_id, description, create_by')
      .eq('id', commentId)
      .maybeSingle();
    if (cErr || !commentRow) {
      sendJson(req, res, 404, { error: 'Comment not found' });
      return;
    }
    const authorStaffId = (commentRow.create_by || '').toString().trim();
    if (!authorStaffId) {
      sendJson(req, res, 400, { error: 'Comment has no create_by' });
      return;
    }
    const { data: authorStaff, error: aErr } = await db
      .from('staff')
      .select('id, name, email')
      .eq('id', authorStaffId)
      .maybeSingle();
    if (aErr || !authorStaff) {
      sendJson(req, res, 400, { error: 'Comment author staff not found' });
      return;
    }
    const authorEmail = (authorStaff.email || '').trim().toLowerCase();
    const sessionEmail = (session.email || '').trim().toLowerCase();
    if (!authorEmail || authorEmail !== sessionEmail) {
      sendJson(req, res, 403, {
        error: 'Only the comment author (staff email must match signed-in user) can send comment emails',
      });
      return;
    }
    const taskId = (commentRow.task_id || '').toString().trim();
    if (!taskId) {
      sendJson(req, res, 400, { error: 'Comment has no task_id' });
      return;
    }
    const { data: taskRow, error: tErr } = await db
      .from('task')
      .select('*')
      .eq('id', taskId)
      .maybeSingle();
    if (tErr || !taskRow) {
      sendJson(req, res, 404, { error: 'Task not found' });
      return;
    }
    const authorNameForSubject =
      (authorStaff.name || '').trim() ||
      authorEmail;
    const taskName = (taskRow.task_name || '').toString().trim() || '(no title)';
    const taskTitleForSubject = mailSubjectSingleLine(taskName).replace(/"/g, '');
    const subject = `${mailSubjectSingleLine(authorNameForSubject)} comments on task "${taskTitleForSubject}"`;
    const taskUrl = taskWebAppUrl(taskId);

    const authorNorm = authorStaffId.toLowerCase();
    const creatorId = (taskRow.create_by || '').toString().trim();
    if (!creatorId) {
      sendJson(req, res, 400, { error: 'Task has no create_by' });
      return;
    }
    if (authorNorm === creatorId.toLowerCase()) {
      sendJson(req, res, 200, {
        ok: true,
        commentId,
        taskId,
        recipients: 0,
        results: [
          {
            ok: true,
            skipped: 'comment author is task creator; no self-email',
          },
        ],
      });
      return;
    }

    const { data: creatorStaff, error: crStaffErr } = await db
      .from('staff')
      .select('email, name')
      .eq('id', creatorId)
      .maybeSingle();
    if (crStaffErr || !creatorStaff) {
      sendJson(req, res, 400, { error: 'Task creator staff not found' });
      return;
    }
    const to = (creatorStaff.email || '').trim();
    const results = [];
    if (!to) {
      results.push({
        staffId: creatorId,
        ok: false,
        skipped: 'no email on creator staff row',
      });
      sendJson(req, res, 200, {
        ok: true,
        commentId,
        taskId,
        recipients: 0,
        results,
      });
      return;
    }

    const recipientDisplayName =
      (creatorStaff.name || '').trim() ||
      to;
    const html = buildTaskCommentCreatorEmailHtml({
      recipientDisplayName,
      commentDescription: commentRow.description,
      taskName,
      taskUrl,
    });
    const text = buildTaskCommentCreatorEmailText({
      recipientDisplayName,
      commentDescription: commentRow.description,
      taskName,
      taskUrl,
    });

    const r = await sendNotificationEmail({
      to,
      subject,
      text,
      html,
      from: NOTIFICATION_EMAIL_FROM,
      replyTo: authorEmail,
    });
    results.push({
      to,
      ok: r.ok,
      messageId: r.ok ? r.id : null,
      error: r.ok ? null : r.error,
      detail: r.ok ? null : r.detail,
    });

    sendJson(req, res, 200, {
      ok: true,
      commentId,
      taskId,
      recipients: results.length,
      results,
    });
  } catch (e) {
    console.error('handleNotifyTaskComment:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * POST { commentId } — after a task comment is edited: Firebase email must match `staff.email` for
 * `comment.update_by`. Emails task `create_by` + assignee_01..10 (deduped), never the editor.
 */
async function handleNotifyTaskEditedComment(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!TASK_COMMENT_EMAIL_ENABLED) {
    sendJson(req, res, 200, {
      ok: true,
      skipped: true,
      message: 'Task comment email notifications are disabled.',
    });
    return;
  }
  if (!db) {
    sendJson(req, res, 503, { error: 'Database not configured' });
    return;
  }
  if (!EMAIL_SENDING_ENABLED) {
    notifyEmailSkippedResponse(req, res);
    return;
  }
  if (!outboundEmailConfigured()) {
    sendJson(req, res, 503, { error: 'Outbound email transport not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const commentId = (body.commentId || '').trim();
    if (!commentId) {
      sendJson(req, res, 400, { error: 'commentId required' });
      return;
    }
    const { data: commentRow, error: cErr } = await db
      .from('comment')
      .select('id, task_id, description, update_by, update_date, create_date')
      .eq('id', commentId)
      .maybeSingle();
    if (cErr || !commentRow) {
      sendJson(req, res, 404, { error: 'Comment not found' });
      return;
    }
    const editorStaffId = (commentRow.update_by || '').toString().trim();
    if (!editorStaffId) {
      sendJson(req, res, 400, { error: 'Comment has no update_by' });
      return;
    }
    const { data: editorStaff, error: edErr } = await db
      .from('staff')
      .select('id, name, email')
      .eq('id', editorStaffId)
      .maybeSingle();
    if (edErr || !editorStaff) {
      sendJson(req, res, 400, { error: 'Comment editor staff not found' });
      return;
    }
    const editorEmail = (editorStaff.email || '').trim().toLowerCase();
    const sessionEmail = (session.email || '').trim().toLowerCase();
    if (!editorEmail || editorEmail !== sessionEmail) {
      sendJson(req, res, 403, {
        error:
          'Only the comment editor (staff email for update_by must match signed-in user) can send edit emails',
      });
      return;
    }
    const taskId = (commentRow.task_id || '').toString().trim();
    if (!taskId) {
      sendJson(req, res, 400, { error: 'Comment has no task_id' });
      return;
    }
    const { data: taskRow, error: tErr } = await db
      .from('task')
      .select('*')
      .eq('id', taskId)
      .maybeSingle();
    if (tErr || !taskRow) {
      sendJson(req, res, 404, { error: 'Task not found' });
      return;
    }
    const taskName = (taskRow.task_name || '').toString().trim() || '(no title)';
    const taskTitleForSubject = mailSubjectSingleLine(taskName).replace(/"/g, '');
    const editorNameForSubject =
      (editorStaff.name || '').trim() ||
      editorEmail;
    const subject = `${mailSubjectSingleLine(editorNameForSubject)} edited comments on task "${taskTitleForSubject}"`;
    const taskUrl = taskWebAppUrl(taskId);
    const updaterNameForBody =
      (editorStaff.name || '').trim() ||
      editorEmail;
    const updatedRaw =
      commentRow.update_date != null && String(commentRow.update_date).trim() !== ''
        ? commentRow.update_date
        : commentRow.create_date;
    const updatedAtLine = formatUpdateDateTimeYmdHm(updatedRaw);

    const recipientByNorm = buildTaskUpdatedDefaultRecipientStaffIds(taskRow);
    const editorNorm = editorStaffId.toLowerCase();
    recipientByNorm.delete(editorNorm);

    const results = [];
    if (recipientByNorm.size === 0) {
      sendJson(req, res, 200, {
        ok: true,
        commentId,
        taskId,
        recipients: 0,
        results: [
          {
            ok: true,
            skipped: 'no recipients after excluding editor (creator/assignees)',
          },
        ],
      });
      return;
    }

    for (const staffUuid of recipientByNorm.values()) {
      const { data: s } = await db
        .from('staff')
        .select('email, name')
        .eq('id', staffUuid)
        .maybeSingle();
      const to = (s?.email || '').trim();
      if (!to) {
        results.push({ staffId: staffUuid, ok: false, skipped: 'no email on staff row' });
        continue;
      }
      const recipientDisplayName =
        (s?.name || '').trim() ||
        to;
      const html = buildTaskCommentEditedEmailHtml({
        recipientDisplayName,
        commentDescription: commentRow.description,
        taskName,
        taskUrl,
        updaterDisplayName: updaterNameForBody,
        updatedAtLine,
      });
      const text = buildTaskCommentEditedEmailText({
        recipientDisplayName,
        commentDescription: commentRow.description,
        taskName,
        taskUrl,
        updaterDisplayName: updaterNameForBody,
        updatedAtLine,
      });
      const r = await sendNotificationEmail({
        to,
        subject,
        text,
        html,
        from: NOTIFICATION_EMAIL_FROM,
        replyTo: editorEmail,
      });
      results.push({
        to,
        ok: r.ok,
        messageId: r.ok ? r.id : null,
        error: r.ok ? null : r.error,
        detail: r.ok ? null : r.detail,
      });
    }

    sendJson(req, res, 200, {
      ok: true,
      commentId,
      taskId,
      recipients: results.filter((x) => x.ok && !x.skipped).length,
      results,
    });
  } catch (e) {
    console.error('handleNotifyTaskEditedComment:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * POST { commentId } — comment author only: Firebase email must match `staff.email` **or** any
 * `app_users.email` linked to `subtask_comment.create_by` → `staff.id`. Sends **one** Email message
 * to **subtask.create_by** (resolved `staff` + `app_users` email) when the author is not the
 * sub-task creator (no self-email). Creator-only comments use `handleNotifySubtaskUpdated`.
 */
async function handleNotifySubtaskComment(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!TASK_COMMENT_EMAIL_ENABLED) {
    sendJson(req, res, 200, {
      ok: true,
      skipped: true,
      message: 'Task/sub-task comment email notifications are disabled.',
    });
    return;
  }
  if (!db) {
    sendJson(req, res, 503, { error: 'Database not configured' });
    return;
  }
  if (!EMAIL_SENDING_ENABLED) {
    notifyEmailSkippedResponse(req, res);
    return;
  }
  if (!outboundEmailConfigured()) {
    sendJson(req, res, 503, { error: 'Outbound email transport not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const commentId = (body.commentId || '').trim();
    if (!commentId) {
      sendJson(req, res, 400, { error: 'commentId required' });
      return;
    }
    const { data: commentRow, error: cErr } = await db
      .from('subtask_comment')
      .select('id, subtask_id, description, create_by')
      .eq('id', commentId)
      .maybeSingle();
    if (cErr || !commentRow) {
      sendJson(req, res, 404, { error: 'Sub-task comment not found' });
      return;
    }
    const authorStaffId = (commentRow.create_by || '').toString().trim();
    if (!authorStaffId) {
      sendJson(req, res, 400, { error: 'Sub-task comment has no create_by' });
      return;
    }
    const { data: authorStaff, error: aErr } = await db
      .from('staff')
      .select('id, name, email')
      .eq('id', authorStaffId)
      .maybeSingle();
    if (aErr || !authorStaff) {
      sendJson(req, res, 400, { error: 'Comment author staff not found' });
      return;
    }
    const sessionEmail = (session.email || '').trim().toLowerCase();
    const authorMatchesSession = await sessionEmailBelongsToStaffRow(
      db,
      authorStaff,
      sessionEmail,
    );
    if (!authorMatchesSession) {
      sendJson(req, res, 403, {
        error:
          'Only the comment author (signed-in email must match staff.email or linked app_users email) can send comment emails',
      });
      return;
    }
    const authorReplyTo = (
      (await resolveStaffEmailForNotifications(db, authorStaff)) ||
      (authorStaff.email || '').trim()
    ).trim();
    const subtaskId = (commentRow.subtask_id || '').toString().trim();
    if (!subtaskId) {
      sendJson(req, res, 400, { error: 'Sub-task comment has no subtask_id' });
      return;
    }
    const { data: subtaskRow, error: tErr } = await db
      .from('subtask')
      .select('*')
      .eq('id', subtaskId)
      .maybeSingle();
    if (tErr || !subtaskRow) {
      sendJson(req, res, 404, { error: 'Sub-task not found' });
      return;
    }
    /** Resolved from `subtask_comment.create_by` → staff (subject line). */
    const authorNameForSubject =
      (authorStaff.name || '').trim() ||
      sessionEmail ||
      authorReplyTo ||
      'Colleague';
    const subtaskName =
      (subtaskRow.subtask_name || '').toString().trim() || '(no title)';
    const subtaskTitleForSubject = mailSubjectSingleLine(subtaskName).replace(/"/g, '');
    const subject = `${mailSubjectSingleLine(authorNameForSubject)} comments on sub-task "${subtaskTitleForSubject}"`;
    const subtaskRowId = (subtaskRow.id || subtaskId || '').toString().trim();
    const subtaskUrl = subtaskWebAppUrl(subtaskRowId);

    const authorNorm = authorStaffId.toLowerCase();
    const creatorId = (subtaskRow.create_by || '').toString().trim();
    if (!creatorId) {
      sendJson(req, res, 400, { error: 'Sub-task has no create_by' });
      return;
    }
    if (authorNorm === creatorId.toLowerCase()) {
      sendJson(req, res, 200, {
        ok: true,
        commentId,
        subtaskId,
        recipients: 0,
        results: [
          {
            ok: true,
            skipped: 'comment author is sub-task creator; no self-email',
          },
        ],
      });
      return;
    }

    const { data: creatorStaff, error: crStaffErr } = await db
      .from('staff')
      .select('id, email, name')
      .eq('id', creatorId)
      .maybeSingle();
    if (crStaffErr || !creatorStaff) {
      sendJson(req, res, 400, { error: 'Sub-task creator staff not found' });
      return;
    }
    const to = (
      (await resolveStaffEmailForNotifications(db, creatorStaff)) ||
      (creatorStaff.email || '').trim()
    ).trim();
    const results = [];
    if (!to) {
      results.push({
        staffId: creatorId,
        ok: false,
        skipped: 'no email on creator staff row',
      });
      sendJson(req, res, 200, {
        ok: true,
        commentId,
        subtaskId,
        recipients: 0,
        results,
      });
      return;
    }

    const recipientDisplayName =
      (creatorStaff.name || '').trim() ||
      to;
    const html = buildSubtaskCommentCreatorEmailHtml({
      recipientDisplayName,
      commentDescription: commentRow.description,
      subtaskName,
      subtaskUrl,
    });
    const text = buildSubtaskCommentCreatorEmailText({
      recipientDisplayName,
      commentDescription: commentRow.description,
      subtaskName,
      subtaskUrl,
    });

    const r = await sendNotificationEmail({
      to,
      subject,
      text,
      html,
      from: NOTIFICATION_EMAIL_FROM,
      replyTo: authorReplyTo || sessionEmail || undefined,
    });
    results.push({
      to,
      ok: r.ok,
      messageId: r.ok ? r.id : null,
      error: r.ok ? null : r.error,
      detail: r.ok ? null : r.detail,
    });

    sendJson(req, res, 200, {
      ok: true,
      commentId,
      subtaskId,
      recipients: results.length,
      results,
    });
  } catch (e) {
    console.error('handleNotifySubtaskComment:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * POST { commentId } — after a sub-task comment is edited: signed-in email must match the editor’s
 * staff row (`subtask_comment.update_by`), via `staff.email` or linked `app_users`. Emails sub-task
 * `create_by` + assignee_01..10 (deduped), never the editor.
 */
async function handleNotifySubtaskEditedComment(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!TASK_COMMENT_EMAIL_ENABLED) {
    sendJson(req, res, 200, {
      ok: true,
      skipped: true,
      message: 'Task/sub-task comment email notifications are disabled.',
    });
    return;
  }
  if (!db) {
    sendJson(req, res, 503, { error: 'Database not configured' });
    return;
  }
  if (!EMAIL_SENDING_ENABLED) {
    notifyEmailSkippedResponse(req, res);
    return;
  }
  if (!outboundEmailConfigured()) {
    sendJson(req, res, 503, { error: 'Outbound email transport not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const commentId = (body.commentId || '').trim();
    if (!commentId) {
      sendJson(req, res, 400, { error: 'commentId required' });
      return;
    }
    const { data: commentRow, error: cErr } = await db
      .from('subtask_comment')
      .select('id, subtask_id, description, update_by, update_date, create_date')
      .eq('id', commentId)
      .maybeSingle();
    if (cErr || !commentRow) {
      sendJson(req, res, 404, { error: 'Sub-task comment not found' });
      return;
    }
    const editorStaffId = (commentRow.update_by || '').toString().trim();
    if (!editorStaffId) {
      sendJson(req, res, 400, { error: 'Sub-task comment has no update_by' });
      return;
    }
    const { data: editorStaff, error: edErr } = await db
      .from('staff')
      .select('id, name, email')
      .eq('id', editorStaffId)
      .maybeSingle();
    if (edErr || !editorStaff) {
      sendJson(req, res, 400, { error: 'Comment editor staff not found' });
      return;
    }
    const sessionEmail = (session.email || '').trim().toLowerCase();
    const editorMatchesSession = await sessionEmailBelongsToStaffRow(
      db,
      editorStaff,
      sessionEmail,
    );
    if (!editorMatchesSession) {
      sendJson(req, res, 403, {
        error:
          'Only the comment editor (signed-in email must match staff.email or linked app_users email for update_by) can send edit emails',
      });
      return;
    }
    const editorReplyTo = (
      (await resolveStaffEmailForNotifications(db, editorStaff)) ||
      (editorStaff.email || '').trim()
    ).trim();
    const subtaskId = (commentRow.subtask_id || '').toString().trim();
    if (!subtaskId) {
      sendJson(req, res, 400, { error: 'Sub-task comment has no subtask_id' });
      return;
    }
    const { data: subtaskRow, error: sErr } = await db
      .from('subtask')
      .select('*')
      .eq('id', subtaskId)
      .maybeSingle();
    if (sErr || !subtaskRow) {
      sendJson(req, res, 404, { error: 'Sub-task not found' });
      return;
    }
    const subtaskName =
      (subtaskRow.subtask_name || '').toString().trim() || '(no title)';
    const subtaskTitleForSubject = mailSubjectSingleLine(subtaskName).replace(/"/g, '');
    const editorNameForSubject =
      (editorStaff.name || '').trim() ||
      sessionEmail ||
      editorReplyTo ||
      'Colleague';
    const subject = `${mailSubjectSingleLine(editorNameForSubject)} edited comments on sub-task "${subtaskTitleForSubject}"`;
    const subtaskRowId = (subtaskRow.id || subtaskId || '').toString().trim();
    const subtaskUrl = subtaskWebAppUrl(subtaskRowId);
    const updaterNameForBody =
      (editorStaff.name || '').trim() ||
      editorReplyTo ||
      sessionEmail ||
      'Colleague';
    const updatedRaw =
      commentRow.update_date != null && String(commentRow.update_date).trim() !== ''
        ? commentRow.update_date
        : commentRow.create_date;
    const updatedAtLine = formatUpdateDateTimeYmdHm(updatedRaw);

    const recipientByNorm = buildTaskUpdatedDefaultRecipientStaffIds(subtaskRow);
    const editorNorm = editorStaffId.toLowerCase();
    recipientByNorm.delete(editorNorm);

    const results = [];
    if (recipientByNorm.size === 0) {
      sendJson(req, res, 200, {
        ok: true,
        commentId,
        subtaskId,
        recipients: 0,
        results: [
          {
            ok: true,
            skipped: 'no recipients after excluding editor (creator/assignees)',
          },
        ],
      });
      return;
    }

    const replyTo = editorReplyTo || sessionEmail || undefined;

    for (const staffUuid of recipientByNorm.values()) {
      const { data: s } = await fetchStaffRowForCreateBy(db, staffUuid);
      const to = (
        (await resolveStaffEmailForNotifications(db, s)) ||
        (s?.email || '').trim()
      ).trim();
      if (!to) {
        results.push({ staffId: staffUuid, ok: false, skipped: 'no email on staff row' });
        continue;
      }
      const recipientDisplayName =
        (s?.name || '').trim() ||
        to;
      const html = buildSubtaskCommentEditedEmailHtml({
        recipientDisplayName,
        commentDescription: commentRow.description,
        subtaskName,
        subtaskUrl,
        updaterDisplayName: updaterNameForBody,
        updatedAtLine,
      });
      const text = buildSubtaskCommentEditedEmailText({
        recipientDisplayName,
        commentDescription: commentRow.description,
        subtaskName,
        subtaskUrl,
        updaterDisplayName: updaterNameForBody,
        updatedAtLine,
      });
      const r = await sendNotificationEmail({
        to,
        subject,
        text,
        html,
        from: NOTIFICATION_EMAIL_FROM,
        replyTo,
      });
      results.push({
        to,
        ok: r.ok,
        messageId: r.ok ? r.id : null,
        error: r.ok ? null : r.error,
        detail: r.ok ? null : r.detail,
      });
    }

    sendJson(req, res, 200, {
      ok: true,
      commentId,
      subtaskId,
      recipients: results.filter((x) => x.ok && !x.skipped).length,
      results,
    });
  } catch (e) {
    console.error('handleNotifySubtaskEditedComment:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * POST { taskId } — last updater only (session email = staff.email for task.update_by).
 * Emails each assignee (assignee_01..10) plus create_by, deduped; one Email message per recipient.
 * If the updater is the task creator and the payload includes at least one allowed field change
 * (task detail columns), the creator is not emailed (no self-email for column edits).
 * Comment-only updates: assignee (not creator) commenting → notify create_by only; creator (not
 * assignee) commenting → notify assignees only. If that targeted set is empty, falls back to the
 * default full recipient list.
 */
async function handleNotifyTaskUpdated(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!db) {
    sendJson(req, res, 503, { error: 'Database not configured' });
    return;
  }
  if (!EMAIL_SENDING_ENABLED) {
    notifyEmailSkippedResponse(req, res);
    return;
  }
  if (!outboundEmailConfigured()) {
    sendJson(req, res, 503, { error: 'Outbound email transport not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const taskId = (body.taskId || '').trim();
    if (!taskId) {
      sendJson(req, res, 400, { error: 'taskId required' });
      return;
    }
    const { data: taskRow, error: tErr } = await db
      .from('task')
      .select('*')
      .eq('id', taskId)
      .maybeSingle();
    if (tErr || !taskRow) {
      sendJson(req, res, 404, { error: 'Task not found' });
      return;
    }
    const taskCommentId = (body.taskCommentId || '').trim();
    let taskCommentRow = null;
    if (taskCommentId) {
      const { data: cRow, error: cErr } = await db
        .from('comment')
        .select('*')
        .eq('id', taskCommentId)
        .maybeSingle();
      if (cErr || !cRow || String(cRow.task_id || '').trim() !== taskId) {
        sendJson(req, res, 400, { error: 'taskCommentId does not match task' });
        return;
      }
      taskCommentRow = cRow;
    }
    let updaterId = taskCommentRow
      ? (taskCommentRow.create_by || '').toString().trim()
      : (taskRow.update_by || '').toString().trim();
    if (!updaterId) {
      sendJson(req, res, 400, { error: 'Task has no update_by' });
      return;
    }
    const { data: updaterStaff, error: uErr } = await fetchStaffRowForCreateBy(db, updaterId);
    if (uErr || !updaterStaff) {
      sendJson(req, res, 400, { error: 'Updater staff not found' });
      return;
    }
    const updaterEmail = (updaterStaff.email || '').trim().toLowerCase();
    const sessionEmail = (session.email || '').trim().toLowerCase();
    if (!updaterEmail || updaterEmail !== sessionEmail) {
      sendJson(req, res, 403, {
        error:
          'Only the user who updated the task (staff email must match signed-in user) can send update emails',
      });
      return;
    }
    const updaterNameForBody =
      (updaterStaff.name || '').trim() || updaterEmail;
    const taskName = (taskRow.task_name || '').toString().trim() || '(no title)';
    const taskTitleForSubject = mailSubjectSingleLine(taskName).replace(/"/g, '');
    const subject = `[Project Tracker] Task Update: ${taskTitleForSubject}`;
    const taskUrl = taskWebAppUrl(taskId);
    const taskRowHasUpdater = Boolean((taskRow.update_by || '').toString().trim());
    const updatedAtLine = taskCommentRow && !taskRowHasUpdater
      ? formatUpdateDateTimeYmdHm(taskCommentRow.create_date)
      : formatUpdateDateTimeYmdHm(taskRow.update_date);

    const changeLinesHtmlParts = [];
    const changeLinesTextParts = [];
    const rawChanges = Array.isArray(body.changes) ? body.changes : [];
    const changeMap = emailChangeMap(rawChanges);
    let nCh = 0;
    for (const row of rawChanges) {
      if (nCh >= TASK_UPDATE_NOTIFY_MAX_CHANGES) break;
      if (!row || typeof row !== 'object') continue;
      const field = String(row.field || '').trim();
      const label = TASK_UPDATE_NOTIFY_FIELD_LABELS[field];
      if (!label) continue;
      let value = Object.prototype.hasOwnProperty.call(row, 'newValue')
        ? row.newValue
        : row.value;
      if (value == null) value = '';
      value = String(value);
      if (value.length > TASK_UPDATE_NOTIFY_MAX_VALUE_LEN) {
        value = `${value.slice(0, TASK_UPDATE_NOTIFY_MAX_VALUE_LEN)}…`;
      }
      const safeVal = escapeHtml(value);
      const safeLbl = escapeHtml(label);
      changeLinesHtmlParts.push(
        `<span style="color:#000000;font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;">${safeLbl} is updated – ${safeVal}</span>`,
      );
      changeLinesTextParts.push(`${label} is updated – ${value}`);
      nCh += 1;
    }
    let commentLineHtml = '';
    let commentLineText = '';
    const rawComment =
      body.commentAddedText != null ? String(body.commentAddedText) : '';
    const commentTrim = rawComment.trim();
    if (commentTrim) {
      let c = commentTrim;
      if (c.length > TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN) {
        c = `${c.slice(0, TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN)}…`;
      }
      const safeC = escapeHtml(c);
      commentLineHtml = `<span style="color:#000000;font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;">Comment is added – ${safeC}</span>`;
      commentLineText = `Comment is added – ${c}`;
    }
    const changeLinesHtml = changeLinesHtmlParts.join('<br>');
    const changeLinesText = changeLinesTextParts.join('\n');

    const creatorId = (taskRow.create_by || '').toString().trim();
    const assigneeIdsForRouting = collectTaskAssigneeStaffIds(taskRow);
    /** @type {Map<string, string>} normalized staff id -> canonical id string */
    let recipientByNorm = buildTaskUpdatedDefaultRecipientStaffIds(taskRow);

    const updaterNorm = String(updaterId).trim().toLowerCase();
    const hasFieldChanges = changeLinesHtmlParts.length > 0;
    const hasComment = Boolean(commentTrim);
    const updaterInAssignees = assigneeIdsForRouting.some(
      (id) => String(id).trim().toLowerCase() === updaterNorm,
    );
    const updaterIsCreator =
      Boolean(creatorId) && updaterNorm === creatorId.toLowerCase();

    if (hasComment && !hasFieldChanges) {
      if (updaterInAssignees && !updaterIsCreator && creatorId) {
        recipientByNorm = new Map();
        recipientByNorm.set(creatorId.toLowerCase(), creatorId);
      } else if (updaterIsCreator && !updaterInAssignees) {
        recipientByNorm = new Map();
        for (const id of assigneeIdsForRouting) {
          const raw = String(id).trim();
          if (!raw) continue;
          const key = raw.toLowerCase();
          if (!recipientByNorm.has(key)) recipientByNorm.set(key, raw);
        }
      }
      if (recipientByNorm.size === 0) {
        recipientByNorm = buildTaskUpdatedDefaultRecipientStaffIds(taskRow);
      }
    }

    const creatorNormKey = creatorId ? creatorId.toLowerCase() : '';
    const skipEnsureCreatorBecauseCreatorNotAssigneeComment =
      hasComment &&
      !hasFieldChanges &&
      updaterIsCreator &&
      !updaterInAssignees;
    if (
      hasComment &&
      !hasFieldChanges &&
      creatorId &&
      updaterNorm !== creatorNormKey &&
      !skipEnsureCreatorBecauseCreatorNotAssigneeComment
    ) {
      recipientByNorm.set(creatorNormKey, creatorId);
    }
    mergeRecipientStaffKeys(recipientByNorm, await requestWorkflowExtraRecipientStaffKeys(body));
    mergeRecipientStaffKeys(
      recipientByNorm,
      await removedAssigneeStaffKeysFromChange(db, changeMap),
    );

    const omitSelfCreatorForFieldUpdates =
      changeLinesHtmlParts.length > 0 &&
      creatorId &&
      updaterNorm === creatorId.toLowerCase();

    recipientByNorm.delete(updaterNorm);

    const results = [];
    const replyTo = updaterEmail;
    const introText = commentTrim && !hasFieldChanges
      ? 'This email is to inform you that a comment has been added to the task.'
      : 'This email is to inform you that task information has been updated.';
    const detailLines = await buildTaskUpdateDetailLines(db, taskRow, changeMap, {
      commentText: commentTrim,
    });

    for (const staffUuid of recipientByNorm.values()) {
      if (
        omitSelfCreatorForFieldUpdates &&
        String(staffUuid).trim().toLowerCase() === updaterNorm
      ) {
        results.push({
          staffId: staffUuid,
          ok: true,
          skipped:
            'task creator is updater (task detail columns changed); no self-email',
        });
        continue;
      }
      const { data: s } = await db
        .from('staff')
        .select('email, name')
        .eq('id', staffUuid)
        .maybeSingle();
      const to = (s?.email || '').trim();
      if (!to) {
        results.push({ staffId: staffUuid, ok: false, skipped: 'no email on staff row' });
        continue;
      }
      const displayNameForHi =
        (s.name || '').trim() ||
        to;
      const html = buildTaskUpdatedAssigneeEmailHtml({
        recipientDisplayName: displayNameForHi,
        changeLinesHtml,
        changeLinesText,
        commentLineHtml,
        commentLineText,
        introHtml: escapeHtml(introText),
        introText,
        detailLinesHtml: detailLines.html,
        detailLinesText: detailLines.text,
        taskName,
        taskUrl,
        updaterName: updaterNameForBody,
        updatedAtLine,
      });
      const text = buildTaskUpdatedAssigneeEmailText({
        recipientDisplayName: displayNameForHi,
        changeLinesHtml,
        changeLinesText,
        commentLineHtml,
        commentLineText,
        introHtml: escapeHtml(introText),
        introText,
        detailLinesHtml: detailLines.html,
        detailLinesText: detailLines.text,
        taskName,
        taskUrl,
        updaterName: updaterNameForBody,
        updatedAtLine,
      });
      const r = await sendNotificationEmail({
        to,
        subject,
        text,
        html,
        from: NOTIFICATION_EMAIL_FROM,
        replyTo,
      });
      results.push({
        to,
        ok: r.ok,
        messageId: r.ok ? r.id : null,
        error: r.ok ? null : r.error,
        detail: r.ok ? null : r.detail,
      });
    }

    sendJson(req, res, 200, {
      ok: true,
      taskId,
      recipients: results.length,
      results,
    });
  } catch (e) {
    console.error('handleNotifyTaskUpdated:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * POST { subtaskId, changes?, commentAddedText? } — only when `subtask.update_by` is the sub-task
 * creator (`create_by`) and session email matches that staff row. One Email message per recipient:
 * assignee_01..10 (non-empty) plus `create_by`, deduped. Field lines: `{A} is updated – {new_value}`
 * for allowed keys; optional `commentAddedText`: `Sub-task comment is added – …` (creator comment).
 */
async function handleNotifySubtaskUpdated(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!db) {
    sendJson(req, res, 503, { error: 'Database not configured' });
    return;
  }
  if (!EMAIL_SENDING_ENABLED) {
    notifyEmailSkippedResponse(req, res);
    return;
  }
  if (!outboundEmailConfigured()) {
    sendJson(req, res, 503, { error: 'Outbound email transport not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const subtaskId = (body.subtaskId || '').trim();
    if (!subtaskId) {
      sendJson(req, res, 400, { error: 'subtaskId required' });
      return;
    }
    const { data: row, error: sErr } = await db
      .from('subtask')
      .select('*')
      .eq('id', subtaskId)
      .maybeSingle();
    if (sErr || !row) {
      sendJson(req, res, 404, { error: 'Sub-task not found' });
      return;
    }
    const subtaskCommentId = (body.subtaskCommentId || '').trim();
    let subtaskCommentRow = null;
    if (subtaskCommentId) {
      const { data: scRow, error: scErr } = await db
        .from('subtask_comment')
        .select('*')
        .eq('id', subtaskCommentId)
        .maybeSingle();
      if (scErr || !scRow || String(scRow.subtask_id || '').trim() !== subtaskId) {
        sendJson(req, res, 400, { error: 'subtaskCommentId does not match sub-task' });
        return;
      }
      subtaskCommentRow = scRow;
    }
    let updaterId = subtaskCommentRow
      ? (subtaskCommentRow.create_by || '').toString().trim()
      : (row.update_by || '').toString().trim();
    if (!updaterId) {
      sendJson(req, res, 400, { error: 'Sub-task has no update_by' });
      return;
    }
    const { data: updaterStaff, error: uErr } = await db
      .from('staff')
      .select('id, name, email')
      .eq('id', updaterId)
      .maybeSingle();
    if (uErr || !updaterStaff) {
      sendJson(req, res, 400, { error: 'Updater staff not found' });
      return;
    }
    const sessionEmail = (session.email || '').trim().toLowerCase();
    const updaterMatchesSession = await sessionEmailBelongsToStaffRow(
      db,
      updaterStaff,
      sessionEmail,
    );
    if (!updaterMatchesSession) {
      sendJson(req, res, 403, {
        error:
          'Only the user who updated the sub-task (signed-in email must match staff.email or linked app_users email) can send update emails',
      });
      return;
    }
    const updaterReplyTo = (
      (await resolveStaffEmailForNotifications(db, updaterStaff)) ||
      (updaterStaff.email || '').trim()
    ).trim();
    const updaterNameForBody =
      (updaterStaff.name || '').trim() ||
      updaterReplyTo ||
      sessionEmail ||
      'Colleague';
    const creatorId = (row.create_by || '').toString().trim();
    const updaterNorm = String(updaterId).trim().toLowerCase();

    const subtaskTitle =
      (row.subtask_name || '').toString().trim() || '(no title)';
    const subtaskTitleForSubject = mailSubjectSingleLine(subtaskTitle).replace(/"/g, '');
    const subject = `[Project Tracker] Subtask Update: ${subtaskTitleForSubject}`;
    const subtaskRowId = (row.id || subtaskId || '').toString().trim();
    const subtaskUrl = subtaskWebAppUrl(subtaskRowId);
    const rowHasUpdater = Boolean((row.update_by || '').toString().trim());
    const updatedAtLine = subtaskCommentRow && !rowHasUpdater
      ? formatUpdateDateTimeYmdHm(subtaskCommentRow.create_date)
      : formatUpdateDateTimeYmdHm(row.update_date);

    const dash = SUBTASK_COMMENT_ADDED_LINE_EN_DASH;
    const changeLinesHtmlParts = [];
    const changeLinesTextParts = [];
    const rawChanges = Array.isArray(body.changes) ? body.changes : [];
    const changeMap = emailChangeMap(rawChanges);
    let nCh = 0;
    for (const chRow of rawChanges) {
      if (nCh >= TASK_UPDATE_NOTIFY_MAX_CHANGES) break;
      if (!chRow || typeof chRow !== 'object') continue;
      const field = String(chRow.field || '').trim();
      const label = SUBTASK_UPDATE_NOTIFY_FIELD_LABELS[field];
      if (!label) continue;
      let value = Object.prototype.hasOwnProperty.call(chRow, 'newValue')
        ? chRow.newValue
        : chRow.value;
      if (value == null) value = '';
      value = String(value);
      if (value.length > TASK_UPDATE_NOTIFY_MAX_VALUE_LEN) {
        value = `${value.slice(0, TASK_UPDATE_NOTIFY_MAX_VALUE_LEN)}…`;
      }
      const safeVal = escapeHtml(value);
      const safeLbl = escapeHtml(label);
      changeLinesHtmlParts.push(`${safeLbl} is updated ${dash} ${safeVal}`);
      changeLinesTextParts.push(`${label} is updated ${dash} ${value}`);
      nCh += 1;
    }
    let commentLineHtml = '';
    let commentLineText = '';
    const rawSubComment =
      body.commentAddedText != null ? String(body.commentAddedText) : '';
    const commentPlain = subtaskCommentDescriptionPlainText(rawSubComment).trim();
    if (commentPlain) {
      let c = commentPlain;
      if (c.length > TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN) {
        c = `${c.slice(0, TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN)}…`;
      }
      const safeC = escapeHtml(c);
      commentLineHtml = `<span style="color:#000000;font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;">Comment is added ${dash} ${safeC}</span>`;
      commentLineText = `Comment is added ${dash} ${c}`;
    }
    const changeLinesHtml = changeLinesHtmlParts.join('<br><br>');
    const changeLinesText = changeLinesTextParts.join('\n\n');

    const hasFieldChanges = changeLinesHtmlParts.length > 0;
    const hasComment = Boolean(commentPlain);
    if (!hasFieldChanges && !hasComment) {
      sendJson(req, res, 200, {
        ok: true,
        skipped: true,
        subtaskId,
        message: 'No notifyable column changes or creator comment in the request.',
        recipients: 0,
        results: [],
      });
      return;
    }

    const recipientByNorm = buildTaskUpdatedDefaultRecipientStaffIds(row);
    mergeRecipientStaffKeys(recipientByNorm, await requestWorkflowExtraRecipientStaffKeys(body));
    mergeRecipientStaffKeys(
      recipientByNorm,
      await removedAssigneeStaffKeysFromChange(db, changeMap),
    );
    recipientByNorm.delete(updaterNorm);
    const results = [];
    const replyTo =
      updaterReplyTo || sessionEmail || undefined;
    const introText = commentPlain && !hasFieldChanges
      ? 'This email is to inform you that a comment has been added to the subtask.'
      : 'This email is to inform you that subtask information has been updated.';
    const detailLines = await buildSubtaskUpdateDetailLines(db, row, changeMap, {
      commentText: commentPlain,
    });

    for (const staffUuid of recipientByNorm.values()) {
      const { data: s } = await db
        .from('staff')
        .select('id, email, name')
        .eq('id', staffUuid)
        .maybeSingle();
      const to = (
        (await resolveStaffEmailForNotifications(db, s)) ||
        (s?.email || '').trim()
      ).trim();
      if (!to) {
        results.push({ staffId: staffUuid, ok: false, skipped: 'no email on staff row' });
        continue;
      }
      const displayNameForHi =
        (s.name || '').trim() ||
        to;
      const html = buildSubtaskUpdatedAssigneeEmailHtml({
        recipientDisplayName: displayNameForHi,
        changeLinesHtml,
        changeLinesText,
        commentLineHtml,
        commentLineText,
        introHtml: escapeHtml(introText),
        introText,
        detailLinesHtml: detailLines.html,
        detailLinesText: detailLines.text,
        subtaskName: subtaskTitle,
        subtaskUrl,
        updaterName: updaterNameForBody,
        updatedAtLine,
      });
      const text = buildSubtaskUpdatedAssigneeEmailText({
        recipientDisplayName: displayNameForHi,
        changeLinesHtml,
        changeLinesText,
        commentLineHtml,
        commentLineText,
        introHtml: escapeHtml(introText),
        introText,
        detailLinesHtml: detailLines.html,
        detailLinesText: detailLines.text,
        subtaskName: subtaskTitle,
        subtaskUrl,
        updaterName: updaterNameForBody,
        updatedAtLine,
      });
      const r = await sendNotificationEmail({
        to,
        subject,
        text,
        html,
        from: NOTIFICATION_EMAIL_FROM,
        replyTo,
      });
      results.push({
        to,
        ok: r.ok,
        messageId: r.ok ? r.id : null,
        error: r.ok ? null : r.error,
        detail: r.ok ? null : r.detail,
      });
    }

    sendJson(req, res, 200, {
      ok: true,
      subtaskId,
      recipients: results.length,
      results,
    });
  } catch (e) {
    console.error('handleNotifySubtaskUpdated:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/** Display name: staff.name, else email. */
function staffDisplayName(staffRow, fallbackEmail) {
  const n = (staffRow?.name || '').trim();
  if (n) return n;
  return (fallbackEmail || '').trim() || 'Colleague';
}

function buildTaskWorkflowEmailShell(taskName, taskUrl, bodyLinesHtml, bodyLinesText) {
  const safeTitle = escapeHtml(taskName);
  const safeTaskUrlAttr = escapeHtml(taskUrl);
  const landing = `${PROJECT_TRACKER_LANDING_URL}/`;
  const safeLandingHref = escapeHtml(landing);
  const html = `<div style="margin:0;font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;line-height:1.5;color:#000000;">${bodyLinesHtml}<br><br>
<a href="${safeTaskUrlAttr}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;font-weight:bold;text-decoration:underline;color:#1565C0;">${safeTitle}</a><br><br>
<a href="${safeLandingHref}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;color:#1565C0;">Project Tracker</a></div>`;
  const text = `${bodyLinesText.join('\n\n')}

${taskName}
${taskUrl}

Project Tracker
${landing}`;
  return { html, text };
}

function buildSubtaskWorkflowEmailShell(subtaskName, subtaskUrl, bodyLinesHtml, bodyLinesText) {
  const safeTitle = escapeHtml(subtaskName);
  const safeSubtaskUrlAttr = escapeHtml(subtaskUrl);
  const landing = `${PROJECT_TRACKER_LANDING_URL}/`;
  const safeLandingHref = escapeHtml(landing);
  const html = `<div style="margin:0;font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;line-height:1.5;color:#000000;">${bodyLinesHtml}<br><br>
<a href="${safeSubtaskUrlAttr}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;font-weight:bold;text-decoration:underline;color:#1565C0;">${safeTitle}</a><br><br>
<a href="${safeLandingHref}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;color:#1565C0;">Project Tracker</a></div>`;
  const text = `${bodyLinesText.join('\n\n')}

${subtaskName}
${subtaskUrl}

Project Tracker
${landing}`;
  return { html, text };
}

/**
 * POST { taskId } — PIC only. To: creator and assignees. Submission for review.
 */
async function handleNotifyTaskSubmission(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!db) {
    sendJson(req, res, 503, { error: 'Database not configured' });
    return;
  }
  if (!EMAIL_SENDING_ENABLED) {
    notifyEmailSkippedResponse(req, res);
    return;
  }
  if (!outboundEmailConfigured()) {
    sendJson(req, res, 503, { error: 'Outbound email transport not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const taskId = (body.taskId || '').trim();
    if (!taskId) {
      sendJson(req, res, 400, { error: 'taskId required' });
      return;
    }
    const { data: taskRow, error: tErr } = await db
      .from('task')
      .select('*')
      .eq('id', taskId)
      .maybeSingle();
    if (tErr || !taskRow) {
      sendJson(req, res, 404, { error: 'Task not found' });
      return;
    }
    const picId = (taskRow.pic || '').toString().trim();
    if (!picId) {
      sendJson(req, res, 400, { error: 'Task has no PIC' });
      return;
    }
    const { data: picStaff, error: pErr } = await fetchStaffRowForCreateBy(
      db,
      picId,
    );
    if (pErr || !picStaff) {
      sendJson(req, res, 400, { error: 'PIC staff not found' });
      return;
    }
    const picEmail = (picStaff.email || '').trim().toLowerCase();
    const sessionEmail = (session.email || '').trim().toLowerCase();
    const picNotifyEmail = await resolveStaffEmailForNotifications(db, picStaff);
    const picAddr = (picNotifyEmail || picEmail).toLowerCase();
    if (!sessionEmail || sessionEmail !== picAddr) {
      sendJson(req, res, 403, {
        error: 'Only the task PIC (staff email must match signed-in user) can send submission emails',
      });
      return;
    }
    const creatorRaw = (taskRow.create_by || '').toString().trim();
    const { data: creatorStaff } = await fetchStaffRowForCreateBy(db, creatorRaw);
    if (!creatorStaff) {
      sendJson(req, res, 400, { error: 'Creator staff not found' });
      return;
    }
    const taskName = (taskRow.task_name || '').toString().trim() || '(no title)';
    const taskTitleForSubject = mailSubjectSingleLine(taskName).replace(/"/g, '');
    const subject = `[Project Tracker] Task Submitted for Review: ${taskTitleForSubject}`;
    const detailLines = await buildTaskUpdateDetailLines(
      db,
      taskRow,
      workflowCompositeChangeMap(body.changes),
      { commentAddedText: body.commentAddedText },
    );
    const results = await sendTaskWorkflowEmailToAssignees({
      taskRow,
      actorStaffKey: picId,
      actorReplyTo: picNotifyEmail || picEmail,
      recipientStaffKeys: [taskRow.create_by],
      extraRecipientStaffKeys: await requestWorkflowExtraRecipientStaffKeys(body),
      subject,
      intro:
        'This email is to inform you that the task has been submitted for review. Please review the submitted work and make a judgement: accept or return.',
      detailLines,
      closing: 'Please review the submitted task in Project Tracker.',
      taskId,
    });
    const failed = results.find((x) => x.ok === false && !x.skipped);
    if (failed) {
      sendJson(req, res, 502, {
        error: failed.error || 'Failed to send notification email',
        detail: failed.detail || null,
        results,
      });
      return;
    }
    sendJson(req, res, 200, {
      ok: true,
      taskId,
      recipients: results.filter((x) => x.ok && !x.skipped).length,
      results,
    });
  } catch (e) {
    console.error('handleNotifyTaskSubmission:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

function recipientStaffMap(staffKeys) {
  const recipientByNorm = new Map();
  for (const rawKey of staffKeys || []) {
    const raw = String(rawKey || '').trim();
    if (!raw) continue;
    const key = raw.toLowerCase();
    if (!recipientByNorm.has(key)) recipientByNorm.set(key, raw);
  }
  return recipientByNorm;
}

function mergeRecipientStaffKeys(recipientByNorm, staffKeys) {
  for (const rawKey of staffKeys || []) {
    const raw = String(rawKey || '').trim();
    if (!raw) continue;
    const key = raw.toLowerCase();
    if (!recipientByNorm.has(key)) recipientByNorm.set(key, raw);
  }
}

function requestExtraRecipientStaffKeys(body) {
  return Array.isArray(body?.extraRecipientStaffKeys)
    ? body.extraRecipientStaffKeys
    : [];
}

function splitAssigneeEmailNames(value) {
  return String(value || '')
    .split(',')
    .map((x) => x.trim())
    .filter(Boolean);
}

async function removedAssigneeStaffKeysFromChange(dbClient, changeMap) {
  const change = changeMap?.get?.('assignees');
  if (!change) return [];
  const oldNames = splitAssigneeEmailNames(change.oldValue);
  const newNames = new Set(
    splitAssigneeEmailNames(change.newValue).map((name) => name.toLowerCase()),
  );
  const removedNames = oldNames.filter(
    (name) => !newNames.has(name.toLowerCase()),
  );
  if (removedNames.length === 0) return [];

  const removedNameSet = new Set(removedNames.map((name) => name.toLowerCase()));
  const { data: rows, error } = await dbClient
    .from('staff')
    .select('id, name');
  if (error) return [];
  return (rows || [])
    .filter((row) => removedNameSet.has(String(row?.name || '').trim().toLowerCase()))
    .map((row) => String(row?.id || '').trim())
    .filter(Boolean);
}

async function assigneeStaffKeysFromChange(dbClient, changeMap) {
  const change = changeMap?.get?.('assignees');
  if (!change) return [];
  const changedNames = [
    ...splitAssigneeEmailNames(change.oldValue),
    ...splitAssigneeEmailNames(change.newValue),
  ];
  if (changedNames.length === 0) return [];

  const changedNameSet = new Set(changedNames.map((name) => name.toLowerCase()));
  const { data: rows, error } = await dbClient
    .from('staff')
    .select('id, name');
  if (error) return [];
  return (rows || [])
    .filter((row) => changedNameSet.has(String(row?.name || '').trim().toLowerCase()))
    .map((row) => String(row?.id || '').trim())
    .filter(Boolean);
}

async function requestWorkflowExtraRecipientStaffKeys(body) {
  return [
    ...requestExtraRecipientStaffKeys(body),
    ...(await assigneeStaffKeysFromChange(db, emailChangeMap(body?.changes))),
  ];
}

async function sendTaskWorkflowEmailToAssignees({
  taskRow,
  actorStaffKey,
  actorReplyTo,
  recipientStaffKeys,
  extraRecipientStaffKeys,
  subject,
  intro,
  detailLines,
  closing,
  taskId,
}) {
  const recipientByNorm = Array.isArray(recipientStaffKeys)
    ? recipientStaffMap(recipientStaffKeys)
    : buildTaskUpdatedDefaultRecipientStaffIds(taskRow);
  mergeRecipientStaffKeys(recipientByNorm, extraRecipientStaffKeys);

  const results = [];
  for (const staffKey of recipientByNorm.values()) {
    const { data: staffRow } = await fetchStaffRowForCreateBy(db, staffKey);
    const to = await resolveStaffEmailForNotifications(db, staffRow);
    if (!to) {
      results.push({ staffId: staffKey, ok: false, skipped: 'no email on staff row' });
      continue;
    }
    const recipientName = staffDisplayName(staffRow, to);
    const html = `<div style="margin:0;font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;line-height:1.5;color:#000000;">Dear ${escapeHtml(recipientName)},<br><br>
${escapeHtml(intro)}<br><br>
${detailLines.html}<br><br>
${escapeHtml(closing)} ${eventTaskLinkHtml(taskId)}<br><br>
${projectTrackerEmailFooterHtml()}</div>`;
    const text = `Dear ${recipientName},

${intro}

${detailLines.text}

${closing} ${eventTaskLinkText(taskId)}

${projectTrackerEmailFooterText()}`;
    const r = await sendNotificationEmail({
      to,
      subject,
      text,
      html,
      from: NOTIFICATION_EMAIL_FROM,
      replyTo: actorReplyTo || undefined,
    });
    results.push({
      to,
      ok: r.ok,
      messageId: r.ok ? r.id : null,
      error: r.ok ? null : r.error,
      detail: r.ok ? null : r.detail,
    });
  }
  return results;
}

async function sendSubtaskWorkflowEmailToAssignees({
  row,
  actorStaffKey,
  actorReplyTo,
  recipientStaffKeys,
  extraRecipientStaffKeys,
  subject,
  intro,
  detailLines,
  closing,
  subtaskId,
}) {
  const recipientByNorm = Array.isArray(recipientStaffKeys)
    ? recipientStaffMap(recipientStaffKeys)
    : buildTaskUpdatedDefaultRecipientStaffIds(row);
  mergeRecipientStaffKeys(recipientByNorm, extraRecipientStaffKeys);

  const results = [];
  for (const staffKey of recipientByNorm.values()) {
    const { data: staffRow } = await fetchStaffRowForCreateBy(db, staffKey);
    const to = await resolveStaffEmailForNotifications(db, staffRow);
    if (!to) {
      results.push({ staffId: staffKey, ok: false, skipped: 'no email on staff row' });
      continue;
    }
    const recipientName = staffDisplayName(staffRow, to);
    const html = `<div style="margin:0;font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;line-height:1.5;color:#000000;">Dear ${escapeHtml(recipientName)},<br><br>
${escapeHtml(intro)}<br><br>
${detailLines.html}<br><br>
${escapeHtml(closing)} ${eventSubtaskLinkHtml(subtaskId)}<br><br>
${projectTrackerEmailFooterHtml()}</div>`;
    const text = `Dear ${recipientName},

${intro}

${detailLines.text}

${closing} ${eventSubtaskLinkText(subtaskId)}

${projectTrackerEmailFooterText()}`;
    const r = await sendNotificationEmail({
      to,
      subject,
      text,
      html,
      from: NOTIFICATION_EMAIL_FROM,
      replyTo: actorReplyTo || undefined,
    });
    results.push({
      to,
      ok: r.ok,
      messageId: r.ok ? r.id : null,
      error: r.ok ? null : r.error,
      detail: r.ok ? null : r.detail,
    });
  }
  return results;
}

/**
 * POST { taskId } — create_by only. To: creator and assignees. Task accepted.
 */
async function handleNotifyTaskAccepted(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!db) {
    sendJson(req, res, 503, { error: 'Database not configured' });
    return;
  }
  if (!EMAIL_SENDING_ENABLED) {
    notifyEmailSkippedResponse(req, res);
    return;
  }
  if (!outboundEmailConfigured()) {
    sendJson(req, res, 503, { error: 'Outbound email transport not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const taskId = (body.taskId || '').trim();
    if (!taskId) {
      sendJson(req, res, 400, { error: 'taskId required' });
      return;
    }
    const { data: taskRow, error: tErr } = await db
      .from('task')
      .select('*')
      .eq('id', taskId)
      .maybeSingle();
    if (tErr || !taskRow) {
      sendJson(req, res, 404, { error: 'Task not found' });
      return;
    }
    const creatorRaw = (taskRow.create_by || '').toString().trim();
    const { data: creatorStaff } = await fetchStaffRowForCreateBy(db, creatorRaw);
    if (!creatorStaff) {
      sendJson(req, res, 400, { error: 'Creator staff not found' });
      return;
    }
    const creatorEmail = (creatorStaff.email || '').trim().toLowerCase();
    const sessionEmail = (session.email || '').trim().toLowerCase();
    const creatorNotifyEmail = await resolveStaffEmailForNotifications(db, creatorStaff);
    const creatorAddr = (creatorNotifyEmail || creatorEmail).toLowerCase();
    if (!sessionEmail || sessionEmail !== creatorAddr) {
      sendJson(req, res, 403, {
        error:
          'Only the task creator (staff email must match signed-in user) can send acceptance emails',
      });
      return;
    }
    const taskName = (taskRow.task_name || '').toString().trim() || '(no title)';
    const taskTitleForSubject = mailSubjectSingleLine(taskName).replace(/"/g, '');
    const subject = `[Project Tracker] Task Submission Accepted: ${taskTitleForSubject}`;
    const detailLines = await buildTaskUpdateDetailLines(
      db,
      taskRow,
      workflowCompositeChangeMap(body.changes),
      { commentAddedText: body.commentAddedText },
    );
    const creatorNorm = creatorRaw.toLowerCase();
    const recipientStaffKeys = collectTaskAssigneeStaffIds(taskRow)
      .filter((key) => String(key || '').trim().toLowerCase() !== creatorNorm);
    const extraRecipientStaffKeys = (await requestWorkflowExtraRecipientStaffKeys(body))
      .filter((key) => String(key || '').trim().toLowerCase() !== creatorNorm);
    const results = await sendTaskWorkflowEmailToAssignees({
      taskRow,
      actorStaffKey: creatorRaw,
      actorReplyTo: creatorNotifyEmail || creatorEmail,
      recipientStaffKeys,
      extraRecipientStaffKeys,
      subject,
      intro:
        'This email is to inform you that the task submission has been accepted. The creator reviewed this task submission and accepted it.',
      detailLines,
      closing: 'Please review the accepted task in Project Tracker.',
      taskId,
    });
    const failed = results.find((x) => x.ok === false && !x.skipped);
    if (failed) {
      sendJson(req, res, 502, {
        error: failed.error || 'Failed to send notification email',
        detail: failed.detail || null,
        results,
      });
      return;
    }
    sendJson(req, res, 200, {
      ok: true,
      taskId,
      recipients: results.filter((x) => x.ok && !x.skipped).length,
      results,
    });
  } catch (e) {
    console.error('handleNotifyTaskAccepted:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * POST { taskId } — create_by only. To: creator and assignees. Task returned.
 */
async function handleNotifyTaskReturned(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!db) {
    sendJson(req, res, 503, { error: 'Database not configured' });
    return;
  }
  if (!EMAIL_SENDING_ENABLED) {
    notifyEmailSkippedResponse(req, res);
    return;
  }
  if (!outboundEmailConfigured()) {
    sendJson(req, res, 503, { error: 'Outbound email transport not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const taskId = (body.taskId || '').trim();
    if (!taskId) {
      sendJson(req, res, 400, { error: 'taskId required' });
      return;
    }
    const { data: taskRow, error: tErr } = await db
      .from('task')
      .select('*')
      .eq('id', taskId)
      .maybeSingle();
    if (tErr || !taskRow) {
      sendJson(req, res, 404, { error: 'Task not found' });
      return;
    }
    const creatorRaw = (taskRow.create_by || '').toString().trim();
    const { data: creatorStaff } = await fetchStaffRowForCreateBy(db, creatorRaw);
    if (!creatorStaff) {
      sendJson(req, res, 400, { error: 'Creator staff not found' });
      return;
    }
    const creatorEmail = (creatorStaff.email || '').trim().toLowerCase();
    const sessionEmail = (session.email || '').trim().toLowerCase();
    const creatorNotifyEmail = await resolveStaffEmailForNotifications(db, creatorStaff);
    const creatorAddr = (creatorNotifyEmail || creatorEmail).toLowerCase();
    if (!sessionEmail || sessionEmail !== creatorAddr) {
      sendJson(req, res, 403, {
        error:
          'Only the task creator (staff email must match signed-in user) can send return emails',
      });
      return;
    }
    const taskName = (taskRow.task_name || '').toString().trim() || '(no title)';
    const taskTitleForSubject = mailSubjectSingleLine(taskName).replace(/"/g, '');
    const subject = `[Project Tracker] Task Submission Returned: ${taskTitleForSubject}`;
    const detailLines = await buildTaskUpdateDetailLines(
      db,
      taskRow,
      workflowCompositeChangeMap(body.changes),
      { commentAddedText: body.commentAddedText },
    );
    const results = await sendTaskWorkflowEmailToAssignees({
      taskRow,
      actorStaffKey: creatorRaw,
      actorReplyTo: creatorNotifyEmail || creatorEmail,
      extraRecipientStaffKeys: await requestWorkflowExtraRecipientStaffKeys(body),
      subject,
      intro:
        'This email is to inform you that the task submission has been returned. The creator reviewed this task submission and returned it for revision.',
      detailLines,
      closing: 'Please review the returned task in Project Tracker.',
      taskId,
    });
    const failed = results.find((x) => x.ok === false && !x.skipped);
    if (failed) {
      sendJson(req, res, 502, {
        error: failed.error || 'Failed to send notification email',
        detail: failed.detail || null,
        results,
      });
      return;
    }
    sendJson(req, res, 200, {
      ok: true,
      taskId,
      recipients: results.filter((x) => x.ok && !x.skipped).length,
      results,
    });
  } catch (e) {
    console.error('handleNotifyTaskReturned:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * POST { subtaskId } — PIC only. To: creator and assignees. Submission for review.
 */
async function handleNotifySubtaskSubmission(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!db) {
    sendJson(req, res, 503, { error: 'Database not configured' });
    return;
  }
  if (!EMAIL_SENDING_ENABLED) {
    notifyEmailSkippedResponse(req, res);
    return;
  }
  if (!outboundEmailConfigured()) {
    sendJson(req, res, 503, { error: 'Outbound email transport not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const subtaskId = (body.subtaskId || '').trim();
    if (!subtaskId) {
      sendJson(req, res, 400, { error: 'subtaskId required' });
      return;
    }
    const { data: row, error: sErr } = await db
      .from('subtask')
      .select('*')
      .eq('id', subtaskId)
      .maybeSingle();
    if (sErr || !row) {
      sendJson(req, res, 404, { error: 'Sub-task not found' });
      return;
    }
    const picId = (row.pic || '').toString().trim();
    if (!picId) {
      sendJson(req, res, 400, { error: 'Sub-task has no PIC' });
      return;
    }
    const { data: picStaff, error: pErr } = await fetchStaffRowForCreateBy(
      db,
      picId,
    );
    if (pErr || !picStaff) {
      sendJson(req, res, 400, { error: 'PIC staff not found' });
      return;
    }
    const picEmail = (picStaff.email || '').trim().toLowerCase();
    const sessionEmail = (session.email || '').trim().toLowerCase();
    const picNotifyEmail = await resolveStaffEmailForNotifications(db, picStaff);
    const picAddr = (picNotifyEmail || picEmail).toLowerCase();
    if (!sessionEmail || sessionEmail !== picAddr) {
      sendJson(req, res, 403, {
        error:
          'Only the sub-task PIC (staff email must match signed-in user) can send submission emails',
      });
      return;
    }
    const creatorRaw = (row.create_by || '').toString().trim();
    const { data: creatorStaff } = await fetchStaffRowForCreateBy(db, creatorRaw);
    if (!creatorStaff) {
      sendJson(req, res, 400, { error: 'Creator staff not found' });
      return;
    }
    const subtaskName = (row.subtask_name || '').toString().trim() || '(no title)';
    const subtaskTitleForSubject = mailSubjectSingleLine(subtaskName).replace(/"/g, '');
    const subject = `[Project Tracker] Subtask Submitted for Review: ${subtaskTitleForSubject}`;
    const detailLines = await buildSubtaskUpdateDetailLines(
      db,
      row,
      workflowCompositeChangeMap(body.changes),
      { commentAddedText: body.commentAddedText },
    );
    const results = await sendSubtaskWorkflowEmailToAssignees({
      row,
      actorStaffKey: picId,
      actorReplyTo: picNotifyEmail || picEmail,
      recipientStaffKeys: [row.create_by],
      extraRecipientStaffKeys: await requestWorkflowExtraRecipientStaffKeys(body),
      subject,
      intro:
        'This email is to inform you that the subtask has been submitted for review. Please review the submitted work and make a judgement: accept or return.',
      detailLines,
      closing: 'Please review the submitted subtask in Project Tracker.',
      subtaskId,
    });
    const failed = results.find((x) => x.ok === false && !x.skipped);
    if (failed) {
      sendJson(req, res, 502, {
        error: failed.error || 'Failed to send notification email',
        detail: failed.detail || null,
        results,
      });
      return;
    }
    sendJson(req, res, 200, {
      ok: true,
      subtaskId,
      recipients: results.filter((x) => x.ok && !x.skipped).length,
      results,
    });
  } catch (e) {
    console.error('handleNotifySubtaskSubmission:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * POST { subtaskId } — create_by only. To: creator and assignees. Sub-task accepted.
 */
async function handleNotifySubtaskAccepted(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!db) {
    sendJson(req, res, 503, { error: 'Database not configured' });
    return;
  }
  if (!EMAIL_SENDING_ENABLED) {
    notifyEmailSkippedResponse(req, res);
    return;
  }
  if (!outboundEmailConfigured()) {
    sendJson(req, res, 503, { error: 'Outbound email transport not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const subtaskId = (body.subtaskId || '').trim();
    if (!subtaskId) {
      sendJson(req, res, 400, { error: 'subtaskId required' });
      return;
    }
    const { data: row, error: sErr } = await db
      .from('subtask')
      .select('*')
      .eq('id', subtaskId)
      .maybeSingle();
    if (sErr || !row) {
      sendJson(req, res, 404, { error: 'Sub-task not found' });
      return;
    }
    const creatorRaw = (row.create_by || '').toString().trim();
    const { data: creatorStaff } = await fetchStaffRowForCreateBy(db, creatorRaw);
    if (!creatorStaff) {
      sendJson(req, res, 400, { error: 'Creator staff not found' });
      return;
    }
    const creatorEmail = (creatorStaff.email || '').trim().toLowerCase();
    const sessionEmail = (session.email || '').trim().toLowerCase();
    const creatorNotifyEmail = await resolveStaffEmailForNotifications(db, creatorStaff);
    const creatorAddr = (creatorNotifyEmail || creatorEmail).toLowerCase();
    if (!sessionEmail || sessionEmail !== creatorAddr) {
      sendJson(req, res, 403, {
        error:
          'Only the sub-task creator (staff email must match signed-in user) can send acceptance emails',
      });
      return;
    }
    const subtaskName = (row.subtask_name || '').toString().trim() || '(no title)';
    const subtaskTitleForSubject = mailSubjectSingleLine(subtaskName).replace(/"/g, '');
    const subject = `[Project Tracker] Subtask Submission Accepted: ${subtaskTitleForSubject}`;
    const detailLines = await buildSubtaskUpdateDetailLines(
      db,
      row,
      workflowCompositeChangeMap(body.changes),
      { commentAddedText: body.commentAddedText },
    );
    const creatorNorm = creatorRaw.toLowerCase();
    const recipientStaffKeys = collectSubtaskAssigneeStaffIds(row)
      .filter((key) => String(key || '').trim().toLowerCase() !== creatorNorm);
    const extraRecipientStaffKeys = (await requestWorkflowExtraRecipientStaffKeys(body))
      .filter((key) => String(key || '').trim().toLowerCase() !== creatorNorm);
    const results = await sendSubtaskWorkflowEmailToAssignees({
      row,
      actorStaffKey: creatorRaw,
      actorReplyTo: creatorNotifyEmail || creatorEmail,
      recipientStaffKeys,
      extraRecipientStaffKeys,
      subject,
      intro:
        'This email is to inform you that the subtask submission has been accepted. The creator reviewed this subtask submission and accepted it.',
      detailLines,
      closing: 'Please review the accepted subtask in Project Tracker.',
      subtaskId,
    });
    const failed = results.find((x) => x.ok === false && !x.skipped);
    if (failed) {
      sendJson(req, res, 502, {
        error: failed.error || 'Failed to send notification email',
        detail: failed.detail || null,
        results,
      });
      return;
    }
    sendJson(req, res, 200, {
      ok: true,
      subtaskId,
      recipients: results.filter((x) => x.ok && !x.skipped).length,
      results,
    });
  } catch (e) {
    console.error('handleNotifySubtaskAccepted:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * POST { subtaskId } — create_by only. To: creator and assignees. Sub-task returned.
 */
async function handleNotifySubtaskReturned(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!db) {
    sendJson(req, res, 503, { error: 'Database not configured' });
    return;
  }
  if (!EMAIL_SENDING_ENABLED) {
    notifyEmailSkippedResponse(req, res);
    return;
  }
  if (!outboundEmailConfigured()) {
    sendJson(req, res, 503, { error: 'Outbound email transport not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const subtaskId = (body.subtaskId || '').trim();
    if (!subtaskId) {
      sendJson(req, res, 400, { error: 'subtaskId required' });
      return;
    }
    const { data: row, error: sErr } = await db
      .from('subtask')
      .select('*')
      .eq('id', subtaskId)
      .maybeSingle();
    if (sErr || !row) {
      sendJson(req, res, 404, { error: 'Sub-task not found' });
      return;
    }
    const creatorRaw = (row.create_by || '').toString().trim();
    const { data: creatorStaff } = await fetchStaffRowForCreateBy(db, creatorRaw);
    if (!creatorStaff) {
      sendJson(req, res, 400, { error: 'Creator staff not found' });
      return;
    }
    const creatorEmail = (creatorStaff.email || '').trim().toLowerCase();
    const sessionEmail = (session.email || '').trim().toLowerCase();
    const creatorNotifyEmail = await resolveStaffEmailForNotifications(db, creatorStaff);
    const creatorAddr = (creatorNotifyEmail || creatorEmail).toLowerCase();
    if (!sessionEmail || sessionEmail !== creatorAddr) {
      sendJson(req, res, 403, {
        error:
          'Only the sub-task creator (staff email must match signed-in user) can send return emails',
      });
      return;
    }
    const subtaskName = (row.subtask_name || '').toString().trim() || '(no title)';
    const subtaskTitleForSubject = mailSubjectSingleLine(subtaskName).replace(/"/g, '');
    const subject = `[Project Tracker] Subtask Submission Returned: ${subtaskTitleForSubject}`;
    const detailLines = await buildSubtaskUpdateDetailLines(
      db,
      row,
      workflowCompositeChangeMap(body.changes),
      { commentAddedText: body.commentAddedText },
    );
    const results = await sendSubtaskWorkflowEmailToAssignees({
      row,
      actorStaffKey: creatorRaw,
      actorReplyTo: creatorNotifyEmail || creatorEmail,
      extraRecipientStaffKeys: await requestWorkflowExtraRecipientStaffKeys(body),
      subject,
      intro:
        'This email is to inform you that the subtask submission has been returned. The creator reviewed this subtask submission and returned it for revision.',
      detailLines,
      closing: 'Please review the returned subtask in Project Tracker.',
      subtaskId,
    });
    const failed = results.find((x) => x.ok === false && !x.skipped);
    if (failed) {
      sendJson(req, res, 502, {
        error: failed.error || 'Failed to send notification email',
        detail: failed.detail || null,
        results,
      });
      return;
    }
    sendJson(req, res, 200, {
      ok: true,
      subtaskId,
      recipients: results.filter((x) => x.ok && !x.skipped).length,
      results,
    });
  } catch (e) {
    console.error('handleNotifySubtaskReturned:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

async function handleNotifyTaskUndoSubmissionDecision(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!db) {
    sendJson(req, res, 503, { error: 'Database not configured' });
    return;
  }
  if (!EMAIL_SENDING_ENABLED) {
    notifyEmailSkippedResponse(req, res);
    return;
  }
  if (!outboundEmailConfigured()) {
    sendJson(req, res, 503, { error: 'Outbound email transport not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const taskId = (body.taskId || '').trim();
    if (!taskId) {
      sendJson(req, res, 400, { error: 'taskId required' });
      return;
    }
    const { data: taskRow, error: tErr } = await db
      .from('task')
      .select('*')
      .eq('id', taskId)
      .maybeSingle();
    if (tErr || !taskRow) {
      sendJson(req, res, 404, { error: 'Task not found' });
      return;
    }
    const actorId = (taskRow.update_by || taskRow.create_by || '').toString().trim();
    const { data: actorStaff } = await fetchStaffRowForCreateBy(db, actorId);
    const sessionEmail = (session.email || '').trim().toLowerCase();
    const actorMatchesSession = await sessionEmailBelongsToStaffRow(db, actorStaff, sessionEmail);
    if (!actorMatchesSession) {
      sendJson(req, res, 403, {
        error: 'Only the user who performed the task undo can send undo emails',
      });
      return;
    }
    const actorReplyTo = (
      (await resolveStaffEmailForNotifications(db, actorStaff)) ||
      (actorStaff?.email || '').trim()
    ).trim();
    const taskName = (taskRow.task_name || '').toString().trim() || '(no title)';
    const subject = `[Project Tracker] Task Submission Decision Undone: ${mailSubjectSingleLine(taskName)}`;
    const changes = [];
    const oldStatus = String(body.oldStatus || '').trim();
    const newStatus = String(taskRow.status || '').trim();
    if (oldStatus && oldStatus !== newStatus) {
      changes.push({ field: 'status', oldValue: oldStatus, newValue: newStatus });
    }
    const oldSubmission = String(body.oldSubmission || '').trim();
    const newSubmission = String(taskRow.submission || '').trim();
    if (oldSubmission && oldSubmission !== newSubmission) {
      changes.push({ field: 'submission', oldValue: oldSubmission, newValue: newSubmission });
    }
    const detailLines = await buildTaskUpdateDetailLines(db, taskRow, workflowCompositeChangeMap(body.changes), {
      commentAddedText: body.commentAddedText,
    });
    const results = await sendTaskWorkflowEmailToAssignees({
      taskRow,
      actorStaffKey: actorId,
      actorReplyTo,
      extraRecipientStaffKeys: await requestWorkflowExtraRecipientStaffKeys(body),
      subject,
      intro:
        'This email is to inform you that the previous submission decision for this task has been undone. The task is now back to pending review.',
      detailLines,
      closing: 'Please review the task whose submission decision was undone in Project Tracker.',
      taskId,
    });
    const failed = results.find((x) => x.ok === false && !x.skipped);
    if (failed) {
      sendJson(req, res, 502, {
        error: failed.error || 'Failed to send notification email',
        detail: failed.detail || null,
        results,
      });
      return;
    }
    sendJson(req, res, 200, {
      ok: true,
      taskId,
      recipients: results.filter((x) => x.ok && !x.skipped).length,
      results,
    });
  } catch (e) {
    console.error('handleNotifyTaskUndoSubmissionDecision:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

async function handleNotifySubtaskUndoSubmissionDecision(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!db) {
    sendJson(req, res, 503, { error: 'Database not configured' });
    return;
  }
  if (!EMAIL_SENDING_ENABLED) {
    notifyEmailSkippedResponse(req, res);
    return;
  }
  if (!outboundEmailConfigured()) {
    sendJson(req, res, 503, { error: 'Outbound email transport not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const subtaskId = (body.subtaskId || '').trim();
    if (!subtaskId) {
      sendJson(req, res, 400, { error: 'subtaskId required' });
      return;
    }
    const { data: row, error: sErr } = await db
      .from('subtask')
      .select('*')
      .eq('id', subtaskId)
      .maybeSingle();
    if (sErr || !row) {
      sendJson(req, res, 404, { error: 'Subtask not found' });
      return;
    }
    const actorId = (row.update_by || row.create_by || '').toString().trim();
    const { data: actorStaff } = await fetchStaffRowForCreateBy(db, actorId);
    const sessionEmail = (session.email || '').trim().toLowerCase();
    const actorMatchesSession = await sessionEmailBelongsToStaffRow(db, actorStaff, sessionEmail);
    if (!actorMatchesSession) {
      sendJson(req, res, 403, {
        error: 'Only the user who performed the subtask undo can send undo emails',
      });
      return;
    }
    const actorReplyTo = (
      (await resolveStaffEmailForNotifications(db, actorStaff)) ||
      (actorStaff?.email || '').trim()
    ).trim();
    const subtaskName = (row.subtask_name || '').toString().trim() || '(no title)';
    const subject = `[Project Tracker] Subtask Submission Decision Undone: ${mailSubjectSingleLine(subtaskName)}`;
    const changes = [];
    const oldStatus = String(body.oldStatus || '').trim();
    const newStatus = String(row.status || '').trim();
    if (oldStatus && oldStatus !== newStatus) {
      changes.push({ field: 'status', oldValue: oldStatus, newValue: newStatus });
    }
    const oldSubmission = String(body.oldSubmission || '').trim();
    const newSubmission = String(row.submission || '').trim();
    if (oldSubmission && oldSubmission !== newSubmission) {
      changes.push({ field: 'submission', oldValue: oldSubmission, newValue: newSubmission });
    }
    const detailLines = await buildSubtaskUpdateDetailLines(db, row, workflowCompositeChangeMap(body.changes), {
      commentAddedText: body.commentAddedText,
    });
    const results = await sendSubtaskWorkflowEmailToAssignees({
      row,
      actorStaffKey: actorId,
      actorReplyTo,
      extraRecipientStaffKeys: await requestWorkflowExtraRecipientStaffKeys(body),
      subject,
      intro:
        'This email is to inform you that the previous submission decision for this subtask has been undone. The subtask is now back to pending review.',
      detailLines,
      closing: 'Please review the subtask whose submission decision was undone in Project Tracker.',
      subtaskId,
    });
    const failed = results.find((x) => x.ok === false && !x.skipped);
    if (failed) {
      sendJson(req, res, 502, {
        error: failed.error || 'Failed to send notification email',
        detail: failed.detail || null,
        results,
      });
      return;
    }
    sendJson(req, res, 200, {
      ok: true,
      subtaskId,
      recipients: results.filter((x) => x.ok && !x.skipped).length,
      results,
    });
  } catch (e) {
    console.error('handleNotifySubtaskUndoSubmissionDecision:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

const TASK_ACTION_EMAIL = {
  deleted: {
    subject: 'Deleted',
    intro:
      'This email is to inform you that the task has been deleted. This task is removed from the active list.',
    closing: 'Please review the deleted task in Project Tracker.',
  },
  restored: {
    subject: 'Restored',
    intro:
      'This email is to inform you that the task has been restored. This deleted task is brought back to the active list.',
    closing: 'Please review the restored task in Project Tracker.',
  },
  paused: {
    subject: 'Paused',
    intro:
      'This email is to inform you that the task has been paused. Work on this task is temporarily suspended.',
    closing: 'Please review the paused task in Project Tracker.',
  },
  resumed: {
    subject: 'Resumed',
    intro:
      'This email is to inform you that the task has been resumed. Work on this task continues after being paused.',
    closing: 'Please review the resumed task in Project Tracker.',
  },
};

const SUBTASK_ACTION_EMAIL = {
  deleted: {
    subject: 'Deleted',
    intro:
      'This email is to inform you that the subtask has been deleted. This subtask is removed from the active list.',
    closing: 'Please review the deleted subtask in Project Tracker.',
  },
  restored: {
    subject: 'Restored',
    intro:
      'This email is to inform you that the subtask has been restored. This deleted subtask is brought back to the active list.',
    closing: 'Please review the restored subtask in Project Tracker.',
  },
  paused: {
    subject: 'Paused',
    intro:
      'This email is to inform you that the subtask has been paused. Work on this subtask is temporarily suspended.',
    closing: 'Please review the paused subtask in Project Tracker.',
  },
  resumed: {
    subject: 'Resumed',
    intro:
      'This email is to inform you that the subtask has been resumed. Work on this subtask continues after being paused.',
    closing: 'Please review the resumed subtask in Project Tracker.',
  },
};

async function handleNotifyTaskAction(req, res, action) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const cfg = TASK_ACTION_EMAIL[action];
  if (!cfg) {
    sendJson(req, res, 400, { error: 'Unknown task action' });
    return;
  }
  const session = await verifyFirebaseToken(req);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!db) {
    sendJson(req, res, 503, { error: 'Database not configured' });
    return;
  }
  if (!EMAIL_SENDING_ENABLED) {
    notifyEmailSkippedResponse(req, res);
    return;
  }
  if (!outboundEmailConfigured()) {
    sendJson(req, res, 503, { error: 'Outbound email transport not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const taskId = (body.taskId || '').trim();
    if (!taskId) {
      sendJson(req, res, 400, { error: 'taskId required' });
      return;
    }
    const { data: taskRow, error: tErr } = await db
      .from('task')
      .select('*')
      .eq('id', taskId)
      .maybeSingle();
    if (tErr || !taskRow) {
      sendJson(req, res, 404, { error: 'Task not found' });
      return;
    }
    const actorId = (taskRow.update_by || taskRow.create_by || '').toString().trim();
    const { data: actorStaff } = await fetchStaffRowForCreateBy(db, actorId);
    const sessionEmail = (session.email || '').trim().toLowerCase();
    const actorMatchesSession = await sessionEmailBelongsToStaffRow(db, actorStaff, sessionEmail);
    if (!actorMatchesSession) {
      sendJson(req, res, 403, {
        error: 'Only the user who performed the task action can send action emails',
      });
      return;
    }
    const actorReplyTo = (
      (await resolveStaffEmailForNotifications(db, actorStaff)) ||
      (actorStaff?.email || '').trim()
    ).trim();
    const taskName = (taskRow.task_name || '').toString().trim() || '(no title)';
    const subject = `[Project Tracker] Task ${cfg.subject}: ${mailSubjectSingleLine(taskName)}`;
    const detailLines = await buildTaskUpdateDetailLines(
      db,
      taskRow,
      workflowCompositeChangeMap(body.changes),
      { commentAddedText: body.commentAddedText },
    );
    const recipientByNorm = buildTaskUpdatedDefaultRecipientStaffIds(taskRow);
    mergeRecipientStaffKeys(recipientByNorm, await requestWorkflowExtraRecipientStaffKeys(body));
    mergeRecipientStaffKeys(
      recipientByNorm,
      await assigneeStaffKeysFromChange(db, emailChangeMap(body.changes)),
    );
    const results = [];
    for (const staffUuid of recipientByNorm.values()) {
      const { data: s } = await fetchStaffRowForCreateBy(db, staffUuid);
      const to = await resolveStaffEmailForNotifications(db, s);
      if (!to) {
        results.push({ staffId: staffUuid, ok: false, skipped: 'no email on staff row' });
        continue;
      }
      const recipientName = staffDisplayName(s, to);
      const html = `<div style="margin:0;font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;line-height:1.5;color:#000000;">Dear ${escapeHtml(recipientName)},<br><br>
${escapeHtml(cfg.intro)}<br><br>
${detailLines.html}<br><br>
${escapeHtml(cfg.closing)} ${eventTaskLinkHtml(taskId)}<br><br>
${projectTrackerEmailFooterHtml()}</div>`;
      const text = `Dear ${recipientName},

${cfg.intro}

${detailLines.text}

${cfg.closing} ${eventTaskLinkText(taskId)}

${projectTrackerEmailFooterText()}`;
      const r = await sendNotificationEmail({
        to,
        subject,
        text,
        html,
        from: NOTIFICATION_EMAIL_FROM,
        replyTo: actorReplyTo || sessionEmail || undefined,
      });
      results.push({
        to,
        ok: r.ok,
        messageId: r.ok ? r.id : null,
        error: r.ok ? null : r.error,
        detail: r.ok ? null : r.detail,
      });
    }
    sendJson(req, res, 200, {
      ok: true,
      taskId,
      action,
      recipients: results.filter((x) => x.ok && !x.skipped).length,
      results,
    });
  } catch (e) {
    console.error('handleNotifyTaskAction:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

async function handleNotifySubtaskAction(req, res, action) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const cfg = SUBTASK_ACTION_EMAIL[action];
  if (!cfg) {
    sendJson(req, res, 400, { error: 'Unknown subtask action' });
    return;
  }
  const session = await verifyFirebaseToken(req);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!db) {
    sendJson(req, res, 503, { error: 'Database not configured' });
    return;
  }
  if (!EMAIL_SENDING_ENABLED) {
    notifyEmailSkippedResponse(req, res);
    return;
  }
  if (!outboundEmailConfigured()) {
    sendJson(req, res, 503, { error: 'Outbound email transport not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const subtaskId = (body.subtaskId || '').trim();
    if (!subtaskId) {
      sendJson(req, res, 400, { error: 'subtaskId required' });
      return;
    }
    const { data: row, error: sErr } = await db
      .from('subtask')
      .select('*')
      .eq('id', subtaskId)
      .maybeSingle();
    if (sErr || !row) {
      sendJson(req, res, 404, { error: 'Subtask not found' });
      return;
    }
    const actorId = (row.update_by || row.create_by || '').toString().trim();
    const { data: actorStaff } = await fetchStaffRowForCreateBy(db, actorId);
    const sessionEmail = (session.email || '').trim().toLowerCase();
    const actorMatchesSession = await sessionEmailBelongsToStaffRow(db, actorStaff, sessionEmail);
    if (!actorMatchesSession) {
      sendJson(req, res, 403, {
        error: 'Only the user who performed the subtask action can send action emails',
      });
      return;
    }
    const actorReplyTo = (
      (await resolveStaffEmailForNotifications(db, actorStaff)) ||
      (actorStaff?.email || '').trim()
    ).trim();
    const subtaskName = (row.subtask_name || '').toString().trim() || '(no title)';
    const subject = `[Project Tracker] Subtask ${cfg.subject}: ${mailSubjectSingleLine(subtaskName)}`;
    const detailLines = await buildSubtaskUpdateDetailLines(
      db,
      row,
      workflowCompositeChangeMap(body.changes),
      { commentAddedText: body.commentAddedText },
    );
    const recipientByNorm = buildTaskUpdatedDefaultRecipientStaffIds(row);
    mergeRecipientStaffKeys(recipientByNorm, await requestWorkflowExtraRecipientStaffKeys(body));
    mergeRecipientStaffKeys(
      recipientByNorm,
      await assigneeStaffKeysFromChange(db, emailChangeMap(body.changes)),
    );
    const results = [];
    for (const staffUuid of recipientByNorm.values()) {
      const { data: s } = await fetchStaffRowForCreateBy(db, staffUuid);
      const to = await resolveStaffEmailForNotifications(db, s);
      if (!to) {
        results.push({ staffId: staffUuid, ok: false, skipped: 'no email on staff row' });
        continue;
      }
      const recipientName = staffDisplayName(s, to);
      const html = `<div style="margin:0;font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;line-height:1.5;color:#000000;">Dear ${escapeHtml(recipientName)},<br><br>
${escapeHtml(cfg.intro)}<br><br>
${detailLines.html}<br><br>
${escapeHtml(cfg.closing)} ${eventSubtaskLinkHtml(subtaskId)}<br><br>
${projectTrackerEmailFooterHtml()}</div>`;
      const text = `Dear ${recipientName},

${cfg.intro}

${detailLines.text}

${cfg.closing} ${eventSubtaskLinkText(subtaskId)}

${projectTrackerEmailFooterText()}`;
      const r = await sendNotificationEmail({
        to,
        subject,
        text,
        html,
        from: NOTIFICATION_EMAIL_FROM,
        replyTo: actorReplyTo || sessionEmail || undefined,
      });
      results.push({
        to,
        ok: r.ok,
        messageId: r.ok ? r.id : null,
        error: r.ok ? null : r.error,
        detail: r.ok ? null : r.detail,
      });
    }
    sendJson(req, res, 200, {
      ok: true,
      subtaskId,
      action,
      recipients: results.filter((x) => x.ok && !x.skipped).length,
      results,
    });
  } catch (e) {
    console.error('handleNotifySubtaskAction:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') {
    applyCors(req, res, 204);
    res.end();
    return;
  }

  const url = new URL(req.url || '/', `http://${req.headers.host}`);
  const path = url.pathname;

  if (path === '/api/me' && req.method === 'GET') {
    await handleApiMe(req, res);
    return;
  }
  if (path === '/api/assignable-staff' && req.method === 'GET') {
    await handleApiAssignableStaff(req, res);
    return;
  }
  if (path === '/api/teams' && req.method === 'GET') {
    await handleApiTeams(req, res);
    return;
  }
  if (path === '/api/staff' && req.method === 'GET') {
    await handleApiStaff(req, res);
    return;
  }
  if (path === '/api/llm/chat/completions' && req.method === 'POST') {
    await handleLlmChatCompletionsProxy(req, res);
    return;
  }
  if (path === '/api/admin/snapshot' && req.method === 'GET') {
    await handleAdminSnapshot(req, res);
    return;
  }
  if (path === '/api/admin/user' && req.method === 'POST') {
    await handleAdminUpsertUser(req, res);
    return;
  }
  if (path.startsWith('/api/admin/user/') && req.method === 'DELETE') {
    await handleAdminDeleteUser(req, res);
    return;
  }
  if (path === '/api/admin/team' && req.method === 'POST') {
    await handleAdminUpsertTeam(req, res);
    return;
  }
  if (path === '/api/admin/team-member' && req.method === 'POST') {
    await handleAdminTeamMember(req, res);
    return;
  }
  if (path === '/api/admin/subordinate' && req.method === 'POST') {
    await handleAdminSubordinate(req, res);
    return;
  }
  if (path === '/api/admin/test-email' && req.method === 'POST') {
    await handleAdminTestEmail(req, res);
    return;
  }
  if (path === '/api/admin/test-smtp' && req.method === 'POST') {
    await handleAdminTestSmtp(req, res);
    return;
  }
  if (path === '/api/test-smtp' && req.method === 'POST') {
    await handleTestSmtp(req, res);
    return;
  }
  if (path === '/api/notify/task-assigned' && req.method === 'POST') {
    await handleNotifyTaskAssigned(req, res);
    return;
  }
  if (path === '/api/notify/subtask-assigned' && req.method === 'POST') {
    await handleNotifySubtaskAssigned(req, res);
    return;
  }
  if (path === '/api/notify/project-assigned' && req.method === 'POST') {
    await handleNotifyProjectAssigned(req, res);
    return;
  }
  if (path === '/api/notify/project-updated' && req.method === 'POST') {
    await handleNotifyProjectUpdated(req, res);
    return;
  }
  if (path === '/api/notify/task-comment' && req.method === 'POST') {
    await handleNotifyTaskComment(req, res);
    return;
  }
  if (path === '/api/notify/task-comment-edited' && req.method === 'POST') {
    await handleNotifyTaskEditedComment(req, res);
    return;
  }
  if (path === '/api/notify/subtask-comment' && req.method === 'POST') {
    await handleNotifySubtaskComment(req, res);
    return;
  }
  if (path === '/api/notify/subtask-comment-edited' && req.method === 'POST') {
    await handleNotifySubtaskEditedComment(req, res);
    return;
  }
  if (path === '/api/notify/task-updated' && req.method === 'POST') {
    await handleNotifyTaskUpdated(req, res);
    return;
  }
  if (path === '/api/notify/subtask-updated' && req.method === 'POST') {
    await handleNotifySubtaskUpdated(req, res);
    return;
  }
  if (path === '/api/notify/task-submission' && req.method === 'POST') {
    await handleNotifyTaskSubmission(req, res);
    return;
  }
  if (path === '/api/notify/task-accepted' && req.method === 'POST') {
    await handleNotifyTaskAccepted(req, res);
    return;
  }
  if (path === '/api/notify/task-returned' && req.method === 'POST') {
    await handleNotifyTaskReturned(req, res);
    return;
  }
  if (path === '/api/notify/task-undo' && req.method === 'POST') {
    await handleNotifyTaskUndoSubmissionDecision(req, res);
    return;
  }
  if (path === '/api/notify/task-deleted' && req.method === 'POST') {
    await handleNotifyTaskAction(req, res, 'deleted');
    return;
  }
  if (path === '/api/notify/task-restored' && req.method === 'POST') {
    await handleNotifyTaskAction(req, res, 'restored');
    return;
  }
  if (path === '/api/notify/task-paused' && req.method === 'POST') {
    await handleNotifyTaskAction(req, res, 'paused');
    return;
  }
  if (path === '/api/notify/task-resumed' && req.method === 'POST') {
    await handleNotifyTaskAction(req, res, 'resumed');
    return;
  }
  if (path === '/api/notify/subtask-submission' && req.method === 'POST') {
    await handleNotifySubtaskSubmission(req, res);
    return;
  }
  if (path === '/api/notify/subtask-accepted' && req.method === 'POST') {
    await handleNotifySubtaskAccepted(req, res);
    return;
  }
  if (path === '/api/notify/subtask-returned' && req.method === 'POST') {
    await handleNotifySubtaskReturned(req, res);
    return;
  }
  if (path === '/api/notify/subtask-undo' && req.method === 'POST') {
    await handleNotifySubtaskUndoSubmissionDecision(req, res);
    return;
  }
  if (path === '/api/notify/subtask-deleted' && req.method === 'POST') {
    await handleNotifySubtaskAction(req, res, 'deleted');
    return;
  }
  if (path === '/api/notify/subtask-restored' && req.method === 'POST') {
    await handleNotifySubtaskAction(req, res, 'restored');
    return;
  }
  if (path === '/api/notify/subtask-paused' && req.method === 'POST') {
    await handleNotifySubtaskAction(req, res, 'paused');
    return;
  }
  if (path === '/api/notify/subtask-resumed' && req.method === 'POST') {
    await handleNotifySubtaskAction(req, res, 'resumed');
    return;
  }
  if (path === '/api/cron/urgent-task-reminders' && req.method === 'POST') {
    await handleCronUrgentTaskReminders(req, res);
    return;
  }
  if (path === '/api/cron/due-today-reminders' && req.method === 'POST') {
    await handleCronDueTodayOnly(req, res);
    return;
  }
  if (path === '/api/cron/pic-overdue-reminders' && req.method === 'POST') {
    await handleCronPicOverdueReminders(req, res);
    return;
  }
  if (path === '/api/cron/creator-overdue-reminders' && req.method === 'POST') {
    await handleCronCreatorOverdueReminders(req, res);
    return;
  }
  if (path === '/api/cron/daily-reminders' && req.method === 'POST') {
    await handleCronDailyReminder(req, res);
    return;
  }
  if (path === '/api/files/upload' && req.method === 'POST') {
    await localFiles.handleLocalFileUpload(req, res, sendJson, applyCors);
    return;
  }
  if (path.startsWith('/api/files/')) {
    await localFiles.handleLocalFileDownload(req, res, applyCors);
    return;
  }
  if (path === '/auth/login' && req.method === 'GET') {
    await oidcAuth.handleAuthLogin(req, res);
    return;
  }
  if (path === '/auth/callback' && req.method === 'POST') {
    await oidcAuth.handleAuthCallback(req, res, sendJson, readBody);
    return;
  }
  if (path === '/auth/session' && req.method === 'GET') {
    await oidcAuth.handleAuthSession(req, res, sendJson);
    return;
  }
  if (path === '/auth/logout' && req.method === 'GET') {
    await oidcAuth.handleAuthLogout(req, res);
    return;
  }
  if (path === '/health' || path === '/') {
    await handleHealth(req, res);
    return;
  }

  sendJson(req, res, 404, { error: 'Not found' });
});

server.listen(PORT, () => {
  console.log(`Server running at http://localhost:${PORT}`);
  console.log(
    `Firebase Admin: ${firebaseAdmin ? 'ok' : 'missing FIREBASE_SERVICE_ACCOUNT_JSON'}`,
  );
  console.log(
    `Postgres: ${db ? 'ok' : 'missing DATABASE_URL or Postgres pool'}`,
  );
  console.log(
    `Postgres: ${pgPool ? 'pool ok' : DATABASE_URL ? 'pool failed' : 'DATABASE_URL not set'}`,
  );
  console.log(
    `HKU SSO: ${oidcAuth.isConfigured() ? `enabled (issuer ${process.env.SSO_ISSUER_URL || ''})` : 'not configured (set SSO_* in .env)'}`,
  );
  console.log(
    `Email sending: ${EMAIL_SENDING_ENABLED ? 'enabled' : 'disabled (EMAIL_SENDING_ENABLED=false)'}`,
  );
  console.log(
    `SMTP: ${smtpMail.isSmtpConfigured() ? JSON.stringify(smtpMail.smtpConfigSummary()) : 'not configured'}`,
  );
  if (process.env.DAILY_REMINDER_CRON_ENABLED === 'true') {
    cron.schedule(
      '0 9 * * *',
      () => {
        runCombinedDailyReminderJob().catch((e) =>
          console.error('daily combined reminder cron:', e),
        );
      },
      { timezone: 'Asia/Hong_Kong' },
    );
    console.log(
      'Combined daily reminders at 09:00 Asia/Hong_Kong (DAILY_REMINDER_CRON_ENABLED=true)',
    );
  }
});
