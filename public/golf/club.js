// Flagcast club accounts in the browser: sign in with email + password or an emailed code, then call the club API.
// Used by /golf/ (the club's page). The Manager app has its own copy of this flow in home.html.
const LS = 'flagcast:club-token';
export const token = {
  get: () => { try { return localStorage.getItem(LS) || ''; } catch { return ''; } },
  set: (t) => { try { t ? localStorage.setItem(LS, t) : localStorage.removeItem(LS); } catch {} },
};
// back from Sign in with Apple (/golf/signin/apple/): the session arrives in the address's #signin=… (never sent to a
// server) or a problem in #error=…; keep the one, show the other, and take both out of the address
export const signinError = (() => {
  try {
    const h = new URLSearchParams(location.hash.slice(1));
    if (h.get('signin')) token.set(h.get('signin'));
    if (h.has('signin') || h.has('error')) history.replaceState(null, '', location.pathname + location.search);
    return h.get('error') || '';
  } catch { return ''; }
})();
export async function api(op, body = {}) {
  const path = op === 'new' ? '/golf/api/new' : `/golf/api/club/${op}`;
  const r = await fetch(path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ token: token.get(), ...body }) });
  const j = await r.json().catch(() => ({}));
  if (r.status === 401 && !['verify', 'login'].includes(op)) token.set('');
  if (!r.ok) throw Object.assign(new Error(j.error || 'That didn’t work. Try again.'), { status: r.status });
  return j;
}
export const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
export const creditsText = (n) => (n < 0 ? 'Unlimited tournaments' : n === 1 ? '1 tournament left to make' : `${n} tournaments left to make`);
