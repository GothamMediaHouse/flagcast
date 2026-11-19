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

## The apps

- **Flagcast Manager** (`apps/flagcast-manager/`, Electron, Mac + Windows): run `Build Flagcast Manager (Mac and PC).command` on the Mac. It signs and notarizes the Mac app with the Developer ID in the keychain and builds the Windows installer; both land in `dist/`.
- **Flagcast phone app** (`apps/flagcast-phone/`, Capacitor 8, iPhone + Android, bundle `app.flagcast.golf`): the app opens `https://flagcast.app/golf/app/` with `FlagcastApp` in its user agent, so the pages show the app bar. `npm install && npx cap sync`, then `npx cap open ios` (Xcode, team C8KXPB4QNA) or `npx cap open android` (Android Studio). Icons and splash come from `assets/` (`npm run icons`); `fix-native.cjs` adds the camera permission for scanning cart cards.
