// The golfer's live view on the iPhone lock screen and Dynamic Island (an iOS Live Activity), kept up to date by
// Apple push while the Flagcast app is closed.
//
// The player app starts the Live Activity when a scorecard opens and sends its push token here
// (POST /golf/api/<id>/live { code, team, token, env, player? }, or { code, team, token, end: true } to stop).
// After every change to the tournament, GolfEvent works out each registered team's card (liveCard) and, when it
// changed, sends it to Apple. A new pro shop message goes out loud (it buzzes); everything else is quiet.
//
// Apple push needs, in Cloudflare: APNS_KEY (secret: the .p8 key's text), APNS_KEY_ID (the key's 10-letter id)
// and optionally APNS_TEAM_ID (default C8KXPB4QNA). Without APNS_KEY nothing is sent and the app still shows the
// card, updated whenever the app is open.
import { leaderboard, fmtPar, playHoles, groupInfo, teamBall, matches, matchFor } from './public/golf/core.js';

export const LIVE_TOPIC = 'app.flagcast.golf.push-type.liveactivity';
export const LIVE_MAX = 400; // tokens kept per tournament
export const MSG_MINS = 30; // a pro shop message stays on the card this long
export const LIVE_HOURS = 12; // a token nobody refreshed in this long is dropped

const lastName = (n) => String(n || '').trim().split(/\s+/).slice(-1)[0] || '';
const teamName = (t) => t.name || t.players.map((p) => lastName(p.name)).join(' / ');

// the message on a team's card: the newest one to everyone, to this team, or to this golfer, in the last 30 minutes
export function cardMessage(ev, teamId, player, now = Date.now()) {
  const n = (ev.nudges || []).filter((x) => (x.team === '*' || x.team === teamId) && (!x.player || !player || x.player === player) && now - x.at <= MSG_MINS * 60000).pop();
  return n ? { text: n.text, from: n.from || 'Pro shop', at: n.at } : null;
}

// What one team's card shows. `scores` is the public state's scores (values only). Keys match the app's
// LiveCard (apps/flagcast-ios/LiveShared/LiveCard.swift); change both together.
export function liveCard(ev, scores, teamId, player = '', now = Date.now(), board = null) {
  const team = (ev.teams || []).find((t) => t.id === teamId); if (!team) return null;
  const stab = ev.format?.type === 'stableford';
  const lb = board || leaderboard(ev, scores);
  const gi = groupInfo(ev, scores, teamId) || {};
  const mine = lb.filter((l) => l.teamId === teamId);
  const best = mine.find((l) => l.played) || mine[0];
  const ph = playHoles(ev), start = ph.includes(team.start) ? team.start : ph[0], k = ph.indexOf(start);
  const order = [...ph.slice(k), ...ph.slice(0, k)];
  const sc = scores?.[teamId] || {};
  const ids = teamBall(ev) ? ['T'] : team.players.map((p) => p.id);
  const done = (h) => ids.length > 0 && ids.every((p) => { const v = sc[p]?.[h - 1]; return v !== null && v !== undefined; });
  const played = order.filter(done).length;
  const hole = order.find((h) => !done(h)) || order[order.length - 1];
  const hh = ev.course?.holes?.[hole - 1] || {};
  const lead = lb.find((l) => l.played);
  const msg = cardMessage(ev, teamId, player, now);
  const raw = best && best.played ? best.score : null;
  // match play: the card shows the team's match ("2 UP", "WON 3&2") and who they're playing, not a to-par score
  const m = ev.format?.type === 'match' ? matches(ev, scores).find((r) => r.a === teamId || r.b === teamId) : null;
  if (m) {
    const f = matchFor(m, teamId), opp = (ev.teams || []).find((t) => t.id === (m.a === teamId ? m.b : m.a));
    const c = { team: gi.name || teamName(team), score: m.started ? f.text : '—', tone: ['up', 'won'].includes(f.state) ? -1 : ['down', 'lost'].includes(f.state) ? 1 : 0,
      thru: m.thru || '—', pos: '—', of: 0, hole, par: hh.par || 4, yds: hh.yds || 0, played, holes: order.length,
      leader: opp ? `v ${opp.name || teamName(opp)}` : '',
      msg: msg ? msg.text : '', from: msg ? msg.from : '', msgAt: msg ? msg.at : 0, final: !!ev.locked, at: now };
    return c;
  }
  return {
    team: gi.name || teamName(team),
    score: raw === null ? '—' : fmtPar(raw, stab),
    // −1 under par (red, as on the boards), 0 level, 1 over; Stableford is always 0
    tone: raw === null || stab ? 0 : Math.sign(raw),
    thru: best ? best.thru : '—',
    pos: best && best.pos ? best.pos : '—',
    of: lb.length,
    hole, par: hh.par || 4, yds: hh.yds || 0,
    played, holes: order.length,
    leader: lead && lead.teamId !== teamId ? `${lead.name} ${fmtPar(lead.score, stab)}` : lead ? 'You lead' : '',
    msg: msg ? msg.text : '', from: msg ? msg.from : '', msgAt: msg ? msg.at : 0,
    final: !!ev.locked, // the results are final: the card ends (it stays on the lock screen a few hours)
    at: now,
  };
}

// the parts that matter for deciding whether to send again (not the time)
export const cardKey = (c) => JSON.stringify({ ...c, at: 0 });

// ---- Apple push (token-based: an ES256 JWT, good for up to an hour; Apple asks to reuse it for at least 20 minutes) ----
const b64u = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const b64uText = (s) => b64u(new TextEncoder().encode(s));
let jwtCache = null;
export async function apnsJWT(env, now = Date.now()) {
  const kid = String(env.APNS_KEY_ID || '').trim(), iss = String(env.APNS_TEAM_ID || 'C8KXPB4QNA').trim();
  if (jwtCache && jwtCache.kid === kid && now - jwtCache.at < 40 * 60000) return jwtCache.jwt;
  const pem = String(env.APNS_KEY || '').replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const head = b64uText(JSON.stringify({ alg: 'ES256', kid })), body = b64uText(JSON.stringify({ iss, iat: Math.floor(now / 1000) }));
  const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(`${head}.${body}`));
  const jwt = `${head}.${body}.${b64u(sig)}`;
  jwtCache = { jwt, kid, at: now };
  return jwt;
}

// the push for one card: event 'update', or 'end' once the results are final (it stays on the lock screen 4 hours)
export function livePayload(card, { alert = false, now = Date.now() } = {}) {
  const secs = Math.floor(now / 1000);
  const aps = { timestamp: secs, event: card.final ? 'end' : 'update', 'content-state': card, 'stale-date': secs + 3 * 3600 };
  if (card.final) aps['dismissal-date'] = secs + 4 * 3600;
  if (alert && card.msg) aps.alert = { title: `From ${card.from || 'the pro shop'}`, body: card.msg, sound: 'default' };
  return { aps };
}

// send one push. → 'ok' | 'gone' (drop the token) | 'error'
export async function sendLive(env, token, env2, payload, priority, fetcher = fetch) {
  const host = env2 === 'dev' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com';
  try {
    const r = await fetcher(`https://${host}/3/device/${token}`, { method: 'POST', body: JSON.stringify(payload), headers: {
      authorization: `bearer ${await apnsJWT(env)}`, 'apns-push-type': 'liveactivity', 'apns-topic': LIVE_TOPIC,
      'apns-priority': String(priority), 'apns-expiration': String(Math.floor(Date.now() / 1000) + 3600), 'content-type': 'application/json' } });
    if (r.ok) return 'ok';
    const why = (await r.json().catch(() => ({}))).reason || '';
    return r.status === 410 || why === 'BadDeviceToken' || why === 'Unregistered' || why === 'ExpiredToken' ? 'gone' : 'error';
  } catch { return 'error'; }
}

export const TOKEN = /^[0-9a-f]{32,200}$/;
