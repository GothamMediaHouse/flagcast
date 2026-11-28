import Foundation
import Observation
import UIKit
import UserNotifications
import ActivityKit

/// A score typed on this phone that the server hasn't confirmed yet. Kept on disk until it's sent, so a cart
/// with no signal keeps scoring; `at` is when it was typed, so a late send never undoes a newer fix.
struct PendingScore: Codable, Hashable {
    var team: String
    var p: String
    var h: Int
    var v: Int?
    var at: Double
}

/// The cart scorecard (matches public/golf/score/): which teams this cart's code scores for, the hole on screen,
/// scores waiting to send, this cart's side-game settings, and messages from the pro shop.
@MainActor @Observable
final class ScorecardModel {
    let id: String
    let code: String
    let feed: EventFeed
    let hits: SponsorHits

    var teams: [String] { didSet { save("teams", teams) } }
    var teamId: String? { didSet { save("team", teamId) } }
    var hole: Int? { didSet { save("hole", hole) } }
    private(set) var pending: [PendingScore] { didSet { save("pending", pending) } }
    var side: SideConfig { didSet { save("side", side) } }
    /// whether this cart has side-game settings of its own yet (a Demo tournament starts a new cart with Skins and Wolf on)
    private var sideSaved = false
    /// Which golfer holds this phone (a player id), "-" when they skipped the question, nil before it's asked.
    var me: String? { didSet { save("me", me) } }

    private(set) var sending = false
    var toast: String?
    var nudge: Nudge?
    /// The cart code isn't in this tournament (the server said so).
    private(set) var codeError: String?
    /// Bumped on each score change and each hole in one, for haptics and the celebration.
    private(set) var changes = 0
    private(set) var aces = 0
    var celebrating = false

    @ObservationIgnored private var retry: Task<Void, Never>?

    private var keyBase: String { "golf:\(id):\(code)" }
    private func save<T: Encodable>(_ k: String, _ v: T) { Store.set("\(keyBase):\(k)", v) }

    init(id: String, code: String) {
        self.id = id
        self.code = code
        feed = Feeds.feed(id)
        hits = SponsorHits(id: id)
        let base = "golf:\(id):\(code)"
        teams = Store.get("\(base):teams", [String]())
        teamId = Store.get("\(base):team", String?.none)
        hole = Store.get("\(base):hole", Int?.none)
        pending = Store.get("\(base):pending", [PendingScore]())
        side = Store.get("\(base):side", SideConfig())
        sideSaved = UserDefaults.standard.data(forKey: "\(base):side") != nil
        me = Store.get("\(base):me", String?.none)
    }

    var state: EventState? { feed.state }
    var team: Team? { state?.team(teamId) }

    /// "Try a demo" (a tournament Admin marked Demo): the cart's round clock starts when its scorecard opens, and again
    /// after 3 hours; it goes with the scores so the desk sees the same start (the web scorecard's myPace)
    var tryStart: Double {
        let now = Date().timeIntervalSince1970 * 1000, k = "\(keyBase):trystart", was = Store.get(k, 0.0)
        if was > 0 && now - was < 3 * 3600_000 { return was }
        Store.set(k, now); return now
    }
    /// The round and hole clocks for this cart (Core.pace), nil before its round starts
    func pace(now: Double = Date().timeIntervalSince1970 * 1000) -> Pace? {
        guard let s = state, let t = teamId else { return nil }
        if let p = Core.pace(s, t, now: now) { return p }
        return s.brand.marked ? Core.pace(s, t, now: now, times: PaceTimes(s: tryStart)) : nil
    }

    func start() {
        feed.onState["score:\(code)"] = { [weak self] s in self?.arrived(s) }
        feed.onLink["score:\(code)"] = { [weak self] on in if on { self?.send() } }
        feed.start()
        Locator.shared.onFix["score:\(code)"] = { [weak self] p, acc in self?.reportSpot(p, acc) }
        Task { await lookUpCart() }
        if let s = state { arrived(s) }
        send()
        askForNotifications()
    }

    // ---- group spot for the desk and the other golfers' Everyone map (only while the tournament is on): every 30 s,
    // or sooner after a walk. A group that hides (GroupPrivacy) is still seen by the desk, not by other golfers ----
    @ObservationIgnored private var sentSpot: (at: GeoPoint, t: Date)?
    func reportSpot(_ at: GeoPoint, _ acc: Int) {
        guard let s = state, let t = teamId, Geo.trackingOn(s) else { return }
        if let last = sentSpot, Date().timeIntervalSince(last.t) < 30, (Geo.yds(last.at, at) ?? 0) < 25 { return }
        sentSpot = (at, Date())
        let h = currentHole()
        Task { _ = try? await API.post(id, "where", ["code": code, "team": t, "at": [at.lat, at.lng], "acc": acc, "hole": h, "hide": GroupPrivacy.hidden(code)]) }
    }

    func stop() {
        Locator.shared.onFix["score:\(code)"] = nil
        feed.onState["score:\(code)"] = nil
        feed.onLink["score:\(code)"] = nil
        feed.stop()
        retry?.cancel()
    }

    /// Which teams this cart's QR code scores for (POST …/cart). With no signal, carry on with what this phone knows.
    func lookUpCart() async {
        do {
            let r = try await API.post(id, "cart", ["code": code])
            let list = (r["teams"] as? [String]) ?? []
            codeError = nil
            teams = list
            if teamId == nil || !list.contains(teamId!) { teamId = list.first; hole = nil }
            settleHole()
        } catch let e as APIError where e.status == 404 {
            codeError = e.message
        } catch {}
    }

    private func arrived(_ s: EventState) {
        Recents.remember(id: id, name: s.name, code: code)
        if teamId == nil, let first = teams.first { teamId = first }
        settleHole()
        demoSides(s)
        checkNudges(s)
        LiveView.shared.update(self) // the lock screen live view
    }

    /// a Demo tournament ("Try a demo"): a cart that hasn't set its side games starts with Skins and Wolf on (net, with
    /// the stroke dots), so the demo shows them. Same as the web scorecard; after that the cart's own settings are kept.
    private func demoSides(_ s: EventState) {
        guard !sideSaved, s.brand.marked, s.sideGamesAllowed else { return }
        sideSaved = true
        side.skins.on = true; side.wolf.on = true; side.wolf.net = true
    }

    // ---- scores ----

    /// Scores as this phone knows them: the server's, with anything still waiting to send on top.
    func myScores() -> Scores {
        var sc = state?.scores ?? [:]
        for e in pending {
            var t = sc[e.team] ?? [:]
            var arr = t[e.p] ?? Array(repeating: nil, count: 18)
            if arr.count < 18 { arr += Array(repeating: nil, count: 18 - arr.count) }
            arr[e.h - 1] = e.v
            t[e.p] = arr
            sc[e.team] = t
        }
        return sc
    }

    /// The holes this cart plays, in order from its starting hole (only the front or back 9 on a 9-hole round;
    /// a start outside those 9 means the first of them).
    func order(_ t: Team) -> [Int] {
        guard let s = state else { return (0..<18).map { (max(1, t.start) - 1 + $0) % 18 + 1 } }
        let ph = Core.playHoles(s), k = ph.firstIndex(of: max(1, t.start)) ?? 0
        return Array(ph[k...] + ph[..<k])
    }

    /// The hole on screen. Picked once when the card opens (the first hole in playing order still missing a
    /// score), then it only moves when the golfer moves it, like the web scorecard. A hole saved from before the
    /// round was set to 9 holes is dropped.
    func currentHole() -> Int {
        if let h = hole, let t = team, state != nil, !order(t).contains(h) { return firstOpenHole() }
        return hole ?? firstOpenHole()
    }

    private func firstOpenHole() -> Int {
        guard let s = state, let t = team else { return 1 }
        let who = s.scorers(t)
        let ord = order(t)
        return ord.first { h in !who.allSatisfy { value($0.id, h) != nil } } ?? ord[0]
    }
    private func settleHole() { if hole == nil, state != nil, team != nil { hole = firstOpenHole() } }

    func switchTeam(_ id: String) {
        teamId = id
        hole = nil
        settleHole()
        LiveView.shared.update(self)
    }

    func value(_ p: String, _ h: Int) -> Int? {
        guard let t = team, let arr = myScores()[t.id]?[p], arr.count >= h else { return nil }
        return arr[h - 1]
    }

    func holeDone(_ h: Int) -> Bool {
        guard let s = state, let t = team else { return false }
        return s.scorers(t).allSatisfy { value($0.id, h) != nil }
    }

    /// − / score / + : tapping the score enters par; − and + step from par when nothing's entered yet.
    func step(_ p: String, _ d: Int) {
        guard let s = state else { return }
        if s.locked { toast = "Scoring is closed. The results are final."; return }
        let h = currentHole(), par = s.course.holes[h - 1].par
        let cur = value(p, h)
        let base = (cur == nil || cur == 0) ? par : cur!
        let v = d == 0 ? base : cur == nil ? par + d : base + d
        set(p, h, max(1, min(15, v)))
    }
    func pickedUp(_ p: String) { guard guardOpen() else { return }; set(p, currentHole(), 0) }
    func clear(_ p: String) { guard guardOpen() else { return }; set(p, currentHole(), nil) }
    private func guardOpen() -> Bool {
        if state?.locked == true { toast = "Scoring is closed. The results are final."; return false }
        return true
    }

    private func set(_ p: String, _ h: Int, _ v: Int?) {
        guard let t = teamId else { return }
        let was = value(p, h)
        pending.removeAll { $0.team == t && $0.p == p && $0.h == h }
        pending.append(PendingScore(team: t, p: p, h: h, v: v, at: (Date().timeIntervalSince1970 * 1000).rounded()))
        changes += 1
        if v == 1 && was != 1 {
            aces += 1
            celebrating = true
            toast = "Hole in one! It’s on the big screens now."
        }
        LiveView.shared.update(self)
        send()
    }

    /// Send what's waiting, one team at a time. Kept on the phone until the server takes it.
    func send() {
        guard !sending, !pending.isEmpty else { return }
        sending = true
        let batch = pending
        Task {
            var failed = false
            let byTeam = Dictionary(grouping: batch, by: \.team)
            for (t, list) in byTeam {
                do {
                    let body: [String: Any?] = ["code": code, "team": t, "start": state?.brand.marked == true ? tryStart : nil,
                        "list": list.map { ["p": $0.p, "h": $0.h, "v": $0.v.map { $0 as Any } ?? NSNull(), "at": $0.at] as [String: Any] }]
                    try await API.post(id, "score", body)
                    let sent = Set(list)
                    pending.removeAll { sent.contains($0) }
                } catch let e as APIError where e.status == 423 || e.status == 403 {
                    // scoring closed, or this code can't score for that team: these will never go through
                    let drop = Set(list)
                    pending.removeAll { drop.contains($0) }
                    toast = e.message
                } catch {
                    failed = true
                }
            }
            sending = false
            if !pending.isEmpty {
                retry?.cancel()
                retry = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(failed ? 5 : 0.3))
                    if !Task.isCancelled { self?.send() }
                }
            }
        }
    }

    var syncText: String {
        if !pending.isEmpty { return "\(pending.count) waiting" }
        if !feed.online { return "Offline · kept" }
        return "All saved"
    }
    var synced: Bool { pending.isEmpty && feed.online }

    // ---- the team's standing ----
    func line() -> Line? {
        guard let s = state, let t = team else { return nil }
        return Core.leaderboard(s, myScores()).first { $0.teamId == t.id }
    }

    // ---- nudges from the pro shop (for example: keep up the pace of play) ----
    private var nudgeKey: String { "golf:\(id):nudge" }
    private func checkNudges(_ s: EventState) {
        let seen = UserDefaults.standard.object(forKey: nudgeKey) as? Double ?? (Date().timeIntervalSince1970 * 1000 - 15 * 60000)
        // to everyone, to this cart, or to one golfer (only their phone, once they've said which one they are)
        let mine = s.nudges.filter { n in
            (n.team == "*" || teams.contains(n.team)) && (n.player == nil || me == nil || me == "-" || n.player == me) && n.at > seen
        }
        guard let n = mine.last else { return }
        UserDefaults.standard.set(n.at, forKey: nudgeKey)
        nudge = n
        // with the lock screen live view on, the server's push shows the message there and buzzes once
        let liveOn = LiveView.enabled && Activity<FlagcastLiveAttributes>.activities.contains { $0.attributes.event == id && $0.attributes.code == code && $0.activityState == .active }
        if UIApplication.shared.applicationState != .active && !liveOn {
            let c = UNMutableNotificationContent()
            c.title = n.from.map { "From \($0)" } ?? "From the pro shop"
            c.body = n.text
            c.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "nudge-\(Int(n.at))", content: c, trigger: nil))
        }
    }

    private func askForNotifications() {
        let k = "flagcast.askedNotifications"
        guard !UserDefaults.standard.bool(forKey: k) else { return }
        UserDefaults.standard.set(true, forKey: k)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // ---- side games ----
    func sideResult() -> SideResult? {
        guard let s = state else { return nil }
        return Core.sideGames(s, myScores(), teams, side)
    }
}
