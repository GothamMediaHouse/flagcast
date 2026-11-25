import Foundation
import ActivityKit
import UIKit

/// The live view on the lock screen and in the Dynamic Island (a Live Activity, drawn by the FlagcastLive widget):
/// the team's score, place and hole stay there while the app is closed. It starts when a scorecard opens on the
/// tournament day, updates from the app while it's open, and from the server's Apple pushes while it's closed
/// (liveact.js on the server). Settings → Live score on the lock screen turns it off.
@MainActor
final class LiveView {
    static let shared = LiveView()
    static let settingKey = "flagcast.liveView"
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: settingKey); if !newValue { Task { await shared.endAll() } } }
    }

    private var watching: Set<String> = []    // activity ids whose push tokens we're sending
    private var lastKey: [String: LiveCard] = [:]

    /// After each change on the scorecard: start, update or end this cart's live view.
    func update(_ m: ScorecardModel) {
        guard let s = m.state, let t = m.team else { return }
        let mine = Activity<FlagcastLiveAttributes>.activities.filter { $0.attributes.event == m.id && $0.attributes.code == m.code }
        // another team on the same cart: the card follows the team on screen
        for a in mine where a.attributes.team != t.id { end(a, nil, m) }
        let current = mine.first { $0.attributes.team == t.id && $0.activityState == .active }
        guard Self.enabled, let card = Self.card(m) else { return }
        if card.final {
            if let current { end(current, card, m) }
            return
        }
        if let current {
            var a = card, b = lastKey[current.id] ?? current.content.state; a.at = 0; b.at = 0
            guard a != b else { return }
            lastKey[current.id] = card
            Task { await current.update(ActivityContent(state: card, staleDate: Date().addingTimeInterval(3 * 3600))) }
            watch(current, m)
            return
        }
        guard Geo.trackingOn(s), ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let logo = s.brand.logoURL
        let attrs = FlagcastLiveAttributes(event: m.id, code: m.code, team: t.id, title: s.name, accent: Self.hex(s.brand.accent), logo: logo != nil)
        Task {
            if let logo { await Self.saveLogo(logo, m.id) }
            do {
                let a = try Activity.request(attributes: attrs, content: ActivityContent(state: card, staleDate: Date().addingTimeInterval(3 * 3600)), pushType: .token)
                lastKey[a.id] = card
                watch(a, m)
            } catch {}
        }
    }

    /// Send each push token Apple gives the live view to the server, so it can update the card while the app is closed.
    private func watch(_ a: Activity<FlagcastLiveAttributes>, _ m: ScorecardModel) {
        guard !watching.contains(a.id) else { return }
        watching.insert(a.id)
        let id = m.id, code = m.code, team = a.attributes.team
        let player = (m.me == nil || m.me == "-") ? "" : m.me!
        Task {
            for await data in a.pushTokenUpdates {
                let token = data.map { String(format: "%02x", $0) }.joined()
                UserDefaults.standard.set(token, forKey: "golf:\(id):\(code):liveToken")
                _ = try? await API.post(id, "live", ["code": code, "team": team, "token": token, "env": Self.apnsEnv, "player": player])
            }
        }
    }

    private func end(_ a: Activity<FlagcastLiveAttributes>, _ card: LiveCard?, _ m: ScorecardModel?) {
        watching.remove(a.id); lastKey[a.id] = nil
        let at = a.attributes
        Task {
            if let card { await a.end(ActivityContent(state: card, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(4 * 3600))) }
            else { await a.end(nil, dismissalPolicy: .immediate) }
            Self.forgetToken(at)
        }
    }

    func endAll() async {
        for a in Activity<FlagcastLiveAttributes>.activities {
            watching.remove(a.id); lastKey[a.id] = nil
            await a.end(nil, dismissalPolicy: .immediate)
            Self.forgetToken(a.attributes)
        }
    }

    private static func forgetToken(_ at: FlagcastLiveAttributes) {
        let k = "golf:\(at.event):\(at.code):liveToken"
        guard let token = UserDefaults.standard.string(forKey: k) else { return }
        UserDefaults.standard.removeObject(forKey: k)
        Task { _ = try? await API.post(at.event, "live", ["code": at.code, "team": at.team, "token": token, "end": true]) }
    }

    private static var apnsEnv: String {
        #if DEBUG
        "dev"
        #else
        "prod"
        #endif
    }

    // ---- the card, as the server works it out (liveact.js liveCard), with this phone's unsent scores on top ----
    static func card(_ m: ScorecardModel, now: Date = Date()) -> LiveCard? {
        guard let s = m.state, let t = m.team else { return nil }
        let scores = m.myScores(), stab = s.format.type == "stableford"
        let lb = Core.leaderboard(s, scores)
        let gi = Core.groupInfo(s, scores, t.id)
        let mine = lb.filter { $0.teamId == t.id }
        let best = mine.first { $0.played > 0 } ?? mine.first
        let order = m.order(t)
        let played = order.filter { m.holeDone($0) }.count
        let hole = order.first { !m.holeDone($0) } ?? order.last ?? 1
        let hh = hole >= 1 && hole <= s.course.holes.count ? s.course.holes[hole - 1] : nil
        let lead = lb.first { $0.played > 0 }
        let ms = now.timeIntervalSince1970 * 1000
        let me = (m.me == nil || m.me == "-") ? nil : m.me
        let msg = s.nudges.filter { n in
            (n.team == "*" || n.team == t.id) && (n.player == nil || me == nil || n.player == me) && ms - n.at <= 30 * 60000
        }.last
        let raw: Int? = (best?.played ?? 0) > 0 ? best?.score : nil
        let leader: String = lead.map { l in l.teamId == t.id ? "You lead" : "\(l.name) \(Core.fmtPar(l.score, stab))" } ?? ""
        return LiveCard(team: gi?.name ?? t.name, score: raw.map { Core.fmtPar($0, stab) } ?? "—",
                        tone: raw == nil || stab ? 0 : (raw! < 0 ? -1 : raw! > 0 ? 1 : 0),
                        thru: best?.thru ?? "—", pos: (best?.pos.isEmpty ?? true) ? "—" : best!.pos, of: lb.count,
                        hole: hole, par: hh?.par ?? 4, yds: hh?.yds ?? 0, played: played, holes: order.count,
                        leader: leader, msg: msg?.text ?? "", from: msg.map { $0.from ?? "Pro shop" } ?? "", msgAt: msg?.at ?? 0,
                        final: s.locked, at: ms.rounded())
    }

    private static func hex(_ s: String) -> String { s.range(of: #"^#[0-9a-fA-F]{6}$"#, options: .regularExpression) != nil ? s : "" }

    /// the club's logo, made small for the widget (it has very little memory) and left in the app group
    private static func saveLogo(_ url: URL, _ event: String) async {
        guard let file = LiveShared.logoFile(event),
              let (d, r) = try? await URLSession.shared.data(from: url), (r as? HTTPURLResponse)?.statusCode == 200,
              let img = UIImage(data: d) else { return }
        let side: CGFloat = 120, sc = min(side / img.size.width, side / img.size.height, 1)
        let size = CGSize(width: img.size.width * sc, height: img.size.height * sc)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let png = UIGraphicsImageRenderer(size: size, format: fmt).pngData { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        try? png.write(to: file, options: .atomic)
    }
}
