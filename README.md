# Flagcast

Live scoring, leaderboard screens and par 3 cameras for golf tournaments. Live at https://flagcast.app.

- `public/` is the website (`/`, `/brochure/`) and the tournament pages under `/golf/` (desk, scorecard, live leaderboard, screens, cart cards, phone app pages).
- `worker.js` serves it and forwards www.flagcast.app and sundaypin.live to flagcast.app.
- `golf.js` holds each tournament in its own Durable Object (`GolfEvent`): setup, scores, contests, screens, and pushes every change to open pages over a WebSocket. The scoring math is in `public/golf/core.js` and runs in the pages.
- `apps/flagcast-manager/` is the Mac and Windows Manager app (Electron).

## Run it locally

    npx wrangler dev

New tournaments need the `GOLF_CREATE_PASS` secret on the live site (Cloudflare → Workers → flagcast → Settings → Variables and Secrets). On localhost no passcode is needed.

## Deploy

Pushing to `main` deploys through Cloudflare Workers Builds.
