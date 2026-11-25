# Flagcast for iPhone (SwiftUI)

The native iPhone app: cart scorecard, live leaderboard, par 3 cameras and replays, side games, and the golf pro / marshal tools. iOS 17+, iPhone only, no third-party packages. Bundle id `app.flagcast.golf`, team C8KXPB4QNA.

It talks to the same API as the web pages (`golf.js`): `GET /golf/api/<id>/state`, the WebSocket at `/golf/api/<id>/ws`, and `POST …/cart`, `…/score`, `…/pro`, `…/hit`, `…/where` (the group's spot, and the other groups for the Course tab's Everyone map).

## Layout

- `Flagcast/Model/Core.swift` is a line-for-line port of `public/golf/core.js` (leaderboard, Stableford, skins, side games…). **Change both together.**
- `Flagcast/Model/Models.swift`: the public state, decoded leniently.
- `Flagcast/Net/`: the API client and `EventFeed` (live link: ping every 25 s, reconnect with backoff, reconnect on foreground, last state cached on disk).
- `Flagcast/Model/ScorecardModel.swift`: the offline-first score queue (kept on disk, sent when online).
- `Flagcast/Views/`: home + QR scanner, scorecard, side games, leaderboard (par 3s, contests, skins), cameras and replays, pro tabs.
- `FlagcastTests/CoreTests.swift` checks the Swift math against `core.js` on the same input.

## Build and test

Open `Flagcast.xcodeproj` in Xcode (scheme **Flagcast**). The project uses folder-synced groups, so new Swift files are picked up without editing the project.

    xcodebuild test -project Flagcast.xcodeproj -scheme Flagcast -destination 'platform=iOS Simulator,name=iPhone 18 Pro'

After changing `public/golf/core.js`, regenerate the test fixture and rerun the tests:

    node apps/flagcast-ios/tools/make-core-fixture.mjs

## Run against a local server

Run the site with `npx wrangler dev` (no passcode needed on localhost), then launch a debug build with the argument `-FlagcastServer http://localhost:8787` (it's in the scheme, switched off), or long-press **flagcast.app** at the bottom of the home screen to set a server. Release builds always use https://flagcast.app.

## Links

Cart cards open the app with `flagcast://g/<id>/s/<CODE>`, and `https://flagcast.app/g/…` links handed to the app work too. True universal links still need the Associated Domains capability and an `apple-app-site-association` file on flagcast.app.

## Live score on the lock screen (Live Activity)

On the tournament day the scorecard starts a Live Activity: the team's score, place and hole on the lock screen and
in the Dynamic Island (widget extension `FlagcastLive`, shared model in `LiveShared/`, app side in
`Flagcast/Model/LiveView.swift`). The app sends its push token to `POST /golf/api/<id>/live`, and the server
(`liveact.js`) pushes a new card through Apple whenever the team's card changes, so it stays live with the app closed.
Settings → Live score on the lock screen turns it off.

One-time setup for the server pushes (done by Matt, never pasted in chat):
1. developer.apple.com → Certificates, IDs & Profiles → Keys → + → tick Apple Push Notifications service (APNs),
   Sandbox & Production → download the .p8 file (it can only be downloaded once) and note its Key ID.
2. Cloudflare → Workers → flagcast → Settings → Variables and Secrets: add secret `APNS_KEY` (paste the whole .p8 text)
   and text variable `APNS_KEY_ID` (the 10-character Key ID). `APNS_TEAM_ID` defaults to C8KXPB4QNA.
Without them the card still shows, but only updates while the app is open.

Xcode signing (automatic) adds the Push Notifications and App Groups (`group.app.flagcast.golf`) capabilities and
registers `app.flagcast.golf.live` the first time it builds.
