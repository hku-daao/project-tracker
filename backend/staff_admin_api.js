/**
 * Staff view writes. The signed-in person must have a staff_admin row.
 * super_admin manages every staff and team. office_admin manages one office.
 */

function emailCandidates(email) {
  const normalized = String(email || '').trim().toLowerCase();
  const at = normalized.indexOf('@');
  const local = at > 0 ? normalized.slice(0, at) : '';
  const out = new Set();
  if (normalized) out.add(normalized);
  if (local) {
    out.add(`${local}@hku.hk`);
    out.add(`${local}@connect.hku.hk`);
  }
  return [...out];
}

function parseStaffEmail(raw) {
  const email = String(raw || '').trim().toLowerCase();
  const at = email.indexOf('@');
  if (at <= 0 || at !== email.lastIndexOf('@')) {
    return { error: 'Email must be a single @hku.hk address.' };
  }
  const local = email.slice(0, at);
  const domain = email.slice(at);
  if (domain !== '@hku.hk') {
    return { error: 'Email domain must be @hku.hk.' };
  }
  if (!/^[a-z0-9][a-z0-9._-]*$/i.test(local)) {
    return { error: 'Email name contains a character that is not allowed.' };
  }
  if (local.length > 8) {
    return { error: 'Email name before @ must be 8 characters or fewer.' };
  }
  return { email, local: local.toLowerCase() };
}

async function loadActor(pool, email) {
  const candidates = emailCandidates(email);
  if (candidates.length === 0) return null;
  const staff = await pool.query(
    `SELECT id, email, name, app_id
     FROM staff
     WHERE lower(email) = ANY($1::text[])
     ORDER BY CASE WHEN lower(email) = $2 THEN 0 ELSE 1 END
     LIMIT 1`,
    [candidates, String(email || '').trim().toLowerCase()],
  );
  const row = staff.rows[0];
  if (!row) return null;
  const grants = await pool.query(
    `SELECT role, office_id
     FROM staff_admin
     WHERE staff_id = $1`,
    [row.id],
  );
  const superAdmin = grants.rows.some((g) => g.role === 'super_admin');
  const officeIds = [
    ...new Set(
      grants.rows
        .filter((g) => g.role === 'office_admin' && g.office_id)
        .map((g) => String(g.office_id)),
    ),
  ];
  const performanceOfficeIds = [
    ...new Set(
      grants.rows
        .filter((g) => g.role === 'performance_admin' && g.office_id)
        .map((g) => String(g.office_id)),
    ),
  ];
  let role = null;
  if (superAdmin) role = 'super_admin';
  else if (officeIds.length > 0) role = 'office_admin';
  else if (performanceOfficeIds.length > 0) role = 'performance_admin';
  if (!role) return null;
  return {
    staffId: row.id,
    email: row.email,
    superAdmin,
    officeIds,
    performanceOfficeIds,
    role,
  };
}

async function loadScope(pool, actor) {
  const offices = await pool.query(
    `SELECT office_id, office_name
     FROM office
     WHERE office_id IS NOT NULL AND btrim(office_id) <> ''
     ORDER BY office_name`,
  );
  const teams = await pool.query(
    `SELECT id, team_id, team_name, office_id
     FROM team
     ORDER BY team_name, team_id`,
  );
  const staff = await pool.query(
    `SELECT s.id, s.name, s.email, s.app_id, s.team_id, s.active,
            t.office_id
     FROM staff s
     LEFT JOIN LATERAL (
       SELECT office_id
       FROM team
       WHERE lower(team_id) = lower(s.team_id)
       LIMIT 1
     ) t ON true
     ORDER BY s.name`,
  );
  const links = await pool.query(
    `SELECT supervisor_id, subordinate_id FROM subordinate`,
  );
  const implied = await pool.query(
    `SELECT supervisor_id, subordinate_id FROM subordinate_implied`,
  );

  const officeAllowed = (officeId) =>
    actor.superAdmin || actor.officeIds.includes(String(officeId || ''));

  const visibleOffices = offices.rows.filter((o) => officeAllowed(o.office_id));
  const visibleTeams = teams.rows.filter((t) => officeAllowed(t.office_id));
  const visibleStaff = staff.rows.filter((s) => {
    if (actor.superAdmin) return true;
    return s.office_id && actor.officeIds.includes(String(s.office_id));
  });
  const staffByApp = new Map();
  for (const s of staff.rows) {
    const key = String(s.app_id || '').trim().toLowerCase();
    if (key) staffByApp.set(key, s);
  }
  const visibleIds = new Set(visibleStaff.map((s) => s.id));
  const linkRows = (rows) => {
    const out = [];
    for (const link of rows) {
      const sup = staffByApp.get(String(link.supervisor_id || '').trim().toLowerCase());
      const sub = staffByApp.get(String(link.subordinate_id || '').trim().toLowerCase());
      if (!sup || !sub) continue;
      if (!visibleIds.has(sup.id) || !visibleIds.has(sub.id)) continue;
      out.push({
        supervisorStaffId: sup.id,
        subordinateStaffId: sub.id,
      });
    }
    return out;
  };
  const visibleLinks = linkRows(links.rows);
  const impliedLinks = linkRows(implied.rows);

  return {
    role: actor.role,
    offices: visibleOffices.map((o) => ({
      officeId: o.office_id,
      officeName: o.office_name || o.office_id,
    })),
    teams: visibleTeams.map((t) => ({
      id: t.id,
      teamId: t.team_id,
      teamName: t.team_name,
      officeId: t.office_id,
    })),
    staff: visibleStaff.map((s) => ({
      id: s.id,
      name: s.name,
      email: s.email,
      appId: s.app_id,
      teamId: s.team_id,
      active: s.active !== false,
      officeId: s.office_id,
    })),
    links: visibleLinks,
    impliedLinks,
  };
}

function teamInScope(scope, teamId) {
  const key = String(teamId || '').trim().toLowerCase();
  return scope.teams.find((t) => String(t.teamId).trim().toLowerCase() === key) || null;
}

function staffInScope(scope, staffId) {
  return scope.staff.find((s) => s.id === staffId) || null;
}

async function handle(req, res, ctx) {
  const { pool, verifySession, sendJson, readBody } = ctx;
  if (!pool) {
    sendJson(req, res, 503, { error: 'Database not configured' });
    return;
  }
  const session = await verifySession(req);
  if (!session || !session.email) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  const actor = await loadActor(pool, session.email);
  if (!actor) {
    sendJson(req, res, 403, { error: 'You do not have access to Staff.' });
    return;
  }

  const url = new URL(req.url || '/', `http://${req.headers.host}`);
  const path = url.pathname;

  try {
    if (path === '/api/staff-admin/context' && req.method === 'GET') {
      if (actor.role === 'performance_admin') {
        sendJson(req, res, 200, {
          role: 'performance_admin',
          officeIds: actor.performanceOfficeIds,
        });
        return;
      }
      const scope = await loadScope(pool, actor);
      scope.officeIds = actor.superAdmin
        ? scope.offices.map((o) => o.officeId)
        : actor.officeIds;
      sendJson(req, res, 200, scope);
      return;
    }
    if (actor.role === 'performance_admin') {
      sendJson(req, res, 403, { error: 'You do not have access to Staff.' });
      return;
    }
    if (path === '/api/staff-admin/staff' && req.method === 'POST') {
      await createStaff(pool, actor, await readBody(req), sendJson, req, res);
      return;
    }
    if (path.startsWith('/api/staff-admin/staff/') && req.method === 'PATCH') {
      const id = path.split('/').pop();
      await updateStaff(pool, actor, id, await readBody(req), sendJson, req, res);
      return;
    }
    if (path === '/api/staff-admin/teams' && req.method === 'POST') {
      await createTeam(pool, actor, await readBody(req), sendJson, req, res);
      return;
    }
    if (path.startsWith('/api/staff-admin/teams/') && req.method === 'PATCH') {
      const id = path.split('/').pop();
      await updateTeam(pool, actor, id, await readBody(req), sendJson, req, res);
      return;
    }
    if (path.startsWith('/api/staff-admin/teams/') && req.method === 'DELETE') {
      const id = path.split('/').pop();
      await deleteTeam(pool, actor, id, sendJson, req, res);
      return;
    }
    if (path === '/api/staff-admin/subordinates' && req.method === 'PUT') {
      await setSubordinates(pool, actor, await readBody(req), sendJson, req, res);
      return;
    }
    if (path === '/api/staff-admin/supervisors' && req.method === 'PUT') {
      await setSupervisors(pool, actor, await readBody(req), sendJson, req, res);
      return;
    }
    sendJson(req, res, 404, { error: 'Not found' });
  } catch (e) {
    console.error('staff-admin:', e);
    sendJson(req, res, 500, { error: 'Could not save Staff changes.' });
  }
}

async function createStaff(pool, actor, body, sendJson, req, res) {
  const parsed = parseStaffEmail(body.email);
  if (parsed.error) {
    sendJson(req, res, 400, { error: parsed.error });
    return;
  }
  const name = String(body.name || '').trim();
  if (!name) {
    sendJson(req, res, 400, { error: 'Name is required.' });
    return;
  }
  const scope = await loadScope(pool, actor);
  const team = teamInScope(scope, body.teamId);
  if (!team) {
    sendJson(req, res, 400, { error: 'Choose a team in your office.' });
    return;
  }
  const dup = await pool.query(
    `SELECT 1 FROM staff WHERE lower(email) = $1 OR lower(app_id) = $2 LIMIT 1`,
    [parsed.email, parsed.local],
  );
  if (dup.rows.length > 0) {
    sendJson(req, res, 400, { error: 'That email is already used by a staff record.' });
    return;
  }
  const active = body.active !== false;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `INSERT INTO staff (name, email, app_id, team_id, active)
       VALUES ($1, $2, $3, $4, $5)`,
      [name, parsed.email, parsed.local, team.teamId, active],
    );
    await linkNewStaffToAdmins(client, parsed.local, team.officeId);
    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
  sendJson(req, res, 200, { ok: true });
}

async function linkNewStaffToAdmins(client, appId, officeId) {
  const subordinateId = String(appId || '').trim();
  if (!subordinateId) return;
  const office = String(officeId || '').trim();
  await client.query(
    `INSERT INTO subordinate (supervisor_id, subordinate_id)
     SELECT DISTINCT admin.app_id, $1
     FROM staff_admin grant_row
     JOIN staff admin ON admin.id = grant_row.staff_id
     WHERE admin.app_id IS NOT NULL
       AND btrim(admin.app_id) <> ''
       AND lower(admin.app_id) <> lower($1)
       AND (
         grant_row.role = 'super_admin'
         OR (
           grant_row.role IN ('office_admin', 'performance_admin')
           AND btrim($2) <> ''
           AND lower(grant_row.office_id) = lower($2)
         )
       )
     ON CONFLICT ON CONSTRAINT unique_supervisor_subordinate DO NOTHING`,
    [subordinateId, office],
  );
}

async function updateStaff(pool, actor, staffId, body, sendJson, req, res) {
  const scope = await loadScope(pool, actor);
  const existing = staffInScope(scope, staffId);
  if (!existing) {
    sendJson(req, res, 404, { error: 'Staff record is outside your office.' });
    return;
  }
  const parsed = parseStaffEmail(body.email);
  if (parsed.error) {
    sendJson(req, res, 400, { error: parsed.error });
    return;
  }
  const name = String(body.name || '').trim();
  if (!name) {
    sendJson(req, res, 400, { error: 'Name is required.' });
    return;
  }
  const team = teamInScope(scope, body.teamId);
  if (!team) {
    sendJson(req, res, 400, { error: 'Choose a team in your office.' });
    return;
  }
  const dup = await pool.query(
    `SELECT 1 FROM staff
     WHERE id <> $1 AND lower(email) = $2
     LIMIT 1`,
    [staffId, parsed.email],
  );
  if (dup.rows.length > 0) {
    sendJson(req, res, 400, { error: 'That email is already used by a staff record.' });
    return;
  }
  const active = body.active !== false;
  await pool.query(
    `UPDATE staff
     SET name = $2, email = $3, team_id = $4, active = $5
     WHERE id = $1`,
    [staffId, name, parsed.email, team.teamId, active],
  );
  sendJson(req, res, 200, { ok: true });
}

async function createTeam(pool, actor, body, sendJson, req, res) {
  const teamId = String(body.teamId || '').trim();
  const teamName = String(body.teamName || '').trim();
  const officeId = String(body.officeId || '').trim();
  if (!teamId || !teamName || !officeId) {
    sendJson(req, res, 400, { error: 'Team id, team name, and office are required.' });
    return;
  }
  const scope = await loadScope(pool, actor);
  if (!scope.offices.some((o) => o.officeId === officeId)) {
    sendJson(req, res, 400, { error: 'That office is outside your access.' });
    return;
  }
  const dup = await pool.query(
    `SELECT 1 FROM team WHERE lower(team_id) = lower($1) LIMIT 1`,
    [teamId],
  );
  if (dup.rows.length > 0) {
    sendJson(req, res, 400, { error: 'That team id already exists.' });
    return;
  }
  await pool.query(
    `INSERT INTO team (team_id, team_name, office_id) VALUES ($1, $2, $3)`,
    [teamId, teamName, officeId],
  );
  sendJson(req, res, 200, { ok: true });
}

async function updateTeam(pool, actor, teamUuid, body, sendJson, req, res) {
  const scope = await loadScope(pool, actor);
  const current = await pool.query(
    `SELECT id, team_id, office_id FROM team WHERE id = $1`,
    [teamUuid],
  );
  const row = current.rows[0];
  if (!row || !scope.teams.some((t) => t.id === row.id)) {
    sendJson(req, res, 404, { error: 'Team is outside your office.' });
    return;
  }
  const teamId = String(body.teamId || '').trim();
  const teamName = String(body.teamName || '').trim();
  const officeId = String(body.officeId || '').trim();
  if (!teamId || !teamName || !officeId) {
    sendJson(req, res, 400, { error: 'Team id, team name, and office are required.' });
    return;
  }
  if (!scope.offices.some((o) => o.officeId === officeId)) {
    sendJson(req, res, 400, { error: 'That office is outside your access.' });
    return;
  }
  const dup = await pool.query(
    `SELECT 1 FROM team WHERE id <> $1 AND lower(team_id) = lower($2) LIMIT 1`,
    [teamUuid, teamId],
  );
  if (dup.rows.length > 0) {
    sendJson(req, res, 400, { error: 'That team id already exists.' });
    return;
  }
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `UPDATE team SET team_id = $2, team_name = $3, office_id = $4 WHERE id = $1`,
      [teamUuid, teamId, teamName, officeId],
    );
    if (String(row.team_id).trim().toLowerCase() !== teamId.toLowerCase()) {
      await client.query(
        `UPDATE staff SET team_id = $2 WHERE lower(team_id) = lower($1)`,
        [row.team_id, teamId],
      );
    }
    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
  sendJson(req, res, 200, { ok: true });
}

async function deleteTeam(pool, actor, teamUuid, sendJson, req, res) {
  const scope = await loadScope(pool, actor);
  const current = await pool.query(
    `SELECT id, team_id FROM team WHERE id = $1`,
    [teamUuid],
  );
  const row = current.rows[0];
  if (!row || !scope.teams.some((t) => t.id === row.id)) {
    sendJson(req, res, 404, { error: 'Team is outside your office.' });
    return;
  }
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `UPDATE staff SET team_id = NULL WHERE lower(team_id) = lower($1)`,
      [row.team_id],
    );
    await client.query(`DELETE FROM team WHERE id = $1`, [teamUuid]);
    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
  sendJson(req, res, 200, { ok: true });
}

async function setSubordinates(pool, actor, body, sendJson, req, res) {
  const scope = await loadScope(pool, actor);
  const supervisor = staffInScope(scope, body.supervisorStaffId);
  if (!supervisor || !supervisor.appId) {
    sendJson(req, res, 400, { error: 'Choose a supervisor in your office.' });
    return;
  }
  const requested = Array.isArray(body.subordinateStaffIds)
    ? body.subordinateStaffIds
    : [];
  const subordinates = [];
  for (const id of requested) {
    if (id === supervisor.id) continue;
    const person = staffInScope(scope, id);
    if (!person || !person.appId) {
      sendJson(req, res, 400, { error: 'A selected staff member is outside your office.' });
      return;
    }
    subordinates.push(person);
  }
  const inScopeAppIds = scope.staff
    .map((s) => String(s.appId || '').trim())
    .filter((id) => id && id.toLowerCase() !== String(supervisor.appId).toLowerCase());

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const implied = await client.query(
      `SELECT subordinate_id
       FROM subordinate_implied
       WHERE lower(supervisor_id) = lower($1)`,
      [supervisor.appId],
    );
    const impliedAppIds = new Set(
      implied.rows.map((row) => String(row.subordinate_id || '').trim().toLowerCase()),
    );
    const stored = subordinates.filter(
      (person) => !impliedAppIds.has(String(person.appId).trim().toLowerCase()),
    );
    const deletable = inScopeAppIds.filter(
      (id) => !impliedAppIds.has(id.toLowerCase()),
    );
    if (deletable.length > 0) {
      await client.query(
        `DELETE FROM subordinate
         WHERE lower(supervisor_id) = lower($1)
           AND lower(subordinate_id) = ANY($2::text[])`,
        [supervisor.appId, deletable.map((id) => id.toLowerCase())],
      );
    }
    for (const person of stored) {
      await client.query(
        `INSERT INTO subordinate (supervisor_id, subordinate_id)
         VALUES ($1, $2)
         ON CONFLICT ON CONSTRAINT unique_supervisor_subordinate DO NOTHING`,
        [supervisor.appId, person.appId],
      );
    }
    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
  sendJson(req, res, 200, { ok: true });
}

async function setSupervisors(pool, actor, body, sendJson, req, res) {
  const scope = await loadScope(pool, actor);
  const subordinate = staffInScope(scope, body.subordinateStaffId);
  if (!subordinate || !subordinate.appId) {
    sendJson(req, res, 400, { error: 'Choose a subordinate in your office.' });
    return;
  }
  const requested = Array.isArray(body.supervisorStaffIds)
    ? body.supervisorStaffIds
    : [];
  const supervisors = [];
  for (const id of requested) {
    if (id === subordinate.id) continue;
    const person = staffInScope(scope, id);
    if (!person || !person.appId) {
      sendJson(req, res, 400, { error: 'A selected staff member is outside your office.' });
      return;
    }
    supervisors.push(person);
  }
  const inScopeAppIds = scope.staff
    .map((s) => String(s.appId || '').trim())
    .filter((id) => id && id.toLowerCase() !== String(subordinate.appId).toLowerCase());

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const implied = await client.query(
      `SELECT supervisor_id
       FROM subordinate_implied
       WHERE lower(subordinate_id) = lower($1)`,
      [subordinate.appId],
    );
    const impliedAppIds = new Set(
      implied.rows.map((row) => String(row.supervisor_id || '').trim().toLowerCase()),
    );
    const stored = supervisors.filter(
      (person) => !impliedAppIds.has(String(person.appId).trim().toLowerCase()),
    );
    const deletable = inScopeAppIds.filter(
      (id) => !impliedAppIds.has(id.toLowerCase()),
    );
    if (deletable.length > 0) {
      await client.query(
        `DELETE FROM subordinate
         WHERE lower(subordinate_id) = lower($1)
           AND lower(supervisor_id) = ANY($2::text[])`,
        [subordinate.appId, deletable.map((id) => id.toLowerCase())],
      );
    }
    for (const person of stored) {
      await client.query(
        `INSERT INTO subordinate (supervisor_id, subordinate_id)
         VALUES ($1, $2)
         ON CONFLICT ON CONSTRAINT unique_supervisor_subordinate DO NOTHING`,
        [person.appId, subordinate.appId],
      );
    }
    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
  sendJson(req, res, 200, { ok: true });
}

module.exports = { handle };
