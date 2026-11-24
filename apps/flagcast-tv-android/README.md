# Flagcast TV for Google TV, Android TV and Fire TV

A full-screen WebView of https://flagcast.app/golf/tv/ (the page in `public/golf/tv/`), kept awake. The page shows a
6-letter code; someone at the club types it in Manager → Screens & sponsors → Club TVs → Add a TV. From then on the TV
plays the club's tournament of the day by itself (and the club's idle screen in between). See `tv.js` on the server.

Package: `app.flagcast.tv`. No libraries. Build on the Mac with Android Studio (or the Android SDK and `./gradlew`):

    ./gradlew assembleRelease     # app/build/outputs/apk/release/ (sign it for Google Play / the Amazon Appstore)
    ./gradlew bundleRelease       # the .aab for Google Play

Google Play needs the TV banner (`res/drawable-xhdpi/banner.png`, 320×180 dp) and the Leanback launcher entry (in the
manifest). Fire TV takes the same APK in the Amazon Appstore. Nothing is uploaded or published without Matt's own words.
