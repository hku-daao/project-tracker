const nodemailer = require('nodemailer');

const SMTP_HOST = (process.env.SMTP_HOST || '').trim();
const SMTP_PORT = parseInt(process.env.SMTP_PORT || '25', 10) || 25;
const SMTP_USER = (process.env.SMTP_USER || '').trim();
const SMTP_PASSWORD = (process.env.SMTP_PASSWORD || '').trim();
const SMTP_FROM = (process.env.SMTP_FROM || 'daaoit.ops@hku.hk').trim();
const SMTP_SECURE = (process.env.SMTP_SECURE || 'false').trim().toLowerCase() === 'true';

function isSmtpConfigured() {
  return SMTP_HOST.length > 0 && SMTP_FROM.includes('@');
}

function createTransporter() {
  if (!isSmtpConfigured()) {
    throw new Error('SMTP not configured (set SMTP_HOST and SMTP_FROM in .env)');
  }
  const auth =
    SMTP_USER.length > 0
      ? { user: SMTP_USER, pass: SMTP_PASSWORD }
      : undefined;
  return nodemailer.createTransport({
    host: SMTP_HOST,
    port: SMTP_PORT,
    secure: SMTP_SECURE,
    auth,
    tls: { rejectUnauthorized: false },
  });
}

/**
 * @returns {{ ok: true, messageId: string, resolvedTo: string } | { ok: false, error: string, detail?: string }}
 */
async function sendSmtpMail({ to, subject, text, html, from: fromOverride }) {
  const toAddr = String(to || '')
    .trim()
    .split(/[,;]/)[0]
    .trim()
    .toLowerCase();
  if (!toAddr || !toAddr.includes('@')) {
    return { ok: false, error: 'Missing or invalid recipient email (to)' };
  }
  try {
    const transporter = createTransporter();
    const info = await transporter.sendMail({
      from: fromOverride || SMTP_FROM,
      to: toAddr,
      subject: String(subject || '(no subject)'),
      text: text || '',
      html: html || undefined,
    });
    return {
      ok: true,
      messageId: info.messageId || '',
      resolvedTo: toAddr,
    };
  } catch (e) {
    return {
      ok: false,
      error: e.message || String(e),
      detail: e.code || undefined,
    };
  }
}

module.exports = {
  isSmtpConfigured,
  sendSmtpMail,
  smtpConfigSummary() {
    return {
      host: SMTP_HOST || null,
      port: SMTP_PORT,
      from: SMTP_FROM || null,
      secure: SMTP_SECURE,
      auth: SMTP_USER.length > 0,
    };
  },
};
