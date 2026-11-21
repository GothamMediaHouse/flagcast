# Flagcast Manager for iPhone and iPad

Flagcast Manager (`app.flagcast.manager`, iPhone and iPad, iOS 17+, team C8KXPB4QNA) is a native SwiftUI app: a club
runs its tournament day from it (Today, Teams, Scores, Screens, More). Signing in with a Flagcast admin email, or the
admin passcode (Settings), adds the Admin tab: clubs, every tournament, any club's TVs and players' phones, activity.

- `python3 tools/make-project.py` writes `FlagcastStaff.xcodeproj`. `Manager/` and `Admin/` are synchronized folders.
- Shared by reference: the tournament model, scoring math and live feed from the iPhone player app
  (`../flagcast-ios`), and the desk model, server calls, Admin model, course pictures and TV logic from the Mac app
  (`../flagcast-mac`). Change them there; all three apps pick them up.
- `Admin` (`app.flagcast.admin`) is retired: its last build only says Admin is now in Manager.
- Debug builds can point at a local copy of the site with the launch argument `-FlagcastServer http://localhost:8787`.
