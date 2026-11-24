# Flagcast TV for Roku

BrightScript / SceneGraph, 1920×1080. Roku has no web views, so it draws the board's pages from the feed flagcast.app
builds for TVs (`tv.js`, `tvfeed.js`): leaderboard pages, par 3 cameras (HLS), sponsors, the phone link, the ticker,
announcements and takeovers. Not connected, it shows a 6-letter code for Manager → Screens & sponsors → Club TVs →
Add a TV. The token is kept in the Roku registry.

Try it on a Roku in developer mode (Home ×3, Up ×2, Right, Left, Right, Left, Right), then:

    cd apps/flagcast-tv-roku && zip -r ../flagcast-tv-roku.zip manifest source components images
    # upload the zip at http://<roku-ip> (Development Application Installer)

Publishing on the Roku Channel Store needs a Roku developer account and Matt's own words.
