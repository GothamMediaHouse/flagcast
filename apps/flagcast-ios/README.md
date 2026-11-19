# Flagcast for iPhone (SwiftUI)

The native iPhone app: cart scorecard, live leaderboard, par 3 cameras and replays, side games, and the golf pro / marshal tools. iOS 17+, iPhone only, no third-party packages. Bundle id `app.flagcast.golf`, team C8KXPB4QNA.

It talks to the same API as the web pages (`golf.js`): `GET /golf/api/<id>/state`, the WebSocket at `/golf/api/<id>/ws`, and `POST …/cart`, `…/score`, `…/pro`, `…/hit`.

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
