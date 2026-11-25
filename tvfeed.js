// The feed the native Flagcast TV apps draw (tv.js serves it): the board's pages as data. No Cloudflare imports, so tests run it in Node.
import { leaderboard, fmtPar, FORMATS, formatName, matches, cup, fmtPts, individuals, hasIndividuals } from './public/golf/core.js';

const abs = (origin, u) => (!u ? '' : /^https:\/\//.test(u) ? u : u.startsWith('/') ? origin + u : '');
const isHLS = (u) => /^https:\/\/.+\.m3u8(\?|$)/.test(u || '');

/**
 * What a native TV app draws: the same pages the board shows (board/index.html), as data, for one screen.
 * Pages: lb (a leaderboard page), cam (a par 3 camera, HLS only), sponsor, sponsors, phone (QR for live scores).
 * The board's other pages (contests, skins, schedule, fundraising) come later; a playlist with only those gets the leaderboard.
 */
export function tvFeed(S, screenId, origin = 'https://flagcast.app') {
  const now = Date.now(), stab = S.format?.type === 'stableford', rows = S.screens?.rows || 10, secsDefault = S.screens?.seconds || 12;
  const sponsorOf = (x) => ({ name: x.name, line: x.line || '', logo: x.logo ? `${origin}/golf/api/tv/sponsor/${S.id}/${x.id}` : '' });
  const spot = (k, hole) => (S.sponsors || []).filter((x) => x.spot === k && (!hole || (x.holes || []).includes(hole)));
  const mode = stab ? 'Points' : S.format?.show === 'gross' ? 'Gross' : 'Net';
  const cams = { ...(S.cams || {}), ...(S.live?.cams || {}) };
  const lbPages = (fl, secs) => {
    const lb = leaderboard(S, S.scores || {}, { flight: fl || null });
    if (!lb.length) return [];
    const pages = Math.min(4, Math.max(1, Math.ceil(lb.length / rows))), lsp = spot('leaderboard')[0];
    return Array.from({ length: pages }, (_, p) => ({
      k: 'lb', secs: secs || secsDefault, title: 'Leaderboard',
      sub: `${fl ? `Flight ${fl}` : formatName(S)} · ${mode}${S.locked ? ' · Final results' : ''}`,
      page: p + 1, pages, sponsor: lsp ? sponsorOf(lsp) : null, points: stab,
      rows: lb.slice(p * rows, p * rows + rows).map((l) => ({ pos: String(l.pos), name: l.name, sub: l.sub && l.sub !== l.name ? l.sub : '',
        score: l.played ? fmtPar(l.score, stab).replace(' pts', '') : '—', under: !stab && !!l.played && l.score < 0, thru: String(l.thru || '').replace('Starts ', '#') })),
    }));
  };
  // match play and Individuals go to the TV apps as leaderboard pages too, so every TV app can draw them as they are:
  // a match is a row (its number, "Fox / Lee v Park / Ortiz", "2 UP", thru) and the cup score goes in the subtitle
  const tname = (id) => { const t = (S.teams || []).find((x) => x.id === id); return t ? t.name || (t.players || []).map((p) => String(p.name || '').split(' ').pop()).join(' / ') : ''; };
  const matchPages = (secs) => {
    const list = matches(S, S.scores || {}); if (!list.length) return [];
    const c = cup(S, S.scores || {}, list), per = rows, pages = Math.min(4, Math.ceil(list.length / per)), lsp = spot('leaderboard')[0];
    return Array.from({ length: pages }, (_, p) => ({
      k: 'lb', secs: secs || secsDefault, title: 'Matches',
      sub: `${formatName(S)}${c.on ? ` · ${c.a} ${fmtPts(c.A)}, ${c.b} ${fmtPts(c.B)}` : ''}${S.locked ? ' · Final results' : ''}`,
      page: p + 1, pages, sponsor: lsp ? sponsorOf(lsp) : null, points: false,
      rows: list.slice(p * per, p * per + per).map((r, i) => {
        const w = r.winner || r.leader, a = tname(r.a), b = tname(r.b);
        return { pos: String(p * per + i + 1), name: `${a} v ${b}`, sub: w ? `${w === 'A' ? a : b} ${r.done ? 'won' : 'leads'}` : r.done ? 'Halved' : '',
          score: r.done ? (r.halved ? '½' : r.text) : r.started ? r.text : '—', under: false, thru: r.done ? 'F' : r.started ? String(r.thru) : String(r.thru).replace('Starts ', '#') };
      }),
    }));
  };
  const indivPages = (fl, secs) => {
    if (!S.format?.indiv || !hasIndividuals(S)) return [];
    const lb = individuals(S, S.scores || {}, { flight: fl || null }); if (!lb.length) return [];
    const pages = Math.min(4, Math.max(1, Math.ceil(lb.length / rows)));
    return Array.from({ length: pages }, (_, p) => ({
      k: 'lb', secs: secs || secsDefault, title: 'Individuals', sub: `${fl ? `Flight ${fl}` : 'Every player'} · ${mode}${S.locked ? ' · Final results' : ''}`,
      page: p + 1, pages, sponsor: null, points: stab,
      rows: lb.slice(p * rows, p * rows + rows).map((l) => ({ pos: String(l.pos), name: l.name, sub: l.sub && l.sub !== l.name ? l.sub : '',
        score: l.played ? fmtPar(l.score, stab).replace(' pts', '') : '—', under: !stab && !!l.played && l.score < 0, thru: String(l.thru || '').replace('Starts ', '#') })),
    }));
  };
  const camPage = (n, secs) => {
    const h = (S.course?.holes || []).find((x) => x.n === n); if (!h) return [];
    const u = cams[n]; const cs = spot('cam', n)[0];
    return isHLS(u) ? [{ k: 'cam', secs: secs || Math.round(secsDefault * 1.5), hole: n, par: h.par, yards: h.yards || 0, url: u, sponsor: cs ? sponsorOf(cs) : null }] : [];
  };
  const page = (it) => {
    const secs = it.secs;
    if (it.k === 'matches' || (it.k === 'lb' && S.format?.type === 'match')) return matchPages(secs);
    if (it.k === 'indiv') return indivPages(it.fl, secs);
    if (it.k === 'lb') return lbPages(it.fl, secs);
    if (it.k === 'cam' || it.k === 'p3') return camPage(it.hole || (S.course?.holes || []).find((h) => h.par === 3 && isHLS(cams[h.n]))?.n, secs);
    if (it.k === 'sponsor') { const x = (S.sponsors || []).find((y) => y.id === it.sponsor); return x ? [{ k: 'sponsor', secs: secs || secsDefault, ...sponsorOf(x) }] : []; }
    if (it.k === 'sponsors') return (S.sponsors || []).length ? [{ k: 'sponsors', secs: secs || secsDefault, list: S.sponsors.slice(0, 12).map(sponsorOf) }] : [];
    return [];
  };
  const phone = { k: 'phone', secs: 12, url: `${origin.startsWith('https:') ? origin : 'https://flagcast.app'}/g/${S.id}`, text: 'Live scores on your phone' };

  let pages = [];
  const f = S.live?.force?.[screenId];
  if (f && !(f.until && now >= f.until)) pages = page({ ...f, secs: 3600 });
  if (!pages.length) {
    const d = (S.displays || []).find((x) => x.id === screenId);
    if (d?.playlist?.length) pages = d.playlist.flatMap(page);
    if (!pages.length) { // the board's usual pages
      if (S.format?.type === 'match') pages.push(...matchPages());
      else for (const fl of (S.flights || []).length > 1 ? S.flights : [null]) pages.push(...lbPages(fl));
      for (const fl of (S.flights || []).length > 1 ? S.flights : [null]) pages.push(...indivPages(fl));
      for (const h of (S.course?.holes || []).filter((x) => x.par === 3)) pages.push(...camPage(h.n));
      if ((S.sponsors || []).length) pages.push(page({ k: 'sponsors' })[0]);
      for (const x of spot('slide')) pages.push({ k: 'sponsor', secs: secsDefault, ...sponsorOf(x) });
    }
    const at = pages.map((x) => x.k).lastIndexOf('lb') + 1;
    if (at) pages.splice(at, 0, phone);
  }
  if (!pages.length) pages = [{ k: 'empty', secs: 30, text: 'Scores will show here once the first group is out.' }];

  const take = S.live?.take && now < (S.live.take.at || 0) + (S.live.take.secs || 25) * 1000 && S.live.take.kind !== 'replay'
    ? { kind: S.live.take.kind, text: S.live.take.text || '', until: S.live.take.at + S.live.take.secs * 1000 } : null;
  const brand = S.brand || {};
  return {
    v: S.v || 0, title: S.screens?.title || S.name || 'Leaderboard', ticker: S.screens?.ticker || '', flash: S.flash?.text || '',
    logo: abs(origin, brand.logo), accent: brand.accent || '', flagcast: !!brand.demo, title_sponsor: spot('title')[0] ? sponsorOf(spot('title')[0]) : null,
    locked: !!S.locked, take, pages,
  };
}
