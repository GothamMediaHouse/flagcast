// Flagcast: live scoring, leaderboard screens and par 3 cameras for golf tournaments.
// The website and pages are static files in public/; each tournament is one Durable Object (GolfEvent in golf.js).
import { golf } from './golf.js';
import { downloads } from './downloads.js';
import { courses } from './courses.js';
import { contact } from './contact.js';
export { GolfEvent } from './golf.js';
export { FlagcastClubs } from './clubs.js';

const HOME = 'flagcast.app';
const FORWARD = ['www.flagcast.app', 'sundaypin.live', 'www.sundaypin.live'];

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    // the old name's domain and www forward to flagcast.app
    if (FORWARD.includes(url.hostname)) return Response.redirect(`https://${HOME}${url.pathname}${url.search}`, 301);
    if (url.pathname === '/api/contact') return contact(request, env);
    // a short address to type on a TV's browser: the Flagcast TV page
    if (url.pathname === '/tv' || url.pathname === '/tv/') return Response.redirect(`${url.origin}/golf/tv/`, 302);
    if (url.pathname === '/golf/api/courses' || url.pathname.startsWith('/golf/api/courses/')) return courses(request, env, ctx);
    if (url.pathname.startsWith('/golf/api/') || url.pathname.startsWith('/g/')) { const r = await golf(request, env); if (r) return r; }
    if (/^\/(download\/[a-z]|api\/[a-z]+\/latest|updates\/)/.test(url.pathname)) { const r = await downloads(request, env, ctx); if (r) return r; }
    return env.ASSETS.fetch(request);
  },
};
