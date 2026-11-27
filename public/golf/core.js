// Flagcast: the scoring math, shared by every golf page (the cart, the screens, the desk and the live page).
// The server only stores what was entered; each page works out the leaderboard from it with these functions,
// so they all show the same numbers.
//
// event.format = { type: 'bestball' | 'shamble' | 'stroke' | 'scramble' | 'stableford' | 'match', count: 1 | 2 (best balls per hole),
//                  allowance: 0–100 (% of each playing handicap), show: 'net' | 'gross',
//                  match: 'singles' | 'fourball' | 'scramble' (match play only), cup: { on, a, b } (match play team cup: the two sides' names) }
// A shamble is scored like best ball (everyone plays from the best drive, then their own ball). Match play pairs teams in
// event.matches = [{ id, a: teamId, b: teamId }]; with a team cup each team has team.side = 'A' | 'B'.
// event.course.holes = [{ n: 1–18, par, yds, hcp: 1–18 (stroke index) }]
// event.teams = [{ id, name, flight, start (hole), hcp (scramble team handicap), players: [{ id, name, hcp }] }]
// scores[teamId] = { [playerId or 'T' for a scramble team]: [18 values: null = not yet, 0 = picked up, else strokes] }

export const FORMATS = {
  bestball: 'Best ball',
  stroke: 'Stroke play',
  scramble: 'Scramble',
  stableford: 'Stableford',
  shamble: 'Shamble',
  match: 'Match play',
};
export const MATCH_TYPES = { singles: 'Singles', fourball: 'Four-ball', scramble: 'Scramble' };

// one score for the whole team (a scramble, or a scramble match): it's entered under 'T' with the team's handicap
export const teamBall = (ev) => { const f = ev?.format || {}; return f.type === 'scramble' || (f.type === 'match' && f.match === 'scramble'); };
// the format's name, as the screens show it ("Four-ball match play")
export const formatName = (ev) => { const f = ev?.format || {}; return f.type === 'match' ? `${MATCH_TYPES[f.match || 'fourball'] || 'Four-ball'} match play` : FORMATS[f.type] || FORMATS.bestball; };
// can the event show each player on their own (the Individuals leaderboard)? Not when the team plays one ball
export const hasIndividuals = (ev) => !teamBall(ev) && (ev?.format?.type || 'bestball') !== 'stroke';

export function defaultHoles() {
  const par = [4, 5, 4, 3, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4, 4, 3, 4, 5];
  const hcp = [7, 3, 11, 15, 1, 9, 17, 5, 13, 8, 16, 2, 4, 12, 10, 18, 6, 14];
  const yds = { 3: 165, 4: 385, 5: 520 };
  return par.map((p, i) => ({ n: i + 1, par: p, yds: yds[p], hcp: hcp[i] }));
}

// strokes a player with this playing handicap gets on a hole with this stroke index (plus handicaps give strokes back)
export function strokesOn(h, si) {
  if (!h) return 0;
  if (h > 0) return Math.floor(h / 18) + (si <= h % 18 ? 1 : 0);
  const p = -h;
  return -(Math.floor(p / 18) + (si > 18 - (p % 18) ? 1 : 0));
}

// Handicap Index (GHIN) → course handicap, the World Handicap System way:
// Index × (Slope ÷ 113) + (Course Rating − Par), rounded. Plus handicaps are negative numbers here (+2.1 → -2.1).
export const coursePar = (ev) => ev.course.holes.reduce((a, h) => a + h.par, 0);
export function courseHcp(index, tee, par) {
  if (index == null || index === '' || !tee || !tee.slope || !tee.rating) return null;
  return Math.round(Number(index) * tee.slope / 113 + (tee.rating - (tee.par || par)));
}
export function parseIndex(v) {
  const s = String(v ?? '').trim(); if (!s) return null;
  const n = Number(s.replace(/^\+/, '')); if (!Number.isFinite(n)) return null;
  return s.startsWith('+') ? -n : n;
}
export const fmtIndex = (n) => (n == null || n === '' ? '' : n < 0 ? `+${-n}` : String(n));
// net double bogey: the most a hole can count for handicap posting (par + 2 + strokes received)
export const netDoubleBogey = (par, courseHandicap, si) => par + 2 + Math.max(0, strokesOn(courseHandicap, si));

// which holes the round is played on: all 18, the front 9 (1–9) or the back 9 (10–18) — event.format.nine = '' | 'front' | 'back'
export const playHoles = (ev) => { const n = ev?.format?.nine; return Array.from({ length: n ? 9 : 18 }, (_, i) => i + 1 + (n === 'back' ? 9 : 0)); };

export const playing = (hcp, allowance) => Math.round((Number(hcp) || 0) * (allowance ?? 100) / 100);

const isScore = (v) => typeof v === 'number' && v >= 0;

// one team's card, hole by hole: what counts on each hole for this format
export function teamCard(ev, team, sc) {
  const f = ev.format || {}, holes = ev.course.holes, allow = f.allowance ?? 100;
  // a shamble counts like best ball; a match's own card is its best ball (or one team ball in a scramble match)
  const type = teamBall(ev) ? 'scramble' : f.type === 'shamble' || f.type === 'match' || !f.type ? 'bestball' : f.type;
  const count = type === 'stroke' || f.type === 'match' ? 1 : Math.max(1, Math.min(4, f.count || 1));
  const s = sc || {};
  const rows = [], inPlay = new Set(playHoles(ev));
  for (let i = 0; i < 18; i++) {
    const hole = holes[i];
    if (!inPlay.has(i + 1)) { rows.push({ hole: hole.n, par: hole.par, gross: null, net: null, done: false, off: true }); continue; }
    let gross = null, net = null, pts = null, done = false, parFor = hole.par;
    if (type === 'scramble') {
      const v = (s.T || [])[i];
      if (v !== null && v !== undefined) {
        done = true;
        const st = strokesOn(playing(team.hcp, allow), hole.hcp);
        if (isScore(v) && v > 0) { gross = v; net = v - st; } else { gross = hole.par + 2 + st; net = hole.par + 2; }
      }
    } else {
      const ps = team.players || [];
      const entered = ps.map((p) => (s[p.id] || [])[i]);
      done = ps.length > 0 && entered.every((v) => v !== null && v !== undefined);
      if (done) {
        const each = ps.map((p, k) => {
          const v = entered[k];
          const st = strokesOn(playing(p.hcp, allow), hole.hcp);
          // picked up: counts as net double bogey (the handicap system's most on a hole), and 0 Stableford points
          if (!isScore(v) || v === 0) return { g: hole.par + 2 + st, n: hole.par + 2, pts: 0, gpts: 0, pu: true };
          const n = v - st;
          return { g: v, n, pts: Math.max(0, 2 + hole.par - n), gpts: Math.max(0, 2 + hole.par - v) };
        });
        const take = Math.min(count, each.length);
        if (type === 'stableford') {
          pts = [...each].sort((a, b) => b.pts - a.pts).slice(0, take).reduce((t, e) => t + e.pts, 0);
          const gp = [...each].sort((a, b) => b.gpts - a.gpts).slice(0, take).reduce((t, e) => t + e.gpts, 0);
          gross = gp; net = pts; // for Stableford these are points
        } else if (take === count) {
          gross = [...each].sort((a, b) => a.g - b.g).slice(0, take).reduce((t, e) => t + e.g, 0);
          net = [...each].sort((a, b) => a.n - b.n).slice(0, take).reduce((t, e) => t + e.n, 0);
        } else { gross = null; net = null; } // not enough balls holed: counts as no score
        parFor = hole.par * count;
      }
    }
    rows.push({ hole: hole.n, par: parFor, gross, net, done });
  }
  return rows;
}

// every line on the leaderboard (a stroke play event lists players, the rest list teams)
export function entries(ev, individual) {
  if ((ev.format || {}).type === 'stroke' || individual) {
    const out = [];
    for (const t of ev.teams || []) for (const p of t.players || []) {
      out.push({ key: `${t.id}:${p.id}`, teamId: t.id, name: p.name, sub: t.name, flight: t.flight || '', start: t.start || 1,
        team: { ...t, players: [p] } });
    }
    return out;
  }
  return (ev.teams || []).map((t) => ({ key: t.id, teamId: t.id, name: t.name || (t.players || []).map((p) => last(p.name)).join(' / '),
    sub: (t.players || []).map((p) => p.name).join(', '), flight: t.flight || '', start: t.start || 1, team: t }));
}

const last = (n) => String(n || '').trim().split(/\s+/).pop();

// the leaderboard: sorted, with positions (ties shown as T2) and holes played
export function leaderboard(ev, scores, opts = {}) {
  const f = ev.format || {}, stab = f.type === 'stableford';
  const mode = opts.mode || f.show || 'net';
  const lines = entries(ev, opts.individual).map((e) => {
    const sc = (scores || {})[e.teamId] || {};
    const card = teamCard(ev, e.team, f.type === 'stroke' || opts.individual ? { [e.team.players[0].id]: sc[e.team.players[0].id] } : sc);
    let toPar = 0, total = 0, played = 0, nr = false;
    for (const r of card) {
      if (!r.done) continue;
      played++;
      const v = mode === 'gross' ? r.gross : r.net;
      if (v === null) { nr = !stab; continue; }
      total += v;
      if (!stab) toPar += v - r.par;
    }
    return { ...e, card, played, total, toPar, nr, score: stab ? total : toPar };
  });
  const ph = playHoles(ev), full = ph.length, endH = ph[full - 1];
  const filtered = opts.flight ? lines.filter((l) => l.flight === opts.flight) : lines;
  const back = (l, from) => l.card.slice(from - 1).reduce((t, r) => t + (r.done ? ((mode === 'gross' ? r.gross : r.net) ?? 0) - (stab ? 0 : r.par) : 0), 0);
  filtered.sort((a, b) => {
    if (!a.played !== !b.played) return a.played ? -1 : 1;
    if (a.nr !== b.nr) return a.nr ? 1 : -1;
    const d = stab ? b.score - a.score : a.score - b.score;
    if (d) return d;
    // card-off for players who finished: back 9, back 6, back 3, last hole
    if (a.played === full && b.played === full) {
      for (const from of (full === 18 ? [10, 13, 16, 18] : [endH - 5, endH - 2, endH])) {
        const x = back(a, from), y = back(b, from);
        if (x !== y) return stab ? y - x : x - y;
      }
    }
    return b.played - a.played || a.name.localeCompare(b.name);
  });
  let pos = 0;
  filtered.forEach((l, i) => {
    const prev = filtered[i - 1];
    const tied = (o) => o && o.played && l.played && o.nr === l.nr && o.score === l.score;
    if (!tied(prev)) pos = i + 1;
    l.pos = l.played ? (tied(prev) || tied(filtered[i + 1]) ? `T${pos}` : String(pos)) : '';
    l.thru = l.played === full ? 'F' : l.played ? String(l.played) : (l.start && l.start !== 1 ? `Starts ${l.start}` : '—');
  });
  return filtered;
}

// every player on their own line, whatever the team format (a club championship's gross and net medal), with flights.
// Stableford events rank each player's own points; the rest rank each player's own score to par.
export function individuals(ev, scores, opts = {}) {
  if (!hasIndividuals(ev)) return [];
  const f = ev.format || {};
  return leaderboard({ ...ev, format: { ...f, type: f.type === 'stableford' ? 'stableford' : 'stroke', count: 1 } }, scores, { ...opts, individual: true });
}

// ---- match play: two teams head to head, hole by hole ----
// Singles: one player a side. Four-ball: each side's best ball. Scramble: one ball a side (entered as 'T', team handicap).
// Strokes come off the lowest player in the match (allowance first). A picked-up ball loses the hole to any score.
// The match ends when one side is more holes up than there are holes left (closed out "3&2"); holes after that don't count.
export function matchPlay(ev, scores, m) {
  const f = ev.format || {}, holes = ev.course.holes, allow = f.allowance ?? 100, gross = f.show === 'gross';
  const T = Object.fromEntries((ev.teams || []).map((t) => [t.id, t]));
  const A = T[m.a], B = T[m.b];
  const out = { id: m.id, a: m.a, b: m.b, holes: [], played: 0, diff: 0, toPlay: 0, done: false, started: false, winner: null, halved: false, text: '', thru: '', strokes: {} };
  if (!A || !B) { out.text = 'Not paired'; return out; }
  const one = teamBall(ev);
  const side = (t) => one ? [{ team: t.id, id: 'T', hcp: playing(t.hcp, allow) }]
    : (f.match === 'singles' ? (t.players || []).slice(0, 1) : (t.players || [])).map((p) => ({ team: t.id, id: p.id, hcp: playing(p.hcp, allow) }));
  const sa = side(A), sb = side(B), all = [...sa, ...sb];
  if (!sa.length || !sb.length) { out.text = 'Not paired'; return out; }
  const low = Math.min(...all.map((p) => p.hcp));
  for (const p of all) { p.rel = p.hcp - low; out.strokes[`${p.team}:${p.id}`] = p.rel; }
  const raw = (p, i) => ((((scores || {})[p.team] || {})[p.id]) || [])[i];
  const entered = (p, i) => { const v = raw(p, i); return v !== null && v !== undefined; };
  const val = (p, i) => { const v = raw(p, i); if (!isScore(v) || v === 0) return Infinity; return gross ? v : v - strokesOn(p.rel, holes[i].hcp); };
  const ph = playHoles(ev).map((h) => h - 1), start = A.start || 1, k0 = Math.max(0, ph.indexOf(start - 1));
  const order = [...ph.slice(k0), ...ph.slice(0, k0)];
  let diff = 0, played = 0;
  for (let k = 0; k < order.length; k++) {
    const i = order[k];
    const row = { hole: i + 1, r: null, after: out.done, sa: Object.fromEntries(sa.map((p) => [p.id, strokesOn(p.rel, holes[i].hcp)])), sb: Object.fromEntries(sb.map((p) => [p.id, strokesOn(p.rel, holes[i].hcp)])) };
    out.holes.push(row);
    if (out.done || !all.every((p) => entered(p, i))) continue;
    const x = Math.min(...sa.map((p) => val(p, i))), y = Math.min(...sb.map((p) => val(p, i)));
    row.r = x < y ? 'A' : y < x ? 'B' : 'H';
    diff += row.r === 'A' ? 1 : row.r === 'B' ? -1 : 0;
    played++;
    const left = order.length - (k + 1);
    if (Math.abs(diff) > left || left === 0) { out.done = true; out.toPlay = left; }
  }
  out.played = played; out.diff = diff; out.started = played > 0;
  if (!out.done) out.toPlay = order.length - played;
  const up = Math.abs(diff);
  if (out.done) {
    if (!diff) { out.halved = true; out.text = 'Halved'; }
    else { out.winner = diff > 0 ? 'A' : 'B'; out.text = out.toPlay ? `${up}&${out.toPlay}` : `${up} UP`; }
    out.thru = 'F';
  } else {
    out.text = !played ? '' : diff ? `${up} UP` : 'AS';
    out.thru = played ? String(played) : (start !== 1 ? `Starts ${start}` : '—');
    out.dormie = played > 0 && up > 0 && up === out.toPlay;
  }
  out.leader = diff > 0 ? 'A' : diff < 0 ? 'B' : null;
  return out;
}

// every match in the event, in the order the desk set them
export function matches(ev, scores) {
  return (ev.matches || []).map((m) => matchPlay(ev, scores, m));
}

// the match as one side sees it: "2 UP", "1 DOWN", "AS", "WON 3&2", "LOST 1 UP", "HALVED"
export function matchFor(r, teamId) {
  const me = r.a === teamId ? 'A' : r.b === teamId ? 'B' : null;
  if (!me || !r.started) return { text: r.thru && r.thru !== '—' ? r.thru : 'Not started', state: 'open' };
  if (r.done) return r.halved ? { text: 'HALVED', state: 'halved' } : { text: `${r.winner === me ? 'WON' : 'LOST'} ${r.text}`, state: r.winner === me ? 'won' : 'lost' };
  if (!r.leader) return { text: 'AS', state: 'level' };
  const up = Math.abs(r.diff);
  return r.leader === me ? { text: `${up} UP`, state: 'up' } : { text: `${up} DOWN`, state: 'down' };
}

// the team cup: 1 point a win, ½ a halve. "now" also counts the matches on the course as they stand
// (leader gets 1, all square ½ each); matches not started yet aren't counted
export function cup(ev, scores, list) {
  const f = ev.format || {}, c = f.cup || {};
  const rs = list || matches(ev, scores);
  const side = (id) => ((ev.teams || []).find((t) => t.id === id) || {}).side;
  const pts = { A: 0, B: 0 }, now = { A: 0, B: 0 };
  let left = 0;
  for (const r of rs) {
    // which cup side each half of the match plays for (normally a is A and b is B)
    const sa = side(r.a) === 'B' ? 'B' : side(r.b) === 'A' ? 'B' : 'A', sb = sa === 'A' ? 'B' : 'A';
    const give = (o, w) => { if (w === 'A') o[sa] += 1; else if (w === 'B') o[sb] += 1; else { o[sa] += 0.5; o[sb] += 0.5; } };
    if (r.done) { give(pts, r.winner); give(now, r.winner); }
    else { left++; if (r.started) give(now, r.leader); }
  }
  const total = rs.length;
  return { on: !!c.on, a: c.a || 'Reds', b: c.b || 'Blues', A: pts.A, B: pts.B, nowA: now.A, nowB: now.B, left, total, toWin: total / 2 + 0.5 };
}
// 6.5 → "6½"
export const fmtPts = (n) => `${Math.floor(n) || (n % 1 ? '' : '0')}${n % 1 ? '½' : ''}`;

export function fmtPar(n, stab) {
  if (stab) return `${n} pts`;
  if (n === 0) return 'E';
  return n > 0 ? `+${n}` : `−${-n}`;
}

// how a single hole went for everyone, for the par 3 screens
export function holeStats(ev, scores, holeNo) {
  const i = holeNo - 1, par = ev.course.holes[i].par;
  const out = { holeNo, par, eagle: 0, birdie: 0, par0: 0, bogey: 0, worse: 0, aces: [], n: 0, total: 0 };
  for (const t of ev.teams || []) {
    const sc = (scores || {})[t.id] || {};
    const who = teamBall(ev) ? [{ id: 'T', name: t.name }] : (t.players || []);
    for (const p of who) {
      const v = (sc[p.id] || [])[i];
      if (!isScore(v) || v === 0) continue;
      out.n++; out.total += v;
      const d = v - par;
      if (v === 1) out.aces.push({ name: p.name, team: t.name });
      if (d <= -2) out.eagle++; else if (d === -1) out.birdie++; else if (d === 0) out.par0++; else if (d === 1) out.bogey++; else out.worse++;
    }
  }
  out.avg = out.n ? out.total / out.n : null;
  return out;
}

// gross skins: a hole is won when one player has the lowest score alone; ties carry over when carry is on
export function skins(ev, scores, carry = true) {
  if (teamBall(ev)) return [];
  const res = []; let pot = 1;
  for (let i = 0; i < 18; i++) {
    let best = Infinity, who = [], all = true;
    for (const t of ev.teams || []) for (const p of t.players || []) {
      const v = ((scores || {})[t.id]?.[p.id] || [])[i];
      if (v === null || v === undefined) { all = false; continue; }
      if (!isScore(v) || v === 0) continue;
      if (v < best) { best = v; who = [{ name: p.name, team: t.name }]; } else if (v === best) who.push({ name: p.name, team: t.name });
    }
    if (!all || !who.length) { res.push({ hole: i + 1, open: true }); pot = 1; continue; }
    if (who.length === 1) { res.push({ hole: i + 1, won: who[0], score: best, worth: pot }); pot = 1; }
    else { res.push({ hole: i + 1, tied: who.length, score: best }); pot = carry ? pot + 1 : 1; }
  }
  return res;
}

// contest standings: closest to the pin (shortest distance wins) and long drive (longest wins).
// checked: only the entries that count (not a golfer's entry still waiting for a pro's OK), for the TVs
export function contestLeader(c, checked = false) {
  const list = (c.entries || []).filter((e) => e && e.name && Number(e.dist) > 0 && (!checked || e.ok !== false));
  list.sort((a, b) => (c.kind === 'ld' ? b.dist - a.dist : a.dist - b.dist));
  return list;
}

// ---- cameras golfers can watch (the Cameras tab, the live page, the TVs' labels) ----
// event.cams = { [hole 1–18, or 0 for the clubhouse]: link } (Flagcast Admin, or a pro's phone with Go live)
// event.golive = { [hole]: { by } } (a phone sending now), event.camsOff = [holes staff hid from golfers],
// event.clipsOff = true when golfers can't save their shot (op 'clip').
export const CLUBHOUSE = 0;
export const CLIP_BACK = 15; // a golfer's "Save your shot": the camera from this many seconds before they tapped
export const CAM_KINDS = { pro: 'Live from the pro', contest: 'Contest holes', par3: 'Par 3s', club: 'Around the club', hole: 'More cameras' };
const ORDER = ['pro', 'contest', 'par3', 'club', 'hole'];
const contestName = (c) => c.label || (c.kind === 'ld' ? 'Long drive' : 'Closest to the pin');
/**
 * Every camera, each once, in the order the Cameras tab shows them: the pro's phone, contest holes, par 3s,
 * around the club (clubhouse, then the 18th green), any other hole.
 * → [{ n, url, hls, kind, title, sub, by (who's sending from a phone), contests: [contest], off }]
 * all: true keeps the cameras staff hid (the desk's list, the TVs); otherwise they're left out.
 */
export function camList(ev, { all = false } = {}) {
  const off = new Set((ev?.camsOff || []).map(Number)), live = ev?.golive || {}, holes = ev?.course?.holes || [];
  const out = [];
  for (const [k, url] of Object.entries(ev?.cams || {})) {
    const n = Number(k);
    if (!url || !Number.isInteger(n) || n < 0 || n > 18 || (n && !holes[n - 1])) continue;
    if (!all && off.has(n)) continue;
    const h = holes[n - 1], contests = n ? (ev.contests || []).filter((c) => c.hole === n) : [];
    const by = live[n] ? String(live[n].by ?? live[n] ?? '') : null;
    const kind = by != null ? 'pro' : contests.length ? 'contest' : n === 0 ? 'club' : h.par === 3 ? 'par3' : n === 18 ? 'club' : 'hole';
    const title = n === 0 ? 'Clubhouse' : kind === 'club' ? '18th green' : `Hole ${n}`;
    const facts = n ? [`Par ${h.par}`, h.yds ? `${h.yds} yds` : ''] : [];
    const sub = [...contests.map(contestName), ...facts].filter(Boolean).join(' · ');
    out.push({ n, url, hls: /\.m3u8(\?|$)/.test(url), kind, title, sub, by: by || '', contests, off: off.has(n) });
  }
  return out.sort((a, b) => ORDER.indexOf(a.kind) - ORDER.indexOf(b.kind) || a.n - b.n);
}
/** the label for one camera, wherever it shows ("Hole 7 · Closest to the pin", "Clubhouse", "Live from the pro · Dave") */
export function camTitle(ev, n) {
  const c = camList(ev, { all: true }).find((x) => x.n === Number(n));
  if (!c) return Number(n) === 0 ? 'Clubhouse' : `Hole ${n}`;
  return [c.title, ...c.contests.map(contestName)].join(' · ');
}

// does a golfer's entry wait for a pro's OK? check 'all': always. 'none': never. 'top' (the default): when it would make the top 3
export function contestNeedsOk(c, others, e) {
  if (c.check === 'none') return false;
  if (c.check === 'all') return true;
  const better = (others || []).filter((x) => x && Number(x.dist) > 0 && (c.kind === 'ld' ? x.dist >= e.dist : x.dist <= e.dist)).length;
  return better < 3;
}

// a word for the pro next to a golfer's entry that looks wrong ('' when it looks fine)
export function contestFlag(c, e) {
  if (!e || e.by !== 'golfer') return '';
  if (c.kind === 'ld') {
    if (e.gps && Math.abs(e.gps - e.dist) > 25) return `GPS from the tee said ${Math.round(e.gps)} yds`;
    const rest = (c.entries || []).filter((x) => x !== e && x.name !== e.name && Number(x.dist) > 0).map((x) => x.dist);
    if (rest.length >= 2 && e.dist > Math.max(...rest) + 30) return `${Math.round(e.dist - Math.max(...rest))} yds past everyone else`;
  } else if (e.dist < 0.5) return 'Under 6 inches';
  return '';
}

export function fmtDist(c, d) {
  d = Number(d) || 0;
  if (c.kind === 'ld') return `${Math.round(d)} yds`;
  const inches = Math.round(d * 12), ft = Math.floor(inches / 12), inch = inches % 12;
  return `${ft} ft ${inch} in`;
}

// the scorecard mark for a score: circle for birdie, double circle for eagle or better, square for bogey, double square worse
export function mark(v, par) {
  if (typeof v !== 'number' || v <= 0) return '';
  const d = v - par;
  return d <= -2 ? 'eagle' : d === -1 ? 'birdie' : d === 1 ? 'bogey' : d >= 2 ? 'double' : '';
}

// ---- side games: a cart's own games, scored in points (no money), with each player's running total ----
// Played among the players in one cart (every team on its cart code). Points only: Flagcast has no money in it.
// cfg = { skins: { on, amt, net, carry }, nassau: { on, amt, net, sides: { [playerKey]: 'A' | 'B' } }, birdies: { on, amt, net },
//   stableford: { on, net }, vegas: { on, amt, net, sides }, wolf: { on, amt, net, picks: { [hole]: playerKey | 'lone' } },
//   closest / longDrive: { on, amt, picks: { [hole]: playerKey } } }. Same math as the players' app (Core.swift).
export function sideGames(ev, scores, teamIds, cfg = {}) {
  const allow = ev.format?.allowance ?? 100, holes = ev.course.holes;
  const teams = teamIds.map((id) => (ev.teams || []).find((t) => t.id === id)).filter(Boolean);
  const players = [];
  for (const t of teams) for (const p of t.players || []) players.push({ key: `${t.id}:${p.id}`, id: p.id, team: t.id, name: p.name || 'Player', hcp: playing(p.hcp, allow) });
  // first names, with a last initial where two players share one
  const first = (n) => String(n).trim().split(/\s+/)[0];
  for (const p of players) {
    const same = players.filter((q) => first(q.name) === first(p.name)).length > 1;
    const parts = String(p.name).trim().split(/\s+/);
    p.short = same && parts.length > 1 ? `${parts[0]} ${parts[parts.length - 1][0]}.` : first(p.name);
  }
  const raw = (p, i) => (((scores || {})[p.team] || {})[p.id] || [])[i];
  const entered = (p, i) => { const v = raw(p, i); return v !== null && v !== undefined; };
  // a hole's score for the games: picked up = net double bogey, like the main leaderboard
  const val = (p, i, net) => {
    const v = raw(p, i), st = strokesOn(p.hcp, holes[i].hcp);
    if (!isScore(v) || v === 0) return net ? holes[i].par + 2 : holes[i].par + 2 + st;
    return net ? v - st : v;
  };
  const start = teams[0]?.start || 1;
  const ph = playHoles(ev).map((h) => h - 1), k0 = Math.max(0, ph.indexOf(start - 1));
  const order = [...ph.slice(k0), ...ph.slice(0, k0)]; // hole indexes this round plays, from the starting hole
  const ledger = Object.fromEntries(players.map((p) => [p.key, 0]));
  const tally = {}; let game = '';
  const pay = (from, to, amt) => {
    if (!amt || from === to) return;
    ledger[from] -= amt; ledger[to] += amt;
    const t = (tally[game] ||= {}); t[from] = (t[from] || 0) - amt; t[to] = (t[to] || 0) + amt;
  };
  const out = { players, ledger, settle: [] };
  const n = players.length;

  // skins: a hole is a skin when one player has the lowest score alone; ties carry the skin to the next hole
  const sk = cfg.skins || {}; game = 'skins';
  if (sk.on && n >= 2) {
    const amt = Number(sk.amt) || 0, rows = []; let pot = 1, won = Object.fromEntries(players.map((p) => [p.key, 0]));
    for (const i of order) {
      if (!players.every((p) => entered(p, i))) { rows.push({ hole: i + 1, open: true, pot }); continue; }
      const live = players.filter((p) => isScore(raw(p, i)) && raw(p, i) > 0);
      const best = Math.min(...live.map((p) => val(p, i, sk.net)));
      const who = live.filter((p) => val(p, i, sk.net) === best);
      if (who.length === 1) {
        rows.push({ hole: i + 1, winner: who[0].key, score: best, worth: pot });
        won[who[0].key] += pot;
        for (const p of players) pay(p.key, who[0].key, amt * pot);
        pot = 1;
      } else { rows.push({ hole: i + 1, tied: who.length, score: isFinite(best) ? best : null, pot }); pot = sk.carry === false ? 1 : pot + 1; }
    }
    out.skins = { rows, won, carrying: rows.some((r) => !r.open) ? pot - 1 : 0 };
  }

  // Nassau: side A against side B, match play on the best score of each side; front 9, back 9 and all 18 are three bets
  const na = cfg.nassau || {}; game = 'nassau';
  if (na.on && n >= 2) {
    const sides = { A: [], B: [] };
    const set = na.sides || {};
    players.forEach((p, k) => {
      const s = set[p.key] || (teams.length >= 2 ? (p.team === teams[0].id ? 'A' : 'B') : (k < Math.ceil(n / 2) ? 'A' : 'B'));
      sides[s === 'B' ? 'B' : 'A'].push(p);
    });
    if (sides.A.length && sides.B.length) {
      const amt = Number(na.amt) || 0;
      const seg = (from, to, label) => {
        let a = 0, b = 0, played = 0, all = true;
        for (let i = from; i <= to; i++) {
          if (![...sides.A, ...sides.B].every((p) => entered(p, i))) { all = false; continue; }
          played++;
          const x = Math.min(...sides.A.map((p) => val(p, i, na.net))), y = Math.min(...sides.B.map((p) => val(p, i, na.net)));
          if (x < y) a++; else if (y < x) b++;
        }
        const diff = a - b, done = all && played === to - from + 1;
        const r = { label, played, holes: to - from + 1, diff, done, winner: done && diff ? (diff > 0 ? 'A' : 'B') : null };
        if (r.winner) {
          const W = sides[r.winner], L = sides[r.winner === 'A' ? 'B' : 'A'];
          for (const l of L) for (const w of W) pay(l.key, w.key, amt / W.length);
        }
        return r;
      };
      out.nassau = { sides: { A: sides.A.map((p) => p.key), B: sides.B.map((p) => p.key) }, segs: ev.format?.nine ? [seg(ph[0], ph[8], 'Match')] : [seg(0, 8, 'Front 9'), seg(9, 17, 'Back 9'), seg(0, 17, 'Overall')] };
    }
  }

  // birdies: each birdie (an eagle or better counts twice) collects from every other player in the cart
  const bi = cfg.birdies || {}; game = 'birdies';
  if (bi.on && n >= 2) {
    const amt = Number(bi.amt) || 0, list = [];
    for (const p of players) for (const i of order) {
      const v = raw(p, i); if (!isScore(v) || v === 0) continue;
      const d = (bi.net ? v - strokesOn(p.hcp, holes[i].hcp) : v) - holes[i].par;
      if (d > -1) continue;
      const count = d <= -2 ? 2 : 1;
      list.push({ key: p.key, hole: i + 1, count, eagle: d <= -2 });
      for (const q of players) pay(q.key, p.key, amt * count);
    }
    out.birdies = { list };
  }

  const hasScore = (p, i) => isScore(raw(p, i)) && raw(p, i) > 0;
  const sideOf = (g, p, k) => (g.sides || {})[p.key] || (teams.length >= 2 ? (p.team === teams[0].id ? 'A' : 'B') : (k < Math.ceil(n / 2) ? 'A' : 'B'));
  const stake = (g, d) => { const v = Number(g.amt ?? d); return Number.isFinite(v) ? v : 0; };

  // Stableford: points against par on each hole (net double bogey or worse 0, bogey 1, par 2, birdie 3, eagle 4).
  // Its own table: these points don't change hands.
  const sf = cfg.stableford || {};
  if (sf.on && n >= 2) {
    const net = sf.net !== false;
    out.stableford = players.map((p) => {
      let points = 0, thru = 0;
      for (const i of order) {
        if (!entered(p, i)) continue;
        thru++;
        if (!hasScore(p, i)) continue; // a pick-up scores nothing
        const v = raw(p, i), s = net ? v - strokesOn(p.hcp, holes[i].hcp) : v;
        points += Math.max(0, 2 + holes[i].par - s);
      }
      return { key: p.key, points, thru };
    });
  }

  // Vegas: two against two. Each side's two scores make a number, low score first (a 4 and a 5 make 45); the lower number wins the difference.
  const vg = cfg.vegas || {}; game = 'vegas';
  if (vg.on && n >= 2) {
    const net = vg.net !== false, amt = stake(vg, 1), A = [], B = [];
    players.forEach((p, k) => (sideOf(vg, p, k) === 'B' ? B : A).push(p));
    const sides = { A: A.map((p) => p.key), B: B.map((p) => p.key) };
    if (A.length === 2 && B.length === 2) {
      const num = (s, i) => { const v = s.map((p) => val(p, i, net)).sort((x, y) => x - y); return Number(`${v[0]}${v[1]}`); };
      const rows = []; let total = 0;
      for (const i of order) {
        if (![...A, ...B].every((p) => entered(p, i))) continue;
        const a = num(A, i), b = num(B, i);
        rows.push({ hole: i + 1, a, b });
        total += b - a; // positive is good for side A
        if (a !== b) { const W = b > a ? A : B, L = b > a ? B : A; W.forEach((w, k) => pay(L[k].key, w.key, Math.abs(b - a) * amt)); }
      }
      out.vegas = { sides, holes: rows, total };
    } else { out.vegas = { sides, holes: [], total: 0 }; out.vegasNeedsFour = true; }
  }

  // Wolf: the wolf rotates in cart order. After the tee shots the wolf takes a partner or goes it alone ("lone"),
  // then the best ball on each side wins the hole. A lone wolf plays for double, both ways.
  const wf = cfg.wolf || {}; game = 'wolf';
  if (wf.on && n >= 3) {
    const net = wf.net !== false, amt = stake(wf, 1), picks = wf.picks || {};
    out.wolf = { holes: order.map((i, k) => {
      const wolf = players[k % n], pick = picks[i + 1];
      const partner = pick === 'lone' ? 'lone' : players.find((p) => p.key === pick && p.key !== wolf.key)?.key ?? null;
      let result = null;
      if (partner && players.every((p) => entered(p, i))) {
        const mine = players.filter((p) => p.key === wolf.key || p.key === partner), rest = players.filter((p) => !mine.includes(p));
        const best = (s) => Math.min(...s.filter((p) => hasScore(p, i)).map((p) => val(p, i, net)));
        const x = best(mine), y = best(rest), st = partner === 'lone' ? amt * 2 : amt;
        if (x < y) { result = 'wolf'; for (const l of rest) for (const w of mine) pay(l.key, w.key, st / mine.length); }
        else if (y < x) { result = 'others'; for (const l of mine) for (const w of rest) pay(l.key, w.key, st / mine.length); }
        else result = 'tie';
      }
      return { hole: i + 1, wolf: wolf.key, partner, result };
    }) };
  }

  // closest to the pin on the par 3s, long drive on the par 5s: the cart picks who won, everyone else gives the stake
  const pickGame = (g, par, name) => {
    game = name;
    if (!g?.on || n < 2) return undefined;
    const amt = stake(g, 2), picks = g.picks || {};
    return order.filter((i) => holes[i].par === par).map((i) => {
      const w = players.find((p) => p.key === picks[i + 1])?.key ?? null;
      if (w) for (const p of players) pay(p.key, w, amt);
      return { hole: i + 1, winner: w };
    });
  };
  const ctp = pickGame(cfg.closest, 3, 'closest'), ld = pickGame(cfg.longDrive, 5, 'longDrive');
  if (ctp) out.closest = ctp;
  if (ld) out.longDrive = ld;
  out.tally = tally;

  // who pays who: the fewest payments that settle everyone up
  const round = (x) => Math.round(x * 100) / 100;
  const owe = players.map((p) => ({ key: p.key, v: round(-ledger[p.key]) })).filter((x) => x.v > 0.004).sort((a, b) => b.v - a.v);
  const get = players.map((p) => ({ key: p.key, v: round(ledger[p.key]) })).filter((x) => x.v > 0.004).sort((a, b) => b.v - a.v);
  let i = 0, j = 0;
  while (i < owe.length && j < get.length) {
    const m = round(Math.min(owe[i].v, get[j].v));
    if (m > 0) out.settle.push({ from: owe[i].key, to: get[j].key, amt: m });
    owe[i].v = round(owe[i].v - m); get[j].v = round(get[j].v - m);
    if (owe[i].v <= 0.004) i++;
    if (get[j].v <= 0.004) j++;
  }
  return out;
}

// what the course map's group card shows about one group: its players, holes played, score and place.
// For stroke play (a line per player) the group's score and place are its best player's; each player has their own.
export function groupInfo(ev, scores, teamId) {
  const team = (ev.teams || []).find((t) => t.id === teamId); if (!team) return null;
  const stab = ev.format?.type === 'stableford', lines = leaderboard(ev, scores).filter((l) => l.teamId === teamId);
  const best = lines.find((l) => l.played) || lines[0];
  const per = lines.length > 1;
  return {
    name: best ? (per ? team.name || best.sub : best.name) : team.name,
    thru: best ? best.thru : '—', score: best && best.played ? fmtPar(best.score, stab) : '—', pos: best && best.pos ? best.pos : '—',
    players: (team.players || []).map((p) => {
      const l = per ? lines.find((x) => x.key === `${teamId}:${p.id}`) : null;
      // otherwise their own gross score to par over the holes they've finished
      let d = 0, n = 0; ((scores || {})[teamId]?.[p.id] || []).forEach((v, i) => { if (typeof v === 'number' && v > 0) { d += v - (ev.course?.holes?.[i]?.par || 4); n++; } });
      return { id: p.id, name: p.name, hcp: p.hcp, today: l && l.played ? fmtPar(l.score, stab) : n && !teamBall(ev) ? `${fmtPar(d)} gross` : '' };
    }),
  };
}
