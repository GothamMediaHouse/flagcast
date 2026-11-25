import SwiftUI

/// A group someone tapped on "Where the groups are" (desk op "groups"), as the card needs it.
struct GroupCardSpot: Hashable {
    var id: String, name: String, start: Int, hole: Int, t: Double
    /// when the group got to this hole (ms), for pace of play; 0 = not known
    var since: Double = 0
    /// a sample group walking the course on a Demo tournament (demogroups.js): nobody gets its messages
    var sample = false
}

/// The card for a tapped group (the web desk's map/index.html groupCard): who they are, where they are, how they're
/// scoring, how long they've been on this hole, and a message to the whole group or one player (day op "nudge").
/// Shared by the Mac Manager (GroupsView) and the iPhone and iPad Manager (DeskExtras GroupsPage).
struct GroupCard: View {
    let doc: DeskDoc
    let group: GroupCardSpot
    var onClose: () -> Void
    @State private var to: String?
    @State private var text = ""
    @State private var sending = false

    /// more than this on one hole shows as slow
    static let paceMins = 15
    static let quick: [(label: String, text: String)] = [
        ("Please pick up the pace", "Please pick up the pace. Thank you!"),
        ("Come to the clubhouse", "Please come to the clubhouse."),
        ("Weather delay", "Weather delay. Please head in."),
    ]

    private var info: Core.GroupInfo? { doc.live.flatMap { Core.groupInfo($0, $0.scores, group.id) } }
    private var team: DeskTeam? { doc.ev.teams.first { $0.id == group.id } }
    private var mins: Int? { group.since > 0 ? max(0, Int((Date().timeIntervalSince1970 * 1000 - group.since) / 60_000)) : nil }
    private var toName: String? { to.flatMap { id in info?.players.first { $0.id == id }?.name } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(group.hole > 0 ? "\(group.hole)" : "?").font(.system(size: 16, weight: .bold, design: .monospaced))
                    .frame(width: 42, height: 42).background(Color(hex: 0x3a8bff), in: RoundedRectangle(cornerRadius: 12, style: .continuous)).foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info?.name ?? group.name).font(.headline).foregroundStyle(FC.ink).lineLimit(1)
                    Text(sub).font(.caption).foregroundStyle(FC.muted)
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).frame(width: 28, height: 28).background(FC.paper2, in: Circle()).foregroundStyle(FC.muted)
                }
                .buttonStyle(.plain).accessibilityLabel("All groups")
            }
            HStack(spacing: 6) {
                stat("HOLE", group.hole > 0 ? "\(group.hole)" : "—")
                stat("THRU", info?.thru ?? "—")
                stat("SCORE", info?.score ?? "—")
                stat("ON HOLE", mins.map { "\($0) min" } ?? "—", warn: (mins ?? 0) > Self.paceMins)
            }
            if let info, !info.players.isEmpty {
                VStack(spacing: 0) {
                    ForEach(info.players, id: \.id) { p in
                        HStack {
                            Text(p.name).foregroundStyle(FC.ink)
                            Text("· \(p.hcp.formatted(.number.precision(.fractionLength(0...1))))").foregroundStyle(FC.muted)
                            Spacer()
                            Button(to == p.id ? "Messaging" : "Message") { to = to == p.id ? nil : p.id }
                                .buttonStyle(.plain).font(.callout.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(to == p.id ? FC.flag : .clear, in: RoundedRectangle(cornerRadius: 6))
                                .foregroundStyle(to == p.id ? FC.onFlag : FC.link)
                        }
                        .font(.callout).padding(.vertical, 6)
                        if p.id != info.players.last?.id { Divider() }
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(Self.quick, id: \.label) { q in
                    Button(q.label) { Task { await send(q.text) } }
                        .buttonStyle(.plain).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(FC.paper, in: Capsule()).overlay(Capsule().stroke(FC.line)).foregroundStyle(FC.ink)
                        .disabled(sending)
                }
            }
            HStack(spacing: 6) {
                TextField(toName.map { "A note to \($0)" } ?? "A note to the whole group", text: $text)
                    .textFieldStyle(.roundedBorder).onSubmit { Task { await send(text) } }
                Button("Send") { Task { await send(text) } }
                    .buttonStyle(.borderedProminent).tint(FC.primary)
                    .disabled(sending || text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text(toName.map { "Goes to \($0)’s phone if they picked their name, otherwise the cart." } ?? "Pops up on every scorecard in this group.")
                .font(.caption).foregroundStyle(FC.muted)
        }
        .padding(14)
        .background(FC.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(FC.line))
        .onChange(of: group.id) { _, _ in to = nil; text = "" }
    }

    private var sub: String {
        let ago: String = {
            let m = Int((Date().timeIntervalSince1970 * 1000 - group.t) / 60_000)
            return m < 1 ? "GPS just now" : "GPS \(m) min ago"
        }()
        return [team.map { $0.cart.isEmpty ? "" : "Cart \($0.cart)" } ?? "", group.start > 0 ? "started hole \(group.start)" : "",
                group.sample ? "sample group on the demo" : "", ago].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func stat(_ label: String, _ value: String, warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1).foregroundStyle(FC.muted).lineLimit(1)
            Text(value).font(.system(size: 16, weight: .bold).monospacedDigit()).foregroundStyle(warn ? Color.orange : FC.ink).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.vertical, 6)
        .background(FC.paper2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func send(_ message: String) async {
        let t = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !sending else { return }
        if group.sample { doc.flash("Sent to \(group.name) (a sample group, so nobody gets it)."); text = ""; return }
        sending = true
        var b: [String: Any] = ["team": group.id, "text": t]
        if let to { b["player"] = to }
        if await doc.day("nudge", b, done: "Sent to \(toName ?? (info?.name ?? group.name))") != nil { text = "" }
        sending = false
    }
}

/// "Golfers can send ready-made notes" (day op "notes"): the switch under the list of groups.
struct GolferNotesToggle: View {
    let doc: DeskDoc
    @State private var off: Bool?
    var body: some View {
        Toggle(isOn: Binding(get: { !(off ?? doc.live?.notesOff ?? false) }, set: { v in
            off = !v
            Task { _ = await doc.day("notes", ["off": !v], done: v ? "Golfer notes are on" : "Golfer notes are off") }
        })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Golfer notes").font(.callout.weight(.semibold)).foregroundStyle(FC.ink)
                Text("Golfers can send ready-made notes to other groups (“Nice round!”, “Want to play through?”).").font(.caption).foregroundStyle(FC.muted)
            }
        }
        .tint(FC.ok)
    }
}
