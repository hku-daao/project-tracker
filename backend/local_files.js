const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

function getUploadDir() {
  return (process.env.UPLOAD_DIR || path.join(__dirname, '..', 'data', 'uploads')).trim();
}

function ensureUploadDir() {
  const dir = getUploadDir();
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

function sanitizeSegment(value) {
  return String(value || '')
    .trim()
    .replace(/[^a-zA-Z0-9._-]+/g, '_')
    .slice(0, 180);
}

function buildRelativePath(entityType, entityId, originalName) {
  const ext = path.extname(originalName || '').toLowerCase().slice(0, 12);
  const id = crypto.randomUUID();
  const type = sanitizeSegment(entityType);
  const entity = sanitizeSegment(entityId);
  return `${type}/${entity}/${id}${ext}`;
}

function resolveStoredFile(relativePath) {
  const root = path.resolve(ensureUploadDir());
  const target = path.resolve(root, relativePath.replace(/^\/+/, ''));
  if (!target.startsWith(root + path.sep) && target !== root) {
    return null;
  }
  return target;
}

function publicFileUrl(relativePath, req) {
  const base = (process.env.PUBLIC_API_BASE_URL || '').trim();
  if (base) {
    return `${base.replace(/\/+$/, '')}/api/files/${relativePath.replace(/\\/g, '/')}`;
  }
  const hostPort =
    process.env.HOST_BACKEND_PORT ||
    process.env.PORT ||
    '';
  const host =
    req.headers.host ||
    (hostPort ? `127.0.0.1:${hostPort}` : '127.0.0.1');
  const proto = (req.headers['x-forwarded-proto'] || 'http').split(',')[0].trim();
  return `${proto}://${host}/api/files/${relativePath.replace(/\\/g, '/')}`;
}

function contentTypeForFilename(name) {
  const n = String(name || '').toLowerCase();
  if (n.endsWith('.pdf')) return 'application/pdf';
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
  if (n.endsWith('.gif')) return 'image/gif';
  if (n.endsWith('.webp')) return 'image/webp';
  if (n.endsWith('.txt')) return 'text/plain';
  if (n.endsWith('.csv')) return 'text/csv';
  if (n.endsWith('.json')) return 'application/json';
  if (n.endsWith('.zip')) return 'application/zip';
  return 'application/octet-stream';
}

function parseMultipart(buffer, boundary) {
  const parts = [];
  const delim = Buffer.from(`--${boundary}`);
  let start = buffer.indexOf(delim);
  while (start >= 0) {
    const next = buffer.indexOf(delim, start + delim.length);
    if (next < 0) break;
    const chunk = buffer.slice(start + delim.length, next);
    const headerEnd = chunk.indexOf('\r\n\r\n');
    if (headerEnd >= 0) {
      const headerText = chunk.slice(0, headerEnd).toString('utf8');
      let body = chunk.slice(headerEnd + 4);
      if (body.slice(-2).equals(Buffer.from('\r\n'))) {
        body = body.slice(0, -2);
      }
      const nameMatch = headerText.match(/name="([^"]+)"/);
      const fileMatch = headerText.match(/filename="([^"]*)"/);
      parts.push({
        name: nameMatch ? nameMatch[1] : '',
        filename: fileMatch ? fileMatch[1] : null,
        body,
      });
    }
    start = next;
  }
  return parts;
}

async function readRawBody(req, limitBytes = 55 * 1024 * 1024) {
  const chunks = [];
  let total = 0;
  for await (const chunk of req) {
    total += chunk.length;
    if (total > limitBytes) {
      throw new Error('Payload too large');
    }
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

async function handleLocalFileUpload(req, res, sendJson, applyCors) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const contentType = String(req.headers['content-type'] || '');
  const boundaryMatch = contentType.match(/boundary=(.+)$/i);
  if (!boundaryMatch) {
    sendJson(req, res, 400, { error: 'Expected multipart/form-data' });
    return;
  }
  try {
    const raw = await readRawBody(req);
    const parts = parseMultipart(raw, boundaryMatch[1].trim());
    const fields = {};
    let filePart = null;
    for (const part of parts) {
      if (part.filename != null) {
        filePart = part;
      } else if (part.name) {
        fields[part.name] = part.body.toString('utf8');
      }
    }
    if (!filePart || !filePart.body?.length) {
      sendJson(req, res, 400, { error: 'Missing file' });
      return;
    }
    const entityType = fields.entity_type || fields.entityType || 'task';
    const entityId = fields.entity_id || fields.entityId || '';
    if (!entityId.trim()) {
      sendJson(req, res, 400, { error: 'entity_id required' });
      return;
    }
    const originalName = (filePart.filename || 'attachment').trim() || 'attachment';
    const relativePath = buildRelativePath(entityType, entityId, originalName);
    const abs = resolveStoredFile(relativePath);
    if (!abs) {
      sendJson(req, res, 400, { error: 'Invalid storage path' });
      return;
    }
    fs.mkdirSync(path.dirname(abs), { recursive: true });
    fs.writeFileSync(abs, filePart.body);
    sendJson(req, res, 200, {
      ok: true,
      url: publicFileUrl(relativePath, req),
      storage_path: relativePath.replace(/\\/g, '/'),
      filename: originalName,
      mime_type: contentTypeForFilename(originalName),
      file_size_bytes: filePart.body.length,
    });
  } catch (e) {
    sendJson(req, res, 500, { error: e.message || 'Upload failed' });
  }
}

async function handleLocalFileDownload(req, res, applyCors) {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    applyCors(req, res, 405, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Method not allowed' }));
    return;
  }
  const prefix = '/api/files/';
  const urlPath = req.url.split('?')[0];
  if (!urlPath.startsWith(prefix)) {
    applyCors(req, res, 404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Not found' }));
    return;
  }
  const relativePath = decodeURIComponent(urlPath.slice(prefix.length));
  const abs = resolveStoredFile(relativePath);
  if (!abs || !fs.existsSync(abs)) {
    applyCors(req, res, 404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Not found' }));
    return;
  }
  const stat = fs.statSync(abs);
  const ct = contentTypeForFilename(abs);
  applyCors(req, res, 200, {
    'Content-Type': ct,
    'Content-Length': String(stat.size),
    'Cache-Control': 'private, max-age=3600',
  });
  if (req.method === 'HEAD') {
    res.end();
    return;
  }
  fs.createReadStream(abs).pipe(res);
}

function isLocalFileUrl(rawUrl) {
  const value = String(rawUrl || '').trim();
  return value.includes('/api/files/');
}

function localRelativePathFromUrl(rawUrl) {
  const value = String(rawUrl || '').trim();
  const marker = '/api/files/';
  const idx = value.indexOf(marker);
  if (idx < 0) return null;
  try {
    return decodeURIComponent(value.slice(idx + marker.length).split('?')[0]);
  } catch (_) {
    return null;
  }
}

module.exports = {
  ensureUploadDir,
  getUploadDir,
  handleLocalFileUpload,
  handleLocalFileDownload,
  isLocalFileUrl,
  localRelativePathFromUrl,
  resolveStoredFile,
  publicFileUrl,
  contentTypeForFilename,
};
