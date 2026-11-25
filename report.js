// The end-of-day files a golf pro can download from the phone app or the pro page (the desk's Report makes the same
// two in the browser): results by flight, and every player's round ready to post to GHIN.
import { leaderboard, coursePar, fmtIndex, netDoubleBogey } from './public/golf/core.js';

// S: the public state (with scores). Rows of cells; the clients turn them into a CSV file.
export function resultsRows(S) {
  const flights = (S.flights || []).filter((fl) => S.teams.some((t) => t.flight === fl));
  const rows = [['Flight', 'Pos', 'Team', 'Players', 'Thru', 'Score', ...S.course.holes.map((h) => `H${h.n}`)]];
  const add = (fl, lines) => { for (const l of lines) rows.push([fl || '', l.pos, l.name, l.sub, l.thru, l.played ? l.score : '', ...l.card.map((r) => (r.done ? (S.format.show === 'gross' ? r.gross : r.net) ?? '' : ''))]); };
  for (const fl of flights) add(fl, leaderboard(S, S.scores, { flight: fl }));
  // teams in no flight (or with no flights at all): one list of their own
  const rest = S.teams.filter((t) => !flights.includes(t.flight));
  if (rest.length) add('', leaderboard({ ...S, teams: rest }, S.scores));
  return rows;
}

// ev: the full event (it has the GHIN numbers), S: the public state. null for a scramble (those can't be posted).
export function ghinRows(ev, S) {
  if (S.format.type === 'scramble') return null;
  const H = S.course.holes, par = coursePar(S), T = ev.course.tees || [];
  const rows = [['Player', 'GHIN number', 'Handicap Index', 'Course handicap', 'Date', 'Course', 'Tees', 'Course rating', 'Slope', 'Par', ...H.map((h) => `H${h.n}`), 'Holes played', 'Gross', 'Adjusted gross', 'Picked up on', 'Team']];
  for (const t of ev.teams) for (const p of t.players) {
    const arr = (S.scores[t.id] || {})[p.id] || [], tee = T.find((x) => x.id === p.tee) || (p.index != null ? T[0] : null);
    let gross = 0, adj = 0, n = 0; const pu = [];
    const holes = H.map((h, i) => {
      const v = arr[i]; if (v == null) return '';
      const cap = netDoubleBogey(h.par, p.hcp, h.hcp); n++;
      if (v === 0) { pu.push(h.n); adj += cap; return cap; } // picked up: counted as net double bogey
      gross += v; adj += Math.min(v, cap); return v;
    });
    if (!n) continue;
    rows.push([p.name, p.ghin || '', fmtIndex(p.index), p.hcp, ev.date || '', ev.course.name || ev.club || '', tee ? tee.name : '', tee ? tee.rating : '', tee ? tee.slope : '', tee && tee.par ? tee.par : par, ...holes, n, pu.length ? '' : gross, adj, pu.join(' '), t.name]);
  }
  return rows;
}
