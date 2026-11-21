import SwiftUI

/// Today: the course photo with LIVE · date and the tournament's name, four numbers, the top of the leaderboard, the
/// closest-to-the-pin, lock the results and an announcement on every TV.
struct TodayView: View {
    var body: some View {
        WithTournament { doc in TodayPage(doc: doc) }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { TournamentMenu() } }
    }
}

private struct TodayPage: View {
    @Bindable var doc: DeskDoc
    @State private var flash = ""
    @State private var confirmLock = false

    private var ev: DeskEvent { doc.ev }
    private var live: EventState? { doc.live }
    private var holes: [Hole] { ev.course.holes.filter { ev.playHoles.contains($0.n) } }
    private var isToday: Bool { ev.date == ISO8601DateFormatter.day.string(from: Date()) }
    private var board: [Line] { live.map { Core.leaderboard($0, $0.scores) } ?? [] }

    var body: some View {
        PhotoPage(image: doc.picture.image, kicker: dayLine(ev.date) ?? "No date set", live: isToday && !ev.locked,
                  title: ev.name.isEmpty ? "Tournament" : ev.name, sub: subtitle, height: 300) {
            HStack(spacing: 8) {
                Button("Open the board") { UIApplication.shared.open(doc.boardURL) }.buttonStyle(WhiteButton())
                ShareLink(item: doc.liveURL) { Label("Live link", systemImage: "square.and.arrow.up") }.buttonStyle(WhiteButton())
            }
        } content: {
            stats
            leaderboard
            contestTile
            announce
            lock
        }
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .refreshable { await doc.feed.refresh(); await doc.refreshDay() }
        .confirmationDialog("Lock the results?", isPresented: $confirmLock, titleVisibility: .visible) {
            Button("Lock Results") { Task { await doc.setLocked(true) } }
        } message: { Text("Scoring closes on every scorecard and the leaderboard becomes final. You can unlock again.") }
    }

    private var subtitle: String {
        let nine = ev.format.nine == "front" ? "Front 9" : ev.format.nine == "back" ? "Back 9" : "18 holes"
        let par = holes.reduce(0) { $0 + $1.par }
        return [ev.course.name.isEmpty ? (ev.club.isEmpty ? nil : ev.club) : ev.course.name, nine, "Par \(par)"].compactMap { $0 }.joined(separator: " · ")
    }

    private var stats: some View {
        let scoring = board.filter { $0.played > 0 && $0.thru != "F" }.count, finished = board.filter { $0.thru == "F" }.count
        let leader = board.first { $0.played > 0 }
        let tvs = ev.displays.count, on = ev.displays.filter { (live?.online[$0.id] ?? 0) > 0 }.count
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            stat("Teams", "\(ev.teams.count)", "\(ev.teams.reduce(0) { $0 + $1.players.count }) players", FC.ink)
            stat("On the course", "\(scoring)", finished > 0 ? "\(finished) finished" : (ev.locked ? "results final" : "scoring now"), FC.ink)
            stat("Leader", leader.map(scoreText) ?? "–", leader?.name ?? "No scores yet", leader.map(scoreColor) ?? FC.ink)
            stat("TVs", tvs == 0 ? "–" : "\(on)/\(tvs)", tvs == 0 ? "None set up" : "showing now", on > 0 ? FC.ok : FC.ink)
        }
    }
    private func stat(_ label: String, _ value: String, _ sub: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(FC.muted)
            Text(value).font(FC.display(34)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).font(.system(size: 12)).foregroundStyle(FC.muted).lineLimit(1)
        }
        .card(padding: 14)
    }

    private var leaderboard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("Leaderboard").font(.headline); Spacer(); NavigationLink("All scores") { ScoresView() }.font(.subheadline.weight(.semibold)).foregroundStyle(FC.link) }
                .padding(.bottom, 8)
            let top = Array(board.filter { $0.played > 0 }.prefix(5))
            if top.isEmpty {
                Text(ev.teams.isEmpty ? "Add teams on the Teams tab, then Save." : "Scores show here as the carts send them.").font(.subheadline).foregroundStyle(FC.muted).padding(.vertical, 18)
            }
            ForEach(top) { l in
                HStack(spacing: 12) {
                    Text(l.pos).font(.system(size: 14, weight: .bold)).foregroundStyle(FC.muted).frame(width: 30, alignment: .leading)
                    Text(l.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Text(l.thru == "F" ? "F" : "Thru \(l.thru)").font(.system(size: 12)).foregroundStyle(FC.muted)
                    Text(scoreText(l)).font(FC.display(24)).foregroundStyle(scoreColor(l)).frame(width: 48, alignment: .trailing)
                }
                .padding(.vertical, 7)
                Divider().overlay(FC.hairline)
            }
        }
        .card()
    }
    private func scoreText(_ l: Line) -> String { ev.format.isStableford ? "\(l.score)" : Core.fmtPar(l.score) }
    private func scoreColor(_ l: Line) -> Color { ev.format.isStableford ? FC.ink : l.score < 0 ? FC.red : l.score > 0 ? FC.blue : FC.ink }

    @ViewBuilder private var contestTile: some View {
        let list = live?.contests ?? ev.contests
        if let c = list.first(where: { !$0.isLongDrive }) ?? list.first {
            let lead = Core.contestLeader(c).first
            NavigationLink { ContestsView() } label: {
                ZStack(alignment: .bottomLeading) {
                    HolePicture(id: doc.id, n: c.hole, h: ev.map.holes[c.hole], fallback: doc.picture.image)
                    LinearGradient(colors: [FC.scrim.opacity(0.88), FC.scrim.opacity(0)], startPoint: .bottom, endPoint: .center)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(c.isLongDrive ? "LONG DRIVE" : "CLOSEST TO THE PIN") · HOLE \(c.hole)").font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(FC.flag)
                        Text(lead?.name ?? "No results yet").font(FC.display(30)).lineLimit(1).minimumScaleFactor(0.6)
                        Text(lead.map { Core.fmtDist(c, $0.dist) } ?? "Post results on the Contests page.").font(.system(size: 13)).opacity(0.85)
                    }
                    .foregroundStyle(.white).padding(16)
                }
                .frame(height: 190).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }

    private var announce: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle("Announcement on every TV")
            if let f = live?.flash, !f.text.isEmpty {
                HStack { Text("“\(f.text)”").foregroundStyle(FC.muted); Spacer(); Button("Clear") { Task { await doc.day("flash", ["text": ""], done: "Cleared.") } } }
            }
            HStack {
                TextField("Shotgun start in 10 minutes", text: $flash).padding(10).background(FC.paper2, in: RoundedRectangle(cornerRadius: 9))
                Button("Show") { let t = flash; Task { if await doc.day("flash", ["text": t], done: "On every TV now.") != nil { flash = "" } } }
                    .buttonStyle(GreenButton()).disabled(flash.isEmpty)
            }
        }
        .card()
    }

    private var lock: some View {
        Button { if ev.locked { Task { await doc.setLocked(false) } } else { confirmLock = true } } label: {
            Label(ev.locked ? "Unlock the results" : "Lock the results", systemImage: ev.locked ? "lock.open" : "lock.fill")
        }
        .buttonStyle(PlainCardButton(full: true))
    }
}
