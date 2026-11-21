# Flagcast Mac apps: approved design (Matt, 2026-11-20)

These are mockups to build natively in SwiftUI (Manager + Admin 2.0.1), not files the apps load. Open any `.dc.html` for the
layout, then match it. The live canvas is https://claude.ai/artifact/V3NqF5ChDMsT4a4PRaL1w1. Team names and numbers are sample data.

## Look
- Colours: green #123628 (sidebar, primary), green-2 #1c4a37, paper #f2f4ef (content background), card #ffffff, ink #14201a,
  muted #56625a, line #d3dacf, flag yellow #e8c547 (LIVE chip, highlights only), red #c8312b (under par), blue #1f5aa6 (over par), ok #2f8a57.
- Type: Barlow Condensed Bold for big titles and numbers (tournament name 76 pt, screen titles 52–56 pt, stats 34 pt, scores 22–24 pt).
  The body uses the system font (the mockups use Inter as a stand-in) at 13–14 pt.
- **Full-bleed photos** (what Matt loved): every screen opens on an edge-to-edge course image that runs under a transparent toolbar
  (fullSizeContentView, toolbar with no background). Image heights are about 430 (Overview), 300 (Setup), 250 (Scores) and 200 (Teams).
  A dark scrim (top 55% black-green for the toolbar, clear in the middle, about 80% at the bottom) sits over it, with the big title in white at the bottom of the photo.
  Toolbar buttons over the photo: white glass (white at 16% with a blur and a 35% white border); the primary button is solid white with green text.
- Content cards sit raised over the photo's bottom edge: white, radius 12, shadow 0 8 30 rgba(8,24,17,0.18).
- Images in the app: the tournament's own course as an Apple Maps satellite snapshot (MKMapSnapshotter from course.at or the map),
  per-hole tee-to-green snapshots for hole tiles, or club photos when set. img/ holds stand-in stock photos used in the mockup only.

## Screens
- **Sidebar** (Sidebar.dc.html, 248 wide, green): logo mark + FLAGCAST / MANAGER, a search field, then TOURNAMENTS. The open tournament
  shows a LIVE chip and its sections with ⌘1–⌘0. The selected row is a cream pill with green text. At the bottom are New tournament ⌘N and the club with tournaments left.
- **Overview** (Main): hero photo with LIVE · date · shotgun, the name, and "course · nine · par · tees yards". A frosted 4-up stats strip
  (Teams, On the course, Leader, Screens) sits on the photo's bottom edge. Below, the Leaderboard card (top 5, red/blue scores) and a closest-to-the-pin photo tile.
- **Teams**: photo header with the title and counts. A flight segmented control and Import / Add team sit in the toolbar. On the left is a table card (selected row green);
  on the right is a raised inspector card with a hole photo header, then players (GHIN, Index, Tees, Course hcp), starting hole, scorer, PIN, Print / Open scorecard.
- **Scores**: photo header "Live scores · FROM THE CARTS". The table card has a green hole header, a par row, team rows with score marks
  (eagle: filled red circle, birdie: red ring, bogey: blue square outline, double: filled blue square), Thru and Total. A legend sits below.
- **Setup**: aerial photo header with "COURSE · town" and the course name. Find the course… / Map the holes / Save are in the toolbar.
  On the left: Tournament form (name, date, shotgun, format, Holes All 18 / Front 9 / Back 9) and Tees list (swatch, rating, slope).
  On the right: Scorecard card with Front 9 and Back 9 grids (Hole / Par / Yards / SI). The nine not in play is dimmed.
- **Admin · Clubs** (Admin.dc.html): same green sidebar with a red ADMIN tag (Clubs, Tournaments, Screens & phones, Activity).
  A yellow approval banner sits at the top. Clubs are a 3-column grid of full-photo cards (status chip, name, town, left / tournaments / staff,
  +1, +5, Open club).
