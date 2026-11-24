# Flagcast TV for Apple TV

Native SwiftUI (tvOS 17+), because tvOS has no web views. It shows a 6-letter code; someone at the club types it in
Manager → Screens & sponsors → Club TVs → Add a TV. Then it asks flagcast.app every 10 seconds what to show (`tv.js`,
`tvfeed.js`): on a tournament day it draws the board's pages (leaderboard, par 3 cameras over HLS, sponsors, the phone
QR code, the ticker, announcements and takeovers); in between, the club's idle screen with the next tournament.

    python3 tools/make-project.py   # writes FlagcastTV.xcodeproj
    xcodebuild -project FlagcastTV.xcodeproj -scheme FlagcastTV -destination 'generic/platform=tvOS Simulator' build

Bundle id `app.flagcast.tv`, team C8KXPB4QNA. Point it at `npx wrangler dev` with the scheme argument
`-FlagcastServer http://localhost:8787`. Nothing is uploaded without Matt's own words ("upload to TestFlight").
