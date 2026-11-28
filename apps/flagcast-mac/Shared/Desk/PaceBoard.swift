import SwiftUI

/// Pace of play (the web desk's Pace of play section): every group's round clock and time on the hole it's playing,
/// slowest first, ahead or behind the goal (Core.pace), a Nudge for the slow ones, and the goal (day op "pace").
/// Shared by the Mac Manager (PaceView) and the iPhone and iPad Manager (PaceScreen).
struct PaceBoard: View {
    let doc: DeskDoc
    var compact = false
    @State private var sent: Set<String> = []

    private static let goals = Array(stride(from: 180, through: 330, by: 5))

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let now = ctx.date.timeIntervalSince1970 * 1000
            if let s = doc.live { board(s, now) } else { ProgressView().frame(maxWidth: .infinity) }
        }
    }

    private struct Row: Identifiable { let team: Team; let pace: Pace?; var id: String { team.id } }

    @ViewBuilder private func board(_ s: EventState, _ now: Double) -> some View {
        let rows = s.teams.map { Row(team: $0, pace: Core.pace(s, $0.id, now: now)) }.sorted { a, b in
            let oa = a.pace.map { $0.fin ? 1 : 0 } ?? 2, ob = b.pace.map { $0.fin ? 1 : 0 } ?? 2
            return oa != ob ? oa < ob : (a.pace?.vs ?? 0) > (b.pace?.vs ?? 0)
        }
        let on = rows.filter { $0.pace.map { !$0.fin } ?? false }, fin = rows.filter { $0.pace?.fin ?? false }
        let behind = on.filter { $0.pace?.level != .ok }
        let avg = on.isEmpty ? 0 : Int((on.reduce(0) { $0 + ($1.pace?.vs ?? 0) } / Double(on.count) / 60000).rounded())
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("Goal for 18 holes").font(.callout.weight(.semibold)).foregroundStyle(FC.ink)
                Picker("Goal", selection: Binding(get: { s.paceGoal }, set: { g in Task { await doc.day("pace", ["goal": g], done: "Pace goal saved") } })) {
                    ForEach(Array(Set(Self.goals + [s.paceGoal])).sorted(), id: \.self) { m in Text(Core.clock(Double(m) * 60000) + (m == 255 ? " (usual)" : "")).tag(m) }
                }
                .labelsHidden().fixedSize()
                if !compact { Text("About \(Int((Double(s.paceGoal) / 18).rounded())) minutes a hole. Golfers see the same goal.").font(.caption).foregroundStyle(FC.muted) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: compact ? 2 : 4), spacing: 10) {
                stat("ON THE COURSE", "\(on.count)", on.count == 1 ? "group" : "groups")
                stat("AVERAGE SO FAR", on.isEmpty ? "—" : "\(avg > 0 ? "+" : "")\(avg)", on.isEmpty ? "" : "min v goal")
                stat("BEHIND PACE", "\(behind.count)", behind.count == 1 ? "group" : "groups", red: behind.contains { $0.pace?.level == .red })
                stat("FINISHED", "\(fin.count)", fin.isEmpty ? "" : "avg " + Core.clock(fin.reduce(0) { $0 + ($1.pace?.elapsed ?? 0) } / Double(fin.count)))
            }
            VStack(spacing: 0) {
                if !compact {
                    HStack(spacing: 8) {
                        Text("GROUP").frame(maxWidth: .infinity, alignment: .leading)
                        Text("HOLE").frame(width: 48, alignment: .leading)
                        Text("ON HOLE").frame(width: 70, alignment: .leading)
                        Text("ROUND").frame(width: 60, alignment: .leading)
                        Text("VS GOAL").frame(width: 110, alignment: .leading)
                        Spacer().frame(width: 76)
                    }
                    .font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(FC.muted)
                    .padding(.horizontal, 14).padding(.vertical, 9).background(FC.head)
                }
                ForEach(rows) { r in
                    row(r)
                    if r.id != rows.last?.id { Divider() }
                }
            }
            .background(FC.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(FC.line))
        }
    }

    private func stat(_ label: String, _ value: String, _ unit: String, red: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10, weight: .bold)).tracking(1.1).foregroundStyle(FC.muted).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value).font(FC.display(28)).foregroundStyle(red ? FC.red : FC.ink)
                Text(unit).font(.caption).foregroundStyle(FC.muted).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(FC.card, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(FC.line))
    }

    @ViewBuilder private func row(_ r: Row) -> some View {
        let t = r.team, p = r.pace
        let sub = (t.cart.isEmpty ? "" : "Cart \(t.cart) · ") + (p?.fin == true ? "finished" : "starts on \(t.start)")
        let name = VStack(alignment: .leading, spacing: 2) {
            Text(t.displayName).font(.callout.weight(.semibold)).foregroundStyle(p == nil ? FC.muted : FC.ink).lineLimit(1)
            Text(sub).font(.caption).foregroundStyle(FC.muted).lineLimit(1)
        }
        if let p {
            let holeBadge = Text(p.fin ? "✓" : "\(p.hole)").font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                .frame(minWidth: 30, minHeight: 30).background(p.fin ? FC.ok : Color(hex: 0x3a8bff), in: RoundedRectangle(cornerRadius: 8))
            let onHole = Text(p.fin ? "—" : Core.clock(p.onHole, secs: true)).font(.system(.callout, design: .monospaced).weight(p.slowHole ? .bold : .medium)).foregroundStyle(p.slowHole ? FC.red : FC.ink)
            let round = Text(Core.clock(p.elapsed)).font(.system(.callout, design: .monospaced).weight(.medium)).foregroundStyle(FC.ink)
            if compact {
                HStack(spacing: 10) {
                    holeBadge
                    VStack(alignment: .leading, spacing: 3) {
                        name
                        HStack(spacing: 10) { onHole; Text("·").foregroundStyle(FC.muted); round }.font(.caption)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 6) { chip(p); nudge(t, p) }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            } else {
                HStack(spacing: 8) {
                    name.frame(maxWidth: .infinity, alignment: .leading)
                    holeBadge.frame(width: 48, alignment: .leading)
                    onHole.frame(width: 70, alignment: .leading)
                    round.frame(width: 60, alignment: .leading)
                    chip(p).frame(width: 110, alignment: .leading)
                    nudge(t, p).frame(width: 76, alignment: .trailing)
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
            }
        } else {
            HStack { name; Spacer(); Text("Not started").font(.caption).foregroundStyle(FC.muted) }.padding(.horizontal, 14).padding(.vertical, 9)
        }
    }

    private func chip(_ p: Pace) -> some View {
        let (bg, fg): (Color, Color) = switch p.level {
        case .ok: (Color(hex: 0xe1f3e8), Color(hex: 0x257347))
        case .amber: (Color(hex: 0xfbefd9), Color(hex: 0x9a5d0b))
        case .red: (Color(hex: 0xfbe2df), Color(hex: 0xb23a30))
        }
        return Text(p.word).font(.system(size: 13, weight: .bold)).lineLimit(1).padding(.horizontal, 10).padding(.vertical, 4).background(bg, in: Capsule()).foregroundStyle(fg)
    }

    @ViewBuilder private func nudge(_ t: Team, _ p: Pace) -> some View {
        if !p.fin && p.level != .ok {
            Button(sent.contains(t.id) ? "Sent" : "Nudge") {
                sent.insert(t.id)
                Task { if await doc.day("nudge", ["team": t.id, "text": "Please pick up the pace. Thank you!"], done: "Sent to \(t.displayName)") == nil { sent.remove(t.id) } }
            }
            .buttonStyle(.bordered).controlSize(.small).disabled(sent.contains(t.id))
        }
    }
}

#if os(macOS)
/// The Mac's Pace of play section.
struct PaceView: View {
    let doc: DeskDoc
    var body: some View {
        DeskPage(doc: doc, section: .pace, save: false) {
            EmptyView()
        } title: {
            HeroTitle(title: "Pace of play", size: 52, sub: "Each group’s round clock and time on the hole it’s playing, slowest first. Times come from the cart phones: nothing to start or stop.", subBeside: false)
        } content: {
            ScrollView {
                PaceBoard(doc: doc)
                    .padding(18)
                    .background(FC.paper, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(color: FC.scrim.opacity(0.18), radius: 15, y: 8)
                    .padding(.horizontal, 24).padding(.bottom, 24)
            }
        }
    }
}
#endif
