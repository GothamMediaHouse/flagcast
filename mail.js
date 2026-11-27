// Flagcast's emails: a branded HTML version (green header with the Flagcast logo, paper-coloured card, one button)
// plus the plain-text version, both sent through Resend. Mail clients get both and show the one they can.
// The logo is a PNG on flagcast.app because Gmail and Outlook don't show SVG.
// No Worker-only imports: test/mail.test.mjs runs it in Node.

const SITE = 'https://flagcast.app';
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const C = { paper: '#f4f1e6', card: '#fffdf6', ink: '#14201a', muted: '#56625a', line: '#d8d2bf', green: '#123628', flag: '#e8c547' };
const FONT = "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif";

/**
 * The HTML email. m: { title, lines: [paragraph...], code?, button?: { label, url }, note? }
 * Text in m is plain text; it is escaped here.
 */
export function mailHtml(m) {
  const p = (t, style = '') => `<p style="margin:0 0 16px;font:16px/1.5 ${FONT};color:${C.ink};${style}">${esc(t)}</p>`;
  const code = m.code ? `<div style="margin:8px 0 24px;padding:18px 0;background:${C.paper};border:1px solid ${C.line};border-radius:12px;text-align:center;font:700 36px/1 ui-monospace,Menlo,Consolas,monospace;letter-spacing:8px;color:${C.green}">${esc(m.code)}</div>` : '';
  const btn = m.button ? `<table role="presentation" cellpadding="0" cellspacing="0" style="margin:8px 0 24px"><tr><td style="background:${C.green};border-radius:10px">`
    + `<a href="${esc(m.button.url)}" style="display:inline-block;padding:14px 26px;font:600 16px/1 ${FONT};color:${C.paper};text-decoration:none;border-radius:10px">${esc(m.button.label)}</a></td></tr></table>` : '';
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">`
    + `<meta name="color-scheme" content="light only"><title>${esc(m.title)}</title></head>`
    + `<body style="margin:0;padding:0;background:${C.paper}">`
    + `<div style="display:none;max-height:0;overflow:hidden">${esc(m.preview || m.lines?.[0] || '')}</div>`
    + `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:${C.paper}"><tr><td align="center" style="padding:24px 12px">`
    + `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:${C.card};border:1px solid ${C.line};border-radius:16px;overflow:hidden">`
    + `<tr><td style="background:${C.green};padding:22px 28px;border-bottom:4px solid ${C.flag}"><img src="${SITE}/brand/email-logo.png" width="140" height="52" alt="Flagcast" style="display:block;border:0"></td></tr>`
    + `<tr><td style="padding:28px">`
    + `<h1 style="margin:0 0 16px;font:700 22px/1.3 ${FONT};color:${C.ink}">${esc(m.title)}</h1>`
    + (m.lines || []).map((t) => p(t)).join('') + code + btn
    + (m.note ? p(m.note, `font-size:14px;color:${C.muted};margin:0`) : '')
    + `</td></tr></table>`
    + `<p style="margin:16px 0 0;font:13px/1.5 ${FONT};color:${C.muted}">Flagcast · live golf for your club · <a href="${SITE}" style="color:${C.muted}">flagcast.app</a></p>`
    + `</td></tr></table></body></html>`;
}

/** The plain-text version of the same email */
export function mailText(m) {
  return [m.title, '', ...(m.lines || []).flatMap((t) => [t, '']), ...(m.code ? [m.code, ''] : []),
    ...(m.button ? [`${m.button.label}: ${m.button.url}`, ''] : []), ...(m.note ? [m.note, ''] : []), 'Flagcast · flagcast.app'].join('\n');
}

// The emails Flagcast sends. Each returns { subject, title, lines, code?, button?, note? }.
const MANAGER = { label: 'Open Flagcast', url: `${SITE}/golf/` };
export const EMAILS = {
  code: (code) => ({ subject: `${code} is your Flagcast sign-in code`, preview: `Your code is ${code}. It works for 15 minutes.`,
    title: 'Your sign-in code', lines: ['Type this code in Flagcast to sign in. It works for 15 minutes.'], code,
    note: 'If you didn’t ask for this, you can ignore this email. Nobody can sign in without the code.' }),
  added: (club, by) => ({ subject: `You’ve been added to ${club} on Flagcast`, title: `Welcome to ${club}`,
    lines: [`${by || 'Flagcast'} added you to ${club} on Flagcast.`, 'Open Flagcast Manager, or the website, and sign in with this email address to see the club’s tournaments.'],
    button: MANAGER, note: `No Manager app yet? Download it at ${SITE}` }),
  approved: (club) => ({ subject: `${club} is ready on Flagcast`, title: `${club} is ready`,
    lines: [`Good news: ${club} is approved on Flagcast.`, 'Sign in with this email address and make your first tournament.'], button: MANAGER }),
  setUp: (club) => ({ subject: `${club} is set up on Flagcast`, title: `${club} is set up`,
    lines: [`Flagcast has set up ${club} for you.`, 'Download Flagcast Manager, open it and sign in with this email address. We email you a code, so there’s no password. Your tournaments will be there.'],
    button: { label: 'Download Flagcast Manager', url: `${SITE}/download/` } }),
  newClub: (name, details) => ({ subject: `New club asking for Flagcast: ${name}`, title: `${name} wants Flagcast`,
    lines: details.filter(Boolean), button: { label: 'Review in Admin', url: `${SITE}/golf/admin/` } }),
};
