// Flagcast club accounts in the browser: sign in with an emailed code, then call the club API.
// Used by /golf/ (the club's page). The Manager app has its own copy of this flow in home.html.
const LS = 'flagcast:club-token';
export const token = {
  get: () => { try { return localStorage.getItem(LS) || ''; } catch { return ''; } },
  set: (t) => { try { t ? localStorage.setItem(LS, t) : localStorage.removeItem(LS); } catch {} },
};
export async function api(op, body = {}) {
  const path = op === 'new' ? '/golf/api/new' : `/golf/api/club/${op}`;
  const r = await fetch(path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ token: token.get(), ...body }) });
  const j = await r.json().catch(() => ({}));
  if (r.status === 401 && op !== 'verify') token.set('');
  if (!r.ok) throw Object.assign(new Error(j.error || 'That didn’t work. Try again.'), { status: r.status });
  return j;
}
export const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
export const creditsText = (n) => (n < 0 ? 'Unlimited tournaments' : n === 1 ? '1 tournament left to make' : `${n} tournaments left to make`);
