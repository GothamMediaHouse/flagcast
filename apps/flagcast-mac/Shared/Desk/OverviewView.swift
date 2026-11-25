import SwiftUI

/// Overview (design/Main.dc.html): the course photo with LIVE · date, the name and "course · nine · par · tees yards",
/// a frosted strip of four numbers on the photo's edge, then the leaderboard and the closest-to-the-pin tile.
struct OverviewView: View {
    @Bindable var doc: DeskDoc
    @Environment(DeskNav.self) private var nav

    private var live: EventState? { doc.live }
    private var ev: DeskEvent { doc.ev }
    private var holes: [Hole] { ev.course.holes.filter { ev.playHoles.contains($0.n) } }
    private var isToday: Bool { ev.date == ISO8601DateFormatter.day.string(from: Date()) }
    private var board: [Line] { live.map { Core.leaderboard($0, $0.scores) } ?? [] }

    var body: some View {
        PhotoPage(image: doc.picture.image, height: 420, section: "Overview", titleHeight: 312) {
            SaveState(doc: doc)
            Button("Open the board") { NSWorkspace.shared.open(doc.boardURL) }.buttonStyle(GlassButton())
            LockButton(doc: doc)
            Button("Save") { Task { await doc.save() } }.buttonStyle(WhiteButton()).disabled(!doc.dirty || doc.saving)
        } title: {
            VStack(alignment: .leading, spacing: 14) {
                // the logo golfers and the TVs see: the club's (or this tournament's own); none on a Demo
                if let u = logoURL(live?.brand.logo) { RemoteLogo(url: u).frame(maxWidth: 240, maxHeight: 64, alignment: .leading).shadow(color: .black.opacity(0.3), radius: 6) }
                HeroTitle(kicker: dayLine(ev.date) ?? "NO DATE SET", live: isToday && !ev.locked, title: ev.name.isEmpty ? "Tournament" : ev.name, size: 76, sub: subtitle)
            }
        } content: {
            VStack(spacing: 18) {
                stats.padding(.horizontal, 24)
                // the leaderboard takes the room; the contest card keeps a fixed share (its photo never sets the width)
                // side by side when the leaderboard still gets 420 pt; stacked in a narrow window
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        leaderboard.frame(minWidth: 420, maxWidth: .infinity)
                        contestTile.frame(width: 340)
                    }
                    VStack(spacing: 16) {
                        leaderboard.frame(maxWidth: .infinity)
                        contestTile.frame(maxWidth: .infinity).frame(height: 220)
                    }
                }
                .padding(.horizontal, 24)
                codesTile.padding(.horizontal, 24).padding(.bottom, 22)
            }
        }
    }

    private var subtitle: String {
        let nine = ev.format.nine == "front" ? "Front 9" : ev.format.nine == "back" ? "Back 9" : "18 holes"
        let par = holes.reduce(0) { $0 + $1.par }, yds = holes.reduce(0) { $0 + $1.yds }
        let tee = ev.course.tees.first?.name
        return [ev.course.name.isEmpty ? (ev.club.isEmpty ? nil : ev.club) : ev.course.name, nine, "Par \(par)",
                yds > 0 ? "\(tee.map { "\($0) tees " } ?? "")\(yds.formatted()) yds" : nil].compactMap { $0 }.joined(separator: " · ")
    }

    // ---- the four numbers ----
    private var stats: some View {
        let scoring = board.filter { $0.played > 0 && $0.thru != "F" }.count
        let finished = board.filter { $0.thru == "F" }.count
        let leader = board.first { $0.played > 0 }
        let screens = ev.displays.count, on = ev.displays.filter { (live?.online[$0.id] ?? 0) > 0 }.count
        return HStack(spacing: 1) {
            stat("Teams", "\(ev.teams.count)", "\(ev.teams.reduce(0) { $0 + $1.players.count }) players", FC.ink)
            stat("On the course", "\(scoring)", finished > 0 ? "\(finished) finished" : (ev.locked ? "results final" : "scoring now"), FC.ink)
            if let live, live.format.isMatch {
                let ms = Core.matches(live, live.scores)
                stat("Matches", ms.isEmpty ? "–" : "\(ms.filter(\.done).count)/\(ms.count)", ms.isEmpty ? "None paired yet" : "finished", FC.ink)
            } else {
                stat("Leader", leader.map { scoreText($0) } ?? "–", leader?.name ?? "No scores yet", leader.map { scoreColor($0) } ?? FC.ink)
            }
            stat("Screens", screens == 0 ? "–" : "\(on)/\(screens)", screens == 0 ? "None set up" : "on now", on > 0 ? FC.ok : FC.ink)
        }
        .background(FC.line)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: FC.scrim.opacity(0.18), radius: 15, y: 8)
    }
    private func stat(_ label: String, _ value: String, _ sub: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(FC.muted)
            Text(value).font(FC.display(34)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).font(.system(size: 12)).foregroundStyle(FC.muted).lineLimit(1)
        }
        .padding(.horizontal, 18).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
        .background(FC.card)
    }

    // ---- leaderboard (match play: the matches as they stand, and the cup) ----
    @ViewBuilder private var leaderboard: some View {
        if let live, live.format.isMatch { matchList(live) } else { strokeBoard }
    }
    private func matchList(_ live: EventState) -> some View {
        let all = Core.matches(live, live.scores), c = Core.cup(live, live.scores, all)
        let list = Array((all.filter { $0.started && !$0.done } + all.filter(\.done) + all.filter { !$0.started }).prefix(6))
        func nm(_ id: String) -> String { ev.teams.first { $0.id == id }?.shortName ?? "" }
        return VStack(spacing: 0) {
            HStack {
                Text("Matches" + (c.on ? " · \(c.a) \(Core.fmtPts(c.A)), \(c.b) \(Core.fmtPts(c.B))" : "")).font(.system(size: 14, weight: .bold))
                Spacer()
                Button("All scores ›") { nav.section = .scores }.buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(FC.link)
            }
            .padding(.leading, 16).padding(.trailing, 20).padding(.vertical, 12)
            if list.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "person.2").font(.system(size: 26)).foregroundStyle(FC.muted)
                    Text(ev.teams.isEmpty ? "Add teams on the Teams page, then Save." : "Pair the teams with Matches on the Teams page.").font(.callout).foregroundStyle(FC.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            }
            ForEach(list) { r in
                let w = r.winner ?? r.leader
                Divider().overlay(FC.hairline)
                HStack(spacing: 6) {
                    Text(nm(r.a)).fontWeight(w == "A" ? .bold : .regular).lineLimit(1)
                    Text("v").foregroundStyle(FC.muted)
                    Text(nm(r.b)).fontWeight(w == "B" ? .bold : .regular).lineLimit(1)
                    Spacer()
                    Text(r.done ? "Final" : r.started ? "Thru \(r.thru)" : r.thru).font(.system(size: 12)).foregroundStyle(FC.muted).frame(width: 70, alignment: .leading)
                    Text(r.started ? r.text : "–").font(FC.display(22)).lineLimit(1).fixedSize().frame(minWidth: 58, alignment: .trailing)
                }
                .font(.system(size: 14))
                .padding(.leading, 16).padding(.trailing, 20).padding(.vertical, 7)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 260, alignment: .top)
        .raisedCard()
    }
    private var strokeBoard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Leaderboard").font(.system(size: 14, weight: .bold))
                Spacer()
                Button("All scores ›") { nav.section = .scores }.buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(FC.link)
            }
            .padding(.leading, 16).padding(.trailing, 20).padding(.vertical, 12)
            let top = Array(board.filter { $0.played > 0 }.prefix(5))
            if top.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "flag.2.crossed").font(.system(size: 26)).foregroundStyle(FC.muted)
                    Text(ev.teams.isEmpty ? "Add teams on the Teams page, then Save." : "Scores show here as the carts send them.").font(.callout).foregroundStyle(FC.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            }
            ForEach(top) { l in
                Divider().overlay(FC.hairline)
                HStack(spacing: 12) {
                    Text(l.pos).font(.system(size: 14, weight: .bold)).foregroundStyle(FC.muted).frame(width: 30, alignment: .leading)
                    Text(l.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Text(l.thru == "F" ? "F" : "Thru \(l.thru)").font(.system(size: 12)).foregroundStyle(FC.muted).frame(width: 60, alignment: .leading)
                    Text(scoreText(l)).font(FC.display(22)).foregroundStyle(scoreColor(l)).lineLimit(1).fixedSize().frame(minWidth: 58, alignment: .trailing)
                }
                .padding(.leading, 16).padding(.trailing, 20).padding(.vertical, 7)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 260, alignment: .top)
        .raisedCard()
    }
    private func scoreText(_ l: Line) -> String { ev.format.isStableford ? "\(l.score)" : Core.fmtPar(l.score) }
    private func scoreColor(_ l: Line) -> Color { ev.format.isStableford ? FC.ink : l.score < 0 ? FC.red : l.score > 0 ? FC.blue : FC.ink }

    // ---- closest to the pin ----
    private var contestTile: some View {
        let c = (live?.contests ?? ev.contests).first { !$0.isLongDrive } ?? (live?.contests ?? ev.contests).first
        let lead = c.flatMap { Core.contestLeader($0).first }
        return ZStack(alignment: .bottomLeading) {
            Color.clear.overlay {
                if let c { HolePicture(id: doc.id, n: c.hole, h: ev.map.holes[c.hole], fallback: doc.picture.image) } else { CourseHeroImage(image: doc.picture.image) }
            }
            .clipped()
            LinearGradient(colors: [FC.scrim.opacity(0.88), FC.scrim.opacity(0)], startPoint: .bottom, endPoint: .init(x: 0.5, y: 0.35))
            VStack(alignment: .leading, spacing: 2) {
                Text(c.map { "\($0.isLongDrive ? "LONG DRIVE" : "CLOSEST TO THE PIN") · HOLE \($0.hole)" } ?? "CONTESTS").font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(FC.flag)
                Text(lead?.name ?? (c == nil ? "No contests yet" : "No results yet")).font(FC.display(30)).lineLimit(1).minimumScaleFactor(0.6)
                Text(lead.flatMap { l in c.map { Core.fmtDist($0, l.dist) } }.map { d in d + (c?.sponsor.isEmpty == false ? " · presented by \(c!.sponsor)" : "") }
                     ?? (c == nil ? "Add one on the Contests page." : "Marshals post results from the phone app."))
                    .font(.system(size: 13)).foregroundStyle(Color(hex: 0xdfe8e1)).lineLimit(1)
            }
            .foregroundStyle(.white).padding(.horizontal, 18).padding(.bottom, 16)
        }
        .frame(minHeight: 260)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle()).onTapGesture { nav.section = .contests }
    }

    // ---- the codes golfers and staff type on the join screen ----
    private var codesTile: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Codes").font(.system(size: 14, weight: .bold))
                Spacer()
                Button("Cart codes ›") { nav.section = .links }.buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(FC.link)
            }
            .padding(.leading, 16).padding(.trailing, 20).padding(.vertical, 12)
            Divider().overlay(FC.hairline)
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tournament code").font(.system(size: 12, weight: .semibold)).foregroundStyle(FC.muted)
                    Text(doc.id.uppercased()).font(.system(size: 34, weight: .bold, design: .monospaced)).foregroundStyle(FC.ink).textSelection(.enabled)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Golf pros and marshals").font(.system(size: 12, weight: .semibold)).foregroundStyle(FC.muted)
                    if ev.pins.isEmpty {
                        HStack(spacing: 10) {
                            Text("No golf pros or marshals yet").font(.system(size: 14)).foregroundStyle(FC.muted)
                            Button("Add them on Staff ›") { nav.section = .staff }.buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(FC.link)
                        }
                    }
                    ForEach(ev.pins) { p in
                        HStack(spacing: 10) {
                            Image(systemName: p.role == "marshal" ? "flag" : "person.badge.key").foregroundStyle(FC.muted).frame(width: 18)
                            Text(p.name.isEmpty ? (p.role == "marshal" ? "Marshal" : "Golf pro") : p.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                            Text(p.role == "marshal" ? "Marshal" : "Golf pro").font(.system(size: 12)).foregroundStyle(FC.muted)
                            Spacer(minLength: 12)
                            Text("PIN \(p.pin)").font(.system(size: 15, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16).padding(.top, 14)
            Text("Golfers type the tournament code and their cart code. Pros and marshals type the tournament code and their PIN.")
                .font(.system(size: 12)).foregroundStyle(FC.muted).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .raisedCard()
    }
}
