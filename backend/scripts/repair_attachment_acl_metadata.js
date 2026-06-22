/**
 * Repairs Firebase Storage ACL metadata for existing Supabase file_attachment rows.
 *
 * Usage from backend/:
 *   node scripts/repair_attachment_acl_metadata.js --dry-run
 *   node scripts/repair_attachment_acl_metadata.js
 *
 * Required env in backend/.env:
 *   SUPABASE_URL
 *   SUPABASE_SERVICE_ROLE_KEY
 *   FIREBASE_SERVICE_ACCOUNT_JSON
 * Optional:
 *   FIREBASE_STORAGE_BUCKET
 */
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const { createClient } = require('@supabase/supabase-js');
const firebaseAdmin = require('firebase-admin');

const SUPABASE_URL = (process.env.SUPABASE_URL || '').trim();
const SUPABASE_SERVICE_ROLE_KEY = (process.env.SUPABASE_SERVICE_ROLE_KEY || '').trim();
const FIREBASE_SERVICE_ACCOUNT_JSON = process.env.FIREBASE_SERVICE_ACCOUNT_JSON || '';
const DRY_RUN = process.argv.includes('--dry-run');
const PAGE_SIZE = 500;

function requireEnv() {
  const missing = [];
  if (!SUPABASE_URL) missing.push('SUPABASE_URL');
  if (!SUPABASE_SERVICE_ROLE_KEY) missing.push('SUPABASE_SERVICE_ROLE_KEY');
  if (!FIREBASE_SERVICE_ACCOUNT_JSON) missing.push('FIREBASE_SERVICE_ACCOUNT_JSON');
  if (missing.length) {
    throw new Error(`Missing env: ${missing.join(', ')}`);
  }
}

function getFirebaseStorageBucketName(serviceAccount) {
  const fromEnv = (process.env.FIREBASE_STORAGE_BUCKET || '').trim();
  if (fromEnv) return fromEnv;
  if (serviceAccount.project_id) return `${serviceAccount.project_id}.firebasestorage.app`;
  return '';
}

function objectPathFromStorageUrl(rawUrl) {
  let uri;
  try {
    uri = new URL(String(rawUrl || '').trim());
  } catch (_) {
    return '';
  }
  if (uri.hostname.toLowerCase() !== 'firebasestorage.googleapis.com') return '';
  const marker = '/o/';
  const idx = uri.pathname.indexOf(marker);
  if (idx < 0) return '';
  const encoded = uri.pathname.slice(idx + marker.length);
  try {
    return decodeURIComponent(encoded).replace(/^\/+/, '');
  } catch (_) {
    return '';
  }
}

function normalizeStorageObjectPath(rawPath) {
  const path = String(rawPath || '').trim().replace(/^\/+/, '');
  if (!path) return '';
  if (isAllowedAttachmentPath(path)) return path;
  try {
    const decoded = decodeURIComponent(path).replace(/^\/+/, '');
    if (isAllowedAttachmentPath(decoded)) return decoded;
  } catch (_) {}
  return path;
}

function isAllowedAttachmentPath(path) {
  return /^project_tracker\/users\/[^/]+\/(project_attachments|task_attachments|subtask_attachments)\/[^/]+\/.+$/i.test(
    String(path || '').trim(),
  );
}

function chunk(values, size) {
  const out = [];
  for (let i = 0; i < values.length; i += size) out.push(values.slice(i, i + size));
  return out;
}

function addKey(out, seen, raw, staffIdToAppId) {
  const key = String(raw || '').trim();
  if (!key) return;
  const appId = staffIdToAppId.get(key) || key;
  const normalized = String(appId || '').trim();
  if (!normalized || seen.has(normalized)) return;
  seen.add(normalized);
  out.push(normalized);
}

function aclKeysForOwner(row, staffIdToAppId) {
  const keys = [];
  const seen = new Set();
  for (let i = 1; i <= 10; i++) {
    addKey(keys, seen, row[`assignee_${String(i).padStart(2, '0')}`], staffIdToAppId);
  }
  addKey(keys, seen, row.pic, staffIdToAppId);
  addKey(keys, seen, row.create_by, staffIdToAppId);
  addKey(keys, seen, row.created_by, staffIdToAppId);
  return keys.slice(0, 10);
}

function metadataFromKeys(keys, existingMetadata) {
  const next = { ...(existingMetadata || {}) };
  for (let i = 0; i < 10; i++) delete next[`m${i}`];
  keys.forEach((key, index) => {
    next[`m${index}`] = key;
  });
  return next;
}

async function fetchAllActiveFileAttachments(supabase) {
  const rows = [];
  for (let from = 0; ; from += PAGE_SIZE) {
    const to = from + PAGE_SIZE - 1;
    const { data, error } = await supabase
      .from('file_attachment')
      .select('id,entity_type,entity_id,url,storage_path,created_by,status')
      .eq('status', 'Active')
      .range(from, to);
    if (error) throw error;
    rows.push(...(data || []));
    if (!data || data.length < PAGE_SIZE) break;
  }
  return rows;
}

async function fetchRowsByIds(supabase, table, ids, select) {
  const out = new Map();
  for (const part of chunk(ids, 200)) {
    if (!part.length) continue;
    const { data, error } = await supabase.from(table).select(select).in('id', part);
    if (error) throw error;
    for (const row of data || []) {
      const id = String(row.id || '').trim();
      if (id) out.set(id, row);
    }
  }
  return out;
}

async function main() {
  requireEnv();
  const serviceAccount = JSON.parse(FIREBASE_SERVICE_ACCOUNT_JSON);
  const bucketName = getFirebaseStorageBucketName(serviceAccount);
  if (!bucketName) throw new Error('Missing FIREBASE_STORAGE_BUCKET or service account project_id');

  firebaseAdmin.initializeApp({
    credential: firebaseAdmin.credential.cert(serviceAccount),
  });

  const bucket = firebaseAdmin.storage().bucket(bucketName);
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const [attachments, staffRes] = await Promise.all([
    fetchAllActiveFileAttachments(supabase),
    supabase.from('staff').select('id,app_id'),
  ]);
  if (staffRes.error) throw staffRes.error;

  const staffIdToAppId = new Map();
  for (const staff of staffRes.data || []) {
    const id = String(staff.id || '').trim();
    const appId = String(staff.app_id || '').trim();
    if (id && appId) staffIdToAppId.set(id, appId);
  }

  const taskIds = [
    ...new Set(
      attachments
        .filter((r) => String(r.entity_type || '').trim().toLowerCase() === 'task')
        .map((r) => String(r.entity_id || '').trim())
        .filter(Boolean),
    ),
  ];
  const subtaskIds = [
    ...new Set(
      attachments
        .filter((r) => String(r.entity_type || '').trim().toLowerCase() === 'subtask')
        .map((r) => String(r.entity_id || '').trim())
        .filter(Boolean),
    ),
  ];

  const ownerSelect =
    'id,create_by,pic,assignee_01,assignee_02,assignee_03,assignee_04,assignee_05,assignee_06,assignee_07,assignee_08,assignee_09,assignee_10';
  const [tasks, subtasks] = await Promise.all([
    fetchRowsByIds(supabase, 'task', taskIds, ownerSelect),
    fetchRowsByIds(supabase, 'subtask', subtaskIds, ownerSelect),
  ]);

  const summary = {
    total: attachments.length,
    patched: 0,
    unchanged: 0,
    skipped: 0,
    errors: 0,
  };

  for (const attachment of attachments) {
    const id = String(attachment.id || '').trim();
    const entityType = String(attachment.entity_type || '').trim().toLowerCase();
    const entityId = String(attachment.entity_id || '').trim();
    const owner = entityType === 'task' ? tasks.get(entityId) : subtasks.get(entityId);
    if (!id || !owner) {
      summary.skipped++;
      console.log(`skip ${id || '(no id)'}: owner not found (${entityType}:${entityId})`);
      continue;
    }

    const objectPath =
      normalizeStorageObjectPath(attachment.storage_path) ||
      objectPathFromStorageUrl(attachment.url);
    if (!isAllowedAttachmentPath(objectPath)) {
      summary.skipped++;
      console.log(`skip ${id}: invalid storage path ${objectPath || '(empty)'}`);
      continue;
    }

    const keys = aclKeysForOwner({ ...owner, created_by: attachment.created_by }, staffIdToAppId);
    if (!keys.length) {
      summary.skipped++;
      console.log(`skip ${id}: no ACL keys resolved`);
      continue;
    }

    try {
      const file = bucket.file(objectPath);
      const [metadata] = await file.getMetadata();
      const existingCustom = metadata.metadata || {};
      const nextCustom = metadataFromKeys(keys, existingCustom);
      const same = keys.every((key, index) => existingCustom[`m${index}`] === key);
      if (same) {
        summary.unchanged++;
        continue;
      }
      if (DRY_RUN) {
        summary.patched++;
        console.log(`dry-run patch ${id}: ${objectPath} -> ${keys.join(', ')}`);
      } else {
        await file.setMetadata({ metadata: nextCustom });
        summary.patched++;
        console.log(`patched ${id}: ${objectPath} -> ${keys.join(', ')}`);
      }
    } catch (e) {
      summary.errors++;
      console.error(`error ${id}: ${e.message}`);
    }
  }

  console.log(
    `${DRY_RUN ? 'Dry run' : 'Repair'} complete: total=${summary.total}, patched=${summary.patched}, unchanged=${summary.unchanged}, skipped=${summary.skipped}, errors=${summary.errors}`,
  );
  if (summary.errors > 0) process.exitCode = 1;
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
