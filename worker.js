// Flagcast: live scoring, leaderboard screens and par 3 cameras for golf tournaments.
// The website and pages are static files in public/; each tournament is one Durable Object (GolfEvent in golf.js).
import { golf } from './golf.js';
export { GolfEvent } from './golf.js';

const HOME = 'flagcast.app';
const FORWARD = ['www.flagcast.app', 'sundaypin.live', 'www.sundaypin.live'];

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    // the old name's domain and www forward to flagcast.app
    if (FORWARD.includes(url.hostname)) return Response.redirect(`https://${HOME}${url.pathname}${url.search}`, 301);
    if (url.pathname.startsWith('/golf/api/') || url.pathname.startsWith('/g/')) { const r = await golf(request, env); if (r) return r; }
    return env.ASSETS.fetch(request);
  },
};
