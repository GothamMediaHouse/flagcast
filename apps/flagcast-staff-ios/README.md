# Flagcast Manager and Flagcast Admin for iPhone and iPad

Two small native apps so a club (Manager) and Flagcast (Admin) can adjust things on the course from a phone or
tablet. They load the same pages as the Mac apps — https://flagcast.app/golf/ (club sign-in, tournaments, desk)
and https://flagcast.app/golf/admin/ — so they update whenever the site does. The shell adds: sign-ins kept on
the device, a native Back / Home bar away from the start page, pull to refresh, other sites in Safari view,
downloaded files (reports) to the share sheet, and a "Can't reach Flagcast" screen with Try again.

- Open `FlagcastStaff.xcodeproj`; schemes **Manager** (`app.flagcast.manager`) and **Admin** (`app.flagcast.admin`),
  iPhone and iPad, iOS 17+, team C8KXPB4QNA. `Shared/WebShell.swift` is the code both use.
- Debug builds can point at a local copy of the site with the launch argument `-FlagcastServer http://localhost:8787`.
