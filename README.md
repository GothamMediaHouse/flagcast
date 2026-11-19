# Flagcast

Live scoring, leaderboard screens and par 3 cameras for golf tournaments. Live at https://flagcast.app.

- `public/` is the website (`/`, `/brochure/`) and the tournament pages under `/golf/` (desk, scorecard, live leaderboard, screens, cart cards, phone app pages).
- `worker.js` serves it and forwards www.flagcast.app and sundaypin.live to flagcast.app.
- `golf.js` holds each tournament in its own Durable Object (`GolfEvent`): setup, scores, contests, screens, and pushes every change to open pages over a WebSocket. The scoring math is in `public/golf/core.js` and runs in the pages.
- `clubs.js` holds club accounts in one Durable Object (`FlagcastClubs`): clubs sign in with an emailed 6-digit code, see only their own tournaments, and make new ones while they have tournament credits. Flagcast runs it from `/golf/admin/` (or the Flagcast Admin app).
- `apps/flagcast-manager/` is the Mac and Windows Manager app clubs use (Electron). `apps/flagcast-admin/` is Flagcast's own Admin app (Mac).

## Run it locally

    npx wrangler dev

Settings on the live worker (Cloudflare → Workers → flagcast → Settings → Variables and Secrets):

- `GOLF_CREATE_PASS` (secret): the Flagcast admin passcode. It opens `/golf/admin/` and the Admin app.
- `RESEND_API_KEY` (secret) and `MAIL_FROM` (e.g. `Flagcast <signin@flagcast.app>`, a domain verified in Resend): sign-in codes and club emails.
- `ADMIN_EMAIL` (optional): gets a note when a club asks to join.

On localhost with none of these, sign-in codes come back on screen and the admin page opens without a passcode.

Clubs: set one up in Admin (name, owner's email, how many tournaments), or a club signs in at `/golf/` or in the Manager and asks; you approve it. Each tournament a club makes uses one credit (`-1` = unlimited). Tournaments you make for a club in Admin don't use credits.

## Deploy

Pushing to `main` deploys through Cloudflare Workers Builds.

## The apps

- **Flagcast Manager** (`apps/flagcast-manager/`, Electron, Mac + Windows): run `Build Flagcast Manager (Mac and PC).command` on the Mac. It signs and notarizes the Mac app with the Developer ID in the keychain and builds the Windows installer; both land in `dist/`.
- **Flagcast Admin** (`apps/flagcast-admin/`, Electron, Mac): Flagcast's own app; it opens `flagcast.app/golf/admin/`. Run `Build Flagcast Admin (Mac).command`.
- **Flagcast phone app** (`apps/flagcast-phone/`, Capacitor 8, iPhone + Android, bundle `app.flagcast.golf`): the app opens `https://flagcast.app/golf/app/` with `FlagcastApp` in its user agent, so the pages show the app bar. `npm install && npx cap sync`, then `npx cap open ios` (Xcode, team C8KXPB4QNA) or `npx cap open android` (Android Studio). Icons and splash come from `assets/` (`npm run icons`); `fix-native.cjs` adds the camera permission for scanning cart cards.
