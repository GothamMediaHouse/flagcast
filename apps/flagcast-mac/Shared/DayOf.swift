import SwiftUI

/// "Day of": the three things that go wrong on event day, each with a one-tap fix. TVs on, par 3 cameras sending,
/// and carts keeping their scores up to date (a nudge for the ones that have gone quiet). Shared by the Mac and
/// iPhone Manager Home; each wraps it in its own card.
struct DayOfChecks: View {
    @Bindable var doc: DeskDoc
    var openScreens: () -> Void
    @State private var camsLive: [Int: Bool] = [:]
    @State private var nudged: Set<String> = []
    @State private var busy = false
    @State private var now = Date()

    private var live: EventState? { doc.live }
    private var tvs: (on: Int, all: Int, off: [String]) {
        let d = doc.ev.displays, online = live?.online ?? [:]
        let off = d.filter { (online[$0.id] ?? 0) == 0 }.map(\.name)
        return (d.count - off.count, d.count, off)
    }
    /// carts that have gone quiet: no score for 20 minutes, while others are scoring (or the round has been going 20 min)
    private var slow: [DeskTeam] { DayOfChecks.slowCarts(teams: doc.ev.teams, lastAt: live?.lastAt ?? [:], now: now) }
    static func slowCarts(teams: [DeskTeam], lastAt: [String: Double], now: Date) -> [DeskTeam] {
        let ms = now.timeIntervalSince1970 * 1000, quiet = 20.0 * 60000
        guard let first = lastAt.values.min(), ms - first > quiet else { return [] }   // the round hasn't been going 20 minutes
        return teams.filter { t in (lastAt[t.id].map { ms - $0 > quiet } ?? true) }
    }
    /// the tournament's day, or scores in the last three hours
    static func isEventDay(_ doc: DeskDoc) -> Bool {
        if doc.ev.date == ISO8601DateFormatter.day.string(from: Date()) { return true }
        return (doc.live?.lastAt.values.max() ?? 0) > (Date().timeIntervalSince1970 - 3 * 3600) * 1000
    }
    private var holesWithCams: [Int] { (live?.cams ?? [:]).keys.sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Day of").font(.headline)
            row(ok: tvs.all == 0 || tvs.off.isEmpty, icon: "tv",
                title: tvs.all == 0 ? "No TVs set up" : "\(tvs.on) of \(tvs.all) TVs on",
                sub: tvs.off.isEmpty ? (tvs.all == 0 ? "Add the club’s TVs on the Screens page." : "Every TV is showing Flagcast.") : "Off: \(tvs.off.prefix(3).joined(separator: ", "))\(tvs.off.count > 3 ? " and \(tvs.off.count - 3) more" : "")",
                button: tvs.all == 0 || !tvs.off.isEmpty ? "Screens" : nil, act: openScreens)
            if !holesWithCams.isEmpty {
                row(ok: camsDown.isEmpty && camsLive.count == holesWithCams.count, icon: "video", title: camsTitle, sub: camsSub,
                    button: "Check Again", act: { Task { await checkCams() } })
            }
            row(ok: slow.isEmpty, icon: "list.number", title: cartsTitle, sub: cartsSub,
                button: quiet.isEmpty ? nil : "Nudge \(quiet.count)", act: { Task { await nudge(quiet) } })
        }
        .task { await checkCams() }
        .task { while !Task.isCancelled { try? await Task.sleep(for: .seconds(30)); now = Date() } }
    }

    private var camsDown: [Int] { holesWithCams.filter { camsLive[$0] == false } }
    private var camsTitle: String { camsLive.count < holesWithCams.count ? "Checking the par 3 cameras…" : "\(holesWithCams.count - camsDown.count) of \(holesWithCams.count) par 3 cameras live" }
    private var camsSub: String { camsDown.isEmpty ? "Phones and TVs can watch every par 3." : "Not sending: hole \(camsDown.map(String.init).joined(separator: ", ")). Flagcast staff look after the cameras." }
    private var quiet: [DeskTeam] { slow.filter { !nudged.contains($0.id) } }
    private var cartsTitle: String { doc.ev.teams.isEmpty ? "No teams yet" : "\(doc.ev.teams.count - slow.count) of \(doc.ev.teams.count) carts scored in the last 20 min" }
    private var cartsSub: String {
        slow.isEmpty ? "Scores are coming in." : "Quiet: \(slow.prefix(3).map(\.displayName).joined(separator: ", "))\(slow.count > 3 ? " and \(slow.count - 3) more" : "")"
    }

    private func row(ok: Bool, icon: String, title: String, sub: String, button: String?, act: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill").font(.title3).foregroundStyle(ok ? Color.green : Color.orange)
                .accessibilityLabel(ok ? "OK" : "Needs a look")
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).labelStyle(.titleOnly)
                Text(sub).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let button { Button(button, action: act).buttonStyle(.bordered).disabled(busy) }
        }
    }

    /// is each par 3 camera's stream answering? (its address gives a playlist while it's sending)
    private func checkCams() async {
        var out: [Int: Bool] = [:]
        await withTaskGroup(of: (Int, Bool).self) { g in
            for (h, s) in live?.cams ?? [:] {
                g.addTask {
                    guard let u = URL(string: s) else { return (h, false) }
                    var r = URLRequest(url: u); r.timeoutInterval = 6
                    let code = ((try? await URLSession.shared.data(for: r))?.1 as? HTTPURLResponse)?.statusCode
                    return (h, code == 200)
                }
            }
            for await (h, ok) in g { out[h] = ok }
        }
        camsLive = out
    }

    /// one tap: a friendly reminder on each quiet cart's scorecard
    private func nudge(_ teams: [DeskTeam]) async {
        busy = true
        for t in teams {
            if await doc.day("nudge", ["team": t.id, "text": "Don’t forget your scores: tap in each hole on your phone so the leaderboard stays live. Thank you!"]) != nil { nudged.insert(t.id) }
        }
        busy = false
        doc.flash("Nudged \(teams.count) cart\(teams.count == 1 ? "" : "s"). They see it on their scorecard.")
    }
}

/// Which cameras golfers see on the Cameras tab and the live page (day op "camshow"): a switch per camera (the pro's
/// phone, contest holes, par 3s, the clubhouse and 18th green), and one for golfers' "Save your shot". Shared by the
/// Mac and iPhone/iPad Manager; each wraps it in its own card. The TVs show whatever the desk routes to them.
struct PlayerCameraSwitches: View {
    @Bindable var doc: DeskDoc
    /// padding for each row (the iPhone's cards draw rows edge to edge)
    var inset: CGFloat = 0
    /// changed here and not back from the server yet
    @State private var offNow: Set<Int>?
    @State private var clipsNow: Bool?
    @State private var juniorNow: Bool?
    @State private var nocamNow: Set<String>?

    private var cams: [CamItem] { doc.live?.camList(all: true) ?? [] }
    private var off: Set<Int> { offNow ?? Set(doc.live?.camsOff ?? []) }
    private var clips: Bool { clipsNow ?? !(doc.live?.clipsOff ?? false) }
    private var junior: Bool { juniorNow ?? (doc.live?.junior ?? false) }
    private var nocam: Set<String> { nocamNow ?? Set(doc.live?.nocam ?? []) }
    private var teams: [Team] { doc.live?.teams ?? [] }
    private static let tags: [CamItem.Kind: String] = [.pro: "Pro’s phone", .contest: "Contest", .par3: "Par 3", .club: "Around the club", .hole: "Hole"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if cams.isEmpty {
                Text(doc.live == nil ? "Loading the cameras…" : "No cameras yet. Flagcast adds camera links in Admin, or a golf pro can go live from the Flagcast app.")
                    .font(.subheadline).foregroundStyle(.secondary).padding(inset).padding(.vertical, 6)
            }
            ForEach(cams) { c in
                Toggle(isOn: Binding(get: { !off.contains(c.n) }, set: { on in set(c.n, on) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(c.title).font(.subheadline.weight(.semibold))
                            Text(Self.tags[c.kind] ?? "").font(.caption2.monospaced().weight(.semibold)).textCase(.uppercase)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(c.kind == .pro ? Color.yellow.opacity(0.35) : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                        }
                        let sub = [c.kind == .pro ? "Live from \(c.by.isEmpty ? "an" : "\(c.by)’s") iPhone" : "", c.sub].filter { !$0.isEmpty }.joined(separator: " · ")
                        if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .padding(.horizontal, inset).padding(.vertical, 6)
                Divider().padding(.leading, inset)
            }
            Toggle(isOn: Binding(get: { clips }, set: { on in setClips(on) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Golfers can save their shot").font(.subheadline.weight(.semibold))
                    Text(junior ? "Off for a junior event" : "A “Save your shot” button on the scorecard of camera holes: a 15-second replay from the club’s camera").font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(junior)
            .padding(.horizontal, inset).padding(.vertical, 6)
            Divider().padding(.leading, inset)
            // privacy (day op "privacy"): groups that asked to stay off camera, and junior events
            VStack(alignment: .leading, spacing: 6) {
                Text("Groups that asked to stay off camera").font(.subheadline.weight(.semibold))
                Text("They can’t save their shot, their saved shots are removed, and please don’t send replays of them to the screens. To take a clip down later, email hello@flagcast.app.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach(teams.filter { nocam.contains($0.id) }) { t in
                    HStack {
                        Text(t.displayName).font(.subheadline)
                        Spacer()
                        Button("Back on camera") { setNocam(t.id, false) }.font(.caption)
                    }
                }
                Menu("Keep a group off camera") {
                    ForEach(teams.filter { !nocam.contains($0.id) }) { t in Button(t.displayName) { setNocam(t.id, true) } }
                }
                .disabled(teams.allSatisfy { nocam.contains($0.id) })
            }
            .padding(.horizontal, inset).padding(.vertical, 6)
            Divider().padding(.leading, inset)
            Toggle(isOn: Binding(get: { junior }, set: { on in setJunior(on) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Junior event").font(.subheadline.weight(.semibold))
                    Text("For players under 18: golfers don’t see other groups on the course map, no Save your shot, no notes between groups and no invite emails. Get parents’ OK before juniors appear on cameras.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, inset).padding(.vertical, 6)
        }
        .onChange(of: doc.live?.camsOff) { offNow = nil }
        .onChange(of: doc.live?.clipsOff) { clipsNow = nil }
        .onChange(of: doc.live?.junior) { juniorNow = nil }
        .onChange(of: doc.live?.nocam) { nocamNow = nil }
    }

    private func set(_ n: Int, _ on: Bool) {
        var o = off; if on { o.remove(n) } else { o.insert(n) }
        offNow = o
        Task { if await doc.day("camshow", ["off": o.sorted()], done: on ? "Golfers see that camera." : "Hidden from golfers.") == nil { offNow = nil } }
    }
    private func setJunior(_ on: Bool) {
        juniorNow = on
        Task { if await doc.day("privacy", ["junior": on], done: on ? "Junior event: those are off for golfers." : "Junior event is off.") == nil { juniorNow = nil } }
    }
    private func setNocam(_ team: String, _ off: Bool) {
        var s = nocam; if off { s.insert(team) } else { s.remove(team) }
        nocamNow = s
        Task { if await doc.day("privacy", ["team": team, "nocam": off], done: off ? "That group stays off camera." : "They can be on camera again.") == nil { nocamNow = nil } }
    }
    private func setClips(_ on: Bool) {
        clipsNow = on
        Task { if await doc.day("camshow", ["clips": on], done: on ? "Golfers can save their shot." : "Save your shot is off.") == nil { clipsNow = nil } }
    }
}
