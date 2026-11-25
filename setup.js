// Rules for a desk's Save and a pro's PIN (golf.js). No Worker-only imports, so the tests run them in Node (test/setup.test.mjs).

// golf pro and marshal PINs: new ones are 6 digits; wrong tries are limited (pro())
export const PIN_LEN = 6, PIN_WAIT = 15 * 60000, PIN_TRIES_IP = 8, PIN_TRIES_ALL = 40;
// a safe string compare for keys and PINs
export function same(a, b) {
  const x = new TextEncoder().encode(String(a ?? '')), y = new TextEncoder().encode(String(b ?? ''));
  let d = x.length ^ y.length; for (let i = 0; i < Math.max(x.length, y.length); i++) d |= (x[i] || 0) ^ (y[i] || 0);
  return d === 0;
}
// a Save's PINs: each different, and new or changed ones at least 6 digits (4 and 5 digit ones from before still work)
export function pinProblem(pins, old = []) {
  const had = new Set(old.map((x) => `${x.id}:${x.pin}`)), seen = new Set();
  for (const x of pins) {
    if (seen.has(x.pin)) return `Two people have PIN ${x.pin}. Give each person their own.`;
    seen.add(x.pin);
    if (x.pin.length < PIN_LEN && !had.has(`${x.id}:${x.pin}`)) return `PINs need ${PIN_LEN} digits now (${x.name || 'one'} has ${x.pin.length}).`;
  }
  return null;
}
// Every Manager saves the whole setup, team list included, so a desk opened a while ago could undo what happened since
// (a late group a pro added, a player moved, another device's Save) and drop those teams' scores. Each team carries
// sv, the setup version it last changed in; the desk sends the version it loaded (setup.v). Teams changed after that
// keep the server's copy, and teams added after it stay even though the old copy doesn't list them. An app too old
// to send v can't take off a team that has scores. Teams the desk did change get the new version.
const teamSame = (a, b) => JSON.stringify({ ...a, sv: 0 }) === JSON.stringify({ ...b, sv: 0 });
export function mergeTeams(old, sent, base, v, scores = {}) {
  const known = Number.isFinite(Number(base)) && base !== null && base !== '' ? Number(base) : null;
  const was = new Map(old.map((t) => [t.id, t])), seen = new Set();
  const out = sent.map((t) => {
    seen.add(t.id);
    const o = was.get(t.id);
    if (o && known !== null && (o.sv || 0) > known) return o; // changed on the server since this desk loaded
    if (!o) return { ...t, sv: v };
    return teamSame(o, t) ? { ...t, sv: o.sv || 0 } : { ...t, sv: v };
  });
  for (const o of old) {
    if (seen.has(o.id)) continue;
    const newer = known !== null && (o.sv || 0) > known, scored = known === null && Object.values(scores[o.id] || {}).some((a) => (a || []).some((x) => x));
    if ((newer || scored) && out.length < 200) out.push(o);
  }
  return out;
}
// cleanSetup drops sv: put each team's back, and the new version on the one that changed
export function stamp(teams, old, changed, v) {
  const sv = new Map(old.map((t) => [t.id, t.sv || 0]));
  return teams.map((t) => ({ ...t, sv: t.id === changed ? v : sv.get(t.id) || 0 }));
}

