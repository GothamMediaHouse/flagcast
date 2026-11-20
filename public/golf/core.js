// Flagcast: the scoring math, shared by every golf page (the cart, the screens, the desk and the live page).
// The server only stores what was entered; each page works out the leaderboard from it with these functions,
// so they all show the same numbers.
//
// event.format = { type: 'bestball' | 'stroke' | 'scramble' | 'stableford', count: 1 | 2 (best balls per hole),
//                  allowance: 0–100 (% of each playing handicap), show: 'net' | 'gross' }
// event.course.holes = [{ n: 1–18, par, yds, hcp: 1–18 (stroke index) }]
// event.teams = [{ id, name, flight, start (hole), hcp (scramble team handicap), players: [{ id, name, hcp }] }]
// scores[teamId] = { [playerId or 'T' for a scramble team]: [18 values: null = not yet, 0 = picked up, else strokes] }

export const FORMATS = {
  bestball: 'Best ball',
  stroke: 'Stroke play',
  scramble: 'Scramble',
  stableford: 'Stableford',
};

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
  const type = f.type || 'bestball';
  const count = type === 'stroke' ? 1 : Math.max(1, Math.min(4, f.count || 1));
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
export function entries(ev) {
  if ((ev.format || {}).type === 'stroke') {
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
  const lines = entries(ev).map((e) => {
    const sc = (scores || {})[e.teamId] || {};
    const card = teamCard(ev, e.team, f.type === 'stroke' ? { [e.team.players[0].id]: sc[e.team.players[0].id] } : sc);
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
    const who = ev.format?.type === 'scramble' ? [{ id: 'T', name: t.name }] : (t.players || []);
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
  if (ev.format?.type === 'scramble') return [];
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

// contest standings: closest to the pin (shortest distance wins) and long drive (longest wins)
export function contestLeader(c) {
  const list = (c.entries || []).filter((e) => e && e.name && Number(e.dist) > 0);
  list.sort((a, b) => (c.kind === 'ld' ? b.dist - a.dist : a.dist - b.dist));
  return list;
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

// ---- side games: a cart's own skins, Nassau and birdies, with who owes who at the end ----
// Played among the players in one cart (every team on its cart code). Flagcast only does the math; players settle up themselves.
// cfg = { skins: { on, amt, net, carry }, nassau: { on, amt, net, sides: { [playerKey]: 'A' | 'B' } }, birdies: { on, amt, net } }
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
  const pay = (from, to, amt) => { if (!amt || from === to) return; ledger[from] -= amt; ledger[to] += amt; };
  const out = { players, ledger, settle: [] };
  const n = players.length;

  // skins: a hole is a skin when one player has the lowest score alone; ties carry the skin to the next hole
  const sk = cfg.skins || {};
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
  const na = cfg.nassau || {};
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
  const bi = cfg.birdies || {};
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
