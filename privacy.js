// How long Flagcast keeps what, and the daily tidy that keeps that promise (flagcast.app/privacy says the same; change both).
//   group spots on the map     wiped when the results are final, and at the latest by the tidy the morning after
//   camera recordings          KEEP_DAYS (stream.js: Cloudflare deletes them, the tidy catches any it missed)
//   emails, GHIN, pace times   PERSONAL_DAYS after the tournament
//   the whole tournament       KEEP_DAYS_ALL after it (not Demo ones), or HIDDEN_DAYS after a club deletes (hides) it
// Junior events (desk op 'privacy' { junior }) turn off the course map's other groups for golfers, Save your shot, notes
// between groups and invite emails. A team on ev.nocam asked to stay off camera: its golfers can't save shots and its clips go.
// No Worker-only imports: test/privacy.test.mjs runs it in Node.

export const DAY = 86400000;
export const KEEP_DAYS = 30;
export const PERSONAL_DAYS = 90;
export const KEEP_DAYS_ALL = 730;
export const HIDDEN_DAYS = 30;
export const REMOVED = 'Removed player';

// the tournament's day (its date, else when it was made), as ms
export function eventDay(ev) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(ev?.date || '');
  return m ? Date.UTC(+m[1], +m[2] - 1, +m[3]) : Number(ev?.created) || 0;
}

// what the tidy should do to one tournament today
export function tidyPlan(ev, now = Date.now()) {
  const day = eventDay(ev), age = day ? now - day : 0;
  return {
    personal: !ev.demo && !!day && age > PERSONAL_DAYS * DAY && !ev.tidied,
    replays: (ev.replays || []).some((r) => !r.url && now - (r.at || 0) > KEEP_DAYS * DAY),
    expired: !ev.demo && !!day && age > KEEP_DAYS_ALL * DAY,
  };
}

// emails, GHIN numbers and the invite log go (names, scores and results stay). → changed?
export function stripPersonal(ev) {
  let changed = false;
  for (const t of ev.teams || []) for (const p of t.players || []) {
    if (p.email) { p.email = ''; changed = true; }
    if (p.ghin) { p.ghin = ''; changed = true; }
  }
  for (const k of ['invites', 'inviteTests']) if (ev[k]) { delete ev[k]; changed = true; }
  return changed;
}

// replays of the live camera older than its recordings (KEEP_DAYS) can't play any more: take them off. → changed?
export function dropOldReplays(ev, now = Date.now()) {
  const keep = (ev.replays || []).filter((r) => r.url || now - (r.at || 0) <= KEEP_DAYS * DAY);
  if (keep.length === (ev.replays || []).length) return false;
  ev.replays = keep;
  if (ev.live?.take?.kind === 'replay' && !keep.some((r) => r.id === ev.live.take.replay)) ev.live.take = null;
  return true;
}

// a team that asked to stay off camera: its golfers' saved shots go. → changed?
export function dropTeamClips(ev, teamId) {
  const keep = (ev.replays || []).filter((r) => !(r.by === 'golfer' && r.team === teamId));
  if (keep.length === (ev.replays || []).length) return false;
  ev.replays = keep;
  if (ev.live?.take?.kind === 'replay' && !keep.some((r) => r.id === ev.live.take.replay)) ev.live.take = null;
  return true;
}

// the invite log only keeps players who are still in the tournament
export function pruneInvites(ev) {
  if (!ev.invites) return false;
  const ids = new Set((ev.teams || []).flatMap((t) => (t.players || []).map((p) => p.id)));
  let changed = false;
  for (const k of Object.keys(ev.invites)) if (!ids.has(k)) { delete ev.invites[k]; changed = true; }
  return changed;
}

const norm = (s) => String(s || '').trim().toLowerCase().replace(/\s+/g, ' ');
// players matching a name or an email exactly (case and spacing don't matter): [{ team, player, name, email }]
export function findPerson(ev, q) {
  const w = norm(q); if (w.length < 3) return [];
  return (ev.teams || []).flatMap((t) => (t.players || []).filter((p) => norm(p.name) === w || (p.email && norm(p.email) === w))
    .map((p) => ({ team: t.id, player: p.id, name: p.name, email: !!p.email })));
}

// someone asked Flagcast to delete their information: their name, email and GHIN go from the tournament (their scores
// stay, unnamed, so the team's results still add up), and so do their invite and their name on contest results. → how many
export function forgetPerson(ev, q) {
  const found = findPerson(ev, q); if (!found.length) return 0;
  const ids = new Set(found.map((f) => f.player)), names = new Set(found.map((f) => f.name).filter(Boolean));
  for (const t of ev.teams || []) for (const p of t.players || []) if (ids.has(p.id)) { p.name = REMOVED; p.email = ''; p.ghin = ''; }
  for (const id of ids) if (ev.invites) delete ev.invites[id];
  for (const c of ev.contests || []) for (const e of c.entries || []) if (ids.has(e.player) || names.has(e.name)) e.name = REMOVED;
  // a replay's label names the team ("Smith / Jones · tee shot"): one naming them loses the names, keeping what the shot was
  const lasts = [...names].map((n) => n.trim().split(/\s+/).pop().toLowerCase()).filter(Boolean);
  for (const r of ev.replays || []) {
    const words = String(r.label || '').toLowerCase().split(/[\s/·]+/);
    if (lasts.some((l) => words.includes(l)) || [...names].some((n) => String(r.label || '').includes(n))) r.label = r.label.includes('·') ? `${REMOVED} ·${r.label.split('·').pop()}` : REMOVED;
  }
  return found.length;
}

// what golfers see of a junior event: the flags that turn things off for them
export const juniorFlags = (ev) => (ev.junior ? { notesOff: true, clipsOff: true, everyoneOff: true } : {});
