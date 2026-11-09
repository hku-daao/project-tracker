/**
 * Project, sub-project, and discussion reply/follow-up notification emails.
 * Recipients and wording follow the approved preview files.
 */
let ctx;

function init(next) {
  ctx = next;
}

function slotIds(row, prefix) {
  const ids = [];
  const seen = new Set();
  for (let i = 1; i <= 60; i += 1) {
    const key = `${prefix}_${String(i).padStart(2, '0')}`;
    const raw = String(row?.[key] || '').trim();
    if (!raw) continue;
    const norm = raw.toLowerCase();
    if (seen.has(norm)) continue;
    seen.add(norm);
    ids.push(raw);
  }
  return ids;
}

function displayStatus(row) {
  const pause = String(row?.pause_status || '').trim().toLowerCase();
  if (pause === 'paused') return 'Paused';
  return String(row?.status || '').trim();
}

function projectWebAppUrl(projectId) {
  const id = String(projectId || '').trim();
  const base = String(ctx.PUBLIC_WEB_APP_URL || '').trim().replace(/\/$/, '');
  return `${base}/#/?project=${encodeURIComponent(id)}`;
}

async function rejectUnlessReady(req, res) {
  if (req.method !== 'POST') {
    ctx.sendJson(req, res, 405, { error: 'Method not allowed' });
    return null;
  }
  const session = await ctx.verifyFirebaseToken(req);
  if (!session) {
    ctx.sendJson(req, res, 401, { error: 'Unauthorized' });
    return null;
  }
  if (!ctx.db) {
    ctx.sendJson(req, res, 503, { error: 'Database not configured' });
    return null;
  }
  if (!ctx.EMAIL_SENDING_ENABLED) {
    ctx.notifyEmailSkippedResponse(req, res);
    return null;
  }
  if (!ctx.outboundEmailConfigured()) {
    ctx.sendJson(req, res, 503, { error: 'Outbound email transport not configured' });
    return null;
  }
  return session;
}

async function assertSessionStaff(session, staffId) {
  const id = String(staffId || '').trim();
  if (!id) return { ok: false, error: 'No acting staff id' };
  const { data: staff } = await ctx.fetchStaffRowForCreateBy(ctx.db, id);
  if (!staff) return { ok: false, error: 'Acting staff not found' };
  const sessionEmail = String(session.email || '').trim().toLowerCase();
  const staffEmail = String(staff.email || '').trim().toLowerCase();
  if (!(await ctx.sessionMayActForStaff(sessionEmail, staffEmail))) {
    return { ok: false, error: 'Signed-in user does not match the person who made this change' };
  }
  const replyTo = (
    (await ctx.resolveStaffEmailForNotifications(ctx.db, staff)) ||
    staffEmail
  ).trim();
  return { ok: true, staff, replyTo, sessionEmail };
}

function recipientMap(ids) {
  const map = new Map();
  for (const raw of ids) {
    const id = String(raw || '').trim();
    if (!id) continue;
    const key = id.toLowerCase();
    if (!map.has(key)) map.set(key, id);
  }
  return map;
}

async function detailLines(kind, row, changeMap) {
  const isSub = kind === 'subproject';
  const name = String(row.name || '').trim();
  const description = String(row.description || '').trim();
  const creatorName = await ctx.staffNameForEmail(ctx.db, row.create_by);
  const assigneeNames = await ctx.staffNamesForEmail(ctx.db, slotIds(row, 'assignee'));
  const picNames = await ctx.staffNamesForEmail(ctx.db, slotIds(row, 'pic'));
  const parentName = isSub
    ? await ctx.projectNameForEmail(ctx.db, row.project_id)
    : '';
  const status = displayStatus(row);
  const rows = [
    [
      isSub ? 'Sub-project' : 'Project',
      ctx.changedValueHtml(changeMap.get(isSub ? 'subprojectName' : 'projectName'), name),
      ctx.changedValueText(changeMap.get(isSub ? 'subprojectName' : 'projectName'), name),
    ],
    [
      'Description',
      ctx.changedValueHtml(changeMap.get('description'), description),
      ctx.changedValueText(changeMap.get('description'), description),
    ],
  ];
  if (isSub) {
    rows.push([
      'Project',
      ctx.changedValueHtml(changeMap.get('project'), parentName),
      ctx.changedValueText(changeMap.get('project'), parentName),
    ]);
  }
  rows.push(
    ['Creator', ctx.escapeHtml(ctx.emailPlainValue(creatorName)), ctx.emailPlainValue(creatorName)],
    [
      'Assignees',
      ctx.changedValueHtml(changeMap.get('assignees'), assigneeNames),
      ctx.changedValueText(changeMap.get('assignees'), assigneeNames),
    ],
    [
      'PIC',
      ctx.changedValueHtml(changeMap.get('pic'), picNames),
      ctx.changedValueText(changeMap.get('pic'), picNames),
    ],
    [
      'Status',
      ctx.changedValueHtml(changeMap.get('status'), status),
      ctx.changedValueText(changeMap.get('status'), status),
    ],
    [
      'Start date',
      ctx.changedDateHtml(changeMap.get('startDate'), row.start_date),
      ctx.changedDateText(changeMap.get('startDate'), row.start_date),
    ],
    [
      'End date',
      ctx.changedDateHtml(changeMap.get('endDate'), row.end_date),
      ctx.changedDateText(changeMap.get('endDate'), row.end_date),
    ],
  );
  const filesChange = changeMap.get('files');
  if (filesChange) {
    rows.push(['Files', ctx.changedActionHtml(filesChange), ctx.changedActionText(filesChange)]);
  }
  const urlChange = changeMap.get('urls');
  if (urlChange) {
    rows.push(['URL', ctx.changedActionHtml(urlChange), ctx.changedActionText(urlChange)]);
  }
  const commentChange = changeMap.get('comment');
  if (commentChange) {
    rows.push([
      'Comment',
      ctx.changedActionHtml(commentChange),
      ctx.changedActionText(commentChange),
    ]);
  }
  return {
    html: rows.map(([label, html]) => ctx.detailLineHtml(label, html)).join('<br><br>'),
    text: rows.map(([label, , text]) => ctx.detailLineText(label, text)).join('\n\n'),
  };
}

function copySubject(kind, event, name, changeMap) {
  const label = kind === 'subproject' ? 'Sub-project' : 'Project';
  const title = ctx.mailSubjectSingleLine(name);
  if (event === 'assigned') {
    return `[Project Tracker] New ${label} Assigned: ${title}`;
  }
  if (event === 'comment-added') {
    return `[Project Tracker] ${label} Comment Added: ${title}`;
  }
  if (event === 'comment-edited') {
    return `[Project Tracker] ${label} Comment Updated: ${title}`;
  }
  if (event === 'deleted') return `[Project Tracker] ${label} Deleted: ${title}`;
  if (event === 'restored') return `[Project Tracker] ${label} Restored: ${title}`;
  if (event === 'paused') return `[Project Tracker] ${label} Paused: ${title}`;
  if (event === 'resumed') return `[Project Tracker] ${label} Resumed: ${title}`;
  if (event === 'completed') return `[Project Tracker] ${label} Completed: ${title}`;
  const keys = [...changeMap.keys()];
  if (keys.length === 1 && keys[0] === 'files') {
    return `[Project Tracker] ${label} File Update: ${title}`;
  }
  if (keys.length === 1 && keys[0] === 'urls') {
    return `[Project Tracker] ${label} URL Update: ${title}`;
  }
  return `[Project Tracker] ${label} Update: ${title}`;
}

function copyIntro(kind, event, changeMap) {
  const noun = kind === 'subproject' ? 'sub-project' : 'project';
  if (event === 'assigned') {
    return `This email is to inform you that a new ${noun} has been created and assigned to you.`;
  }
  if (event === 'comment-added') {
    return `This email is to inform you that a comment has been added to the ${noun}.`;
  }
  if (event === 'comment-edited') {
    return `This email is to inform you that a comment has been updated on the ${noun}.`;
  }
  if (event === 'deleted') {
    return `This email is to inform you that the ${noun} has been deleted. This ${noun} is removed from the active list.`;
  }
  if (event === 'restored') {
    return `This email is to inform you that the ${noun} has been restored. This deleted ${noun} is brought back to the active list.`;
  }
  if (event === 'paused') {
    return `This email is to inform you that the ${noun} has been paused. Work on this ${noun} is temporarily suspended.`;
  }
  if (event === 'resumed') {
    return `This email is to inform you that the ${noun} has been resumed. Work on this ${noun} continues after being paused.`;
  }
  if (event === 'completed') {
    return `This email is to inform you that the ${noun} has been marked completed.`;
  }
  const keys = [...changeMap.keys()];
  if (keys.length === 1 && keys[0] === 'files') {
    return `This email is to inform you that ${noun} file information has been updated.`;
  }
  if (keys.length === 1 && keys[0] === 'urls') {
    return `This email is to inform you that ${noun} URL information has been updated.`;
  }
  return `This email is to inform you that ${noun} information has been updated.`;
}

function copyClosing(kind, event) {
  const noun = kind === 'subproject' ? 'sub-project' : 'project';
  if (event === 'assigned') return `Please review the new ${noun} in Project Tracker.`;
  if (event === 'deleted') return `Please review the deleted ${noun} in Project Tracker.`;
  if (event === 'restored') return `Please review the restored ${noun} in Project Tracker.`;
  if (event === 'paused') return `Please review the paused ${noun} in Project Tracker.`;
  if (event === 'resumed') return `Please review the resumed ${noun} in Project Tracker.`;
  if (event === 'completed') return `Please review the completed ${noun} in Project Tracker.`;
  const updated = kind === 'subproject' ? 'sub-project' : 'project';
  return `Please review the updated ${updated} information in Project Tracker.`;
}

const ACTION_EVENTS = new Set([
  'deleted',
  'restored',
  'paused',
  'resumed',
  'completed',
]);

async function handleHierarchyEvent(req, res) {
  const session = await rejectUnlessReady(req, res);
  if (!session) return;
  try {
    const body = await ctx.readBody(req);
    const kind = String(body.kind || '').trim();
    const event = String(body.event || '').trim();
    const id = String(body.id || '').trim();
    if (kind !== 'project' && kind !== 'subproject') {
      ctx.sendJson(req, res, 400, { error: 'kind must be project or subproject' });
      return;
    }
    if (!id || !event) {
      ctx.sendJson(req, res, 400, { error: 'id and event required' });
      return;
    }
    const table = kind === 'project' ? 'project' : 'subproject';
    const { data: row, error } = await ctx.db.from(table).select('*').eq('id', id).maybeSingle();
    if (error || !row) {
      ctx.sendJson(req, res, 404, { error: `${kind} not found` });
      return;
    }
    const changeMap = ctx.emailChangeMap(body.changes);
    let actorId = event === 'assigned'
      ? String(row.create_by || '').trim()
      : String(row.update_by || row.create_by || '').trim();
    if (event === 'comment-added' || event === 'comment-edited') {
      const commentId = String(body.commentId || '').trim();
      const commentTable = kind === 'project' ? 'project_comment' : 'subproject_comment';
      const foreignKey = kind === 'project' ? 'project_id' : 'subproject_id';
      if (!commentId) {
        ctx.sendJson(req, res, 400, { error: 'commentId required' });
        return;
      }
      const { data: commentRow, error: commentErr } = await ctx.db
        .from(commentTable)
        .select('*')
        .eq('id', commentId)
        .maybeSingle();
      if (commentErr || !commentRow || String(commentRow[foreignKey] || '').trim() !== id) {
        ctx.sendJson(req, res, 400, { error: 'commentId does not match this item' });
        return;
      }
      actorId = String(
        event === 'comment-edited'
          ? (commentRow.update_by || commentRow.create_by || '')
          : (commentRow.create_by || ''),
      ).trim();
      const existing = changeMap.get('comment');
      changeMap.set('comment', {
        oldValue: existing ? existing.oldValue : '',
        newValue: String(commentRow.description || '').trim(),
      });
    }
    if (event === 'updated' && changeMap.size === 0) {
      ctx.sendJson(req, res, 200, { ok: true, skipped: true, reason: 'no_changes' });
      return;
    }
    const actor = await assertSessionStaff(session, actorId);
    if (!actor.ok) {
      ctx.sendJson(req, res, 403, { error: actor.error });
      return;
    }
    const name = String(row.name || '').trim() || '(no title)';
    const projectId = kind === 'project' ? id : String(row.project_id || '').trim();
    const linkUrl = projectWebAppUrl(projectId);
    const lines = await detailLines(kind, row, changeMap);
    const subject = copySubject(kind, event, name, changeMap);
    const intro = copyIntro(kind, event, changeMap);
    const closing = copyClosing(kind, event);
    const linkHtml = ctx.eventInlineLinkHtml('Project link', linkUrl);
    const linkText = ctx.eventInlineLinkText('Project link', linkUrl);
    const recipients = recipientMap([
      ...slotIds(row, 'assignee'),
      ...(Array.isArray(body.previousAssigneeIds) ? body.previousAssigneeIds : []),
    ]);
    if (event !== 'assigned') {
      const creatorId = String(row.create_by || '').trim();
      if (creatorId) recipients.set(creatorId.toLowerCase(), creatorId);
    }
    if (event !== 'assigned' && !ACTION_EVENTS.has(event)) {
      recipients.delete(String(actorId).toLowerCase());
    }
    if (event === 'assigned') {
      recipients.delete(String(row.create_by || '').trim().toLowerCase());
    }
    const results = [];
    for (const staffId of recipients.values()) {
      const { data: staff } = await ctx.fetchStaffRowForCreateBy(ctx.db, staffId);
      const to = await ctx.resolveStaffEmailForNotifications(ctx.db, staff);
      if (!to) {
        results.push({ staffId, ok: false, skipped: 'no email' });
        continue;
      }
      const recipientName = ctx.staffDisplayName(staff, to);
      const html = `<div style="margin:0;font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;line-height:1.5;color:#000000;">Dear ${ctx.escapeHtml(recipientName)},<br><br>
${ctx.escapeHtml(intro)}<br><br>
${lines.html}<br><br>
${ctx.escapeHtml(closing)} ${linkHtml}<br><br>
${ctx.projectTrackerEmailFooterHtml()}</div>`;
      const text = `Dear ${recipientName},

${intro}

${lines.text}

${closing} ${linkText}

${ctx.projectTrackerEmailFooterText()}`;
      const sent = await ctx.sendNotificationEmail({
        to,
        subject,
        text,
        html,
        from: ctx.NOTIFICATION_EMAIL_FROM,
        replyTo: actor.replyTo || actor.sessionEmail || undefined,
      });
      results.push({
        to,
        ok: sent.ok,
        error: sent.ok ? null : sent.error,
      });
    }
    ctx.sendJson(req, res, 200, {
      ok: true,
      kind,
      event,
      id,
      recipients: results.filter((item) => item.ok && !item.skipped).length,
      results,
    });
  } catch (e) {
    console.error('handleHierarchyEvent:', e);
    ctx.sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

function greenValue(value) {
  const text = String(value || '').trim() || '(empty)';
  return `<strong><span style="color:#188038;">${ctx.escapeHtml(text)}</span></strong>`;
}

async function handleDiscussionReply(req, res) {
  const session = await rejectUnlessReady(req, res);
  if (!session) return;
  try {
    const body = await ctx.readBody(req);
    const postId = String(body.postId || '').trim();
    if (!postId) {
      ctx.sendJson(req, res, 400, { error: 'postId required' });
      return;
    }
    const { data: post, error } = await ctx.db
      .from('forum_post')
      .select('id, thread_id, parent_post_id, depth, content, created_by')
      .eq('id', postId)
      .maybeSingle();
    if (error || !post) {
      ctx.sendJson(req, res, 404, { error: 'Discussion post not found' });
      return;
    }
    const depth = Number(post.depth || 0);
    if (depth <= 0) {
      ctx.sendJson(req, res, 200, { ok: true, skipped: true, reason: 'root_post' });
      return;
    }
    const { data: thread } = await ctx.db
      .from('forum_thread')
      .select('id, title, category')
      .eq('id', post.thread_id)
      .maybeSingle();
    if (!thread) {
      ctx.sendJson(req, res, 404, { error: 'Discussion thread not found' });
      return;
    }
    const parentId = String(post.parent_post_id || '').trim();
    const { data: parent } = parentId
      ? await ctx.db
        .from('forum_post')
        .select('id, parent_post_id, depth, content, created_by')
        .eq('id', parentId)
        .maybeSingle()
      : { data: null };
    let root = parent;
    if (parent && Number(parent.depth || 0) > 0 && parent.parent_post_id) {
      const { data: rootRow } = await ctx.db
        .from('forum_post')
        .select('id, content, created_by, depth')
        .eq('id', parent.parent_post_id)
        .maybeSingle();
      if (rootRow) root = rootRow;
    }
    if (!root) {
      ctx.sendJson(req, res, 400, { error: 'Parent post not found' });
      return;
    }
    const author = await assertSessionStaff(session, post.created_by);
    if (!author.ok) {
      ctx.sendJson(req, res, 403, { error: author.error });
      return;
    }
    const isFollowUp = depth >= 2;
    const recipients = recipientMap([root.created_by]);
    if (isFollowUp && parent?.created_by) recipients.set(
      String(parent.created_by).trim().toLowerCase(),
      String(parent.created_by).trim(),
    );
    recipients.delete(String(post.created_by || '').trim().toLowerCase());
    const topic = String(thread.title || '').trim() || '(no title)';
    const category = String(thread.category || '').trim() || 'General';
    const topicUrl = ctx.discussionWebAppUrl(thread.id);
    const rootAuthor = await ctx.staffNameForEmail(ctx.db, root.created_by);
    const replyAuthorName = isFollowUp
      ? await ctx.staffNameForEmail(ctx.db, parent.created_by)
      : await ctx.staffNameForEmail(ctx.db, post.created_by);
    const followAuthorName = await ctx.staffNameForEmail(ctx.db, post.created_by);
    const rootBody = String(root.content || '').trim() || '(empty)';
    const replyBody = isFollowUp
      ? (String(parent.content || '').trim() || '(empty)')
      : (String(post.content || '').trim() || '(empty)');
    const followBody = String(post.content || '').trim() || '(empty)';
    const subject = isFollowUp
      ? `[Project Tracker] New Follow-up: ${ctx.mailSubjectSingleLine(topic)}`
      : `[Project Tracker] New Reply: ${ctx.mailSubjectSingleLine(topic)}`;
    const intro = isFollowUp
      ? 'This email is to inform you that a follow-up has been added to a reply on this discussion post.'
      : 'This email is to inform you that a reply has been added to your discussion post.';
    const rows = [
      ['Topic', ctx.escapeHtml(topic), topic],
      ['Category', ctx.escapeHtml(category), category],
      ['Post by', ctx.escapeHtml(ctx.emailPlainValue(rootAuthor)), ctx.emailPlainValue(rootAuthor)],
      ['Post', ctx.escapeHtml(rootBody).replace(/\r\n|\r|\n/g, '<br>'), rootBody],
      ['Reply by', ctx.escapeHtml(ctx.emailPlainValue(replyAuthorName)), ctx.emailPlainValue(replyAuthorName)],
      [
        'Reply',
        isFollowUp ? ctx.escapeHtml(replyBody).replace(/\r\n|\r|\n/g, '<br>') : greenValue(replyBody),
        replyBody,
      ],
    ];
    if (isFollowUp) {
      rows.push(
        ['Follow-up by', ctx.escapeHtml(ctx.emailPlainValue(followAuthorName)), ctx.emailPlainValue(followAuthorName)],
        ['Follow-up', greenValue(followBody), followBody],
      );
    }
    const lines = {
      html: rows.map(([label, html]) => ctx.detailLineHtml(label, html)).join('<br><br>'),
      text: rows.map(([label, , text]) => ctx.detailLineText(label, text)).join('\n\n'),
    };
    const closing = isFollowUp
      ? 'Please review the follow-up in Project Tracker.'
      : 'Please review the reply in Project Tracker.';
    const linkHtml = ctx.eventInlineLinkHtml('Topic link', topicUrl);
    const linkText = ctx.eventInlineLinkText('Topic link', topicUrl);
    const results = [];
    for (const staffId of recipients.values()) {
      const { data: staff } = await ctx.fetchStaffRowForCreateBy(ctx.db, staffId);
      const to = await ctx.resolveStaffEmailForNotifications(ctx.db, staff);
      if (!to) {
        results.push({ staffId, ok: false, skipped: 'no email' });
        continue;
      }
      const recipientName = ctx.staffDisplayName(staff, to);
      const html = `<div style="margin:0;font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;line-height:1.5;color:#000000;">Dear ${ctx.escapeHtml(recipientName)},<br><br>
${ctx.escapeHtml(intro)}<br><br>
${lines.html}<br><br>
${ctx.escapeHtml(closing)} ${linkHtml}<br><br>
${ctx.projectTrackerEmailFooterHtml()}</div>`;
      const text = `Dear ${recipientName},

${intro}

${lines.text}

${closing} ${linkText}

${ctx.projectTrackerEmailFooterText()}`;
      const sent = await ctx.sendNotificationEmail({
        to,
        subject,
        text,
        html,
        from: ctx.NOTIFICATION_EMAIL_FROM,
        replyTo: author.replyTo || author.sessionEmail || undefined,
      });
      results.push({ to, ok: sent.ok, error: sent.ok ? null : sent.error });
    }
    ctx.sendJson(req, res, 200, {
      ok: true,
      postId,
      depth,
      recipients: results.filter((item) => item.ok && !item.skipped).length,
      results,
    });
  } catch (e) {
    console.error('handleDiscussionReply:', e);
    ctx.sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

module.exports = {
  init,
  handleHierarchyEvent,
  handleDiscussionReply,
};
