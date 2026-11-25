import SwiftUI

// What the TVs can show and how they're switched: shared by the Mac and the iPhone and iPad Manager
// (the simple TV cards, Show something else, and Engineering).

let PAGE_NAMES: [(String, String)] = [("lb", "Leaderboard"), ("matches", "Matches (match play)"), ("indiv", "Individuals"), ("p3", "Par 3 camera"), ("cam", "One hole’s camera"), ("contests", "Contests"), ("skins", "Skins"),
                                      ("fund", "Fundraising"), ("sponsors", "All sponsors"), ("sponsor", "One sponsor"), ("schedule", "Schedule")]

/// What a screen can be sent to for one tournament.
struct PageChoices {
    var flights: [String] = []
    var p3: [Int] = []
    var holes: [Int] = Array(1...18)
    var sponsors: [(id: String, name: String)] = []

    func label(_ p: PageRef) -> String {
        let n = PAGE_NAMES.first { $0.0 == p.k }?.1 ?? p.k
        switch p.k {
        case "lb", "indiv": return p.fl.isEmpty ? n : "\(n) · Flight \(p.fl)"
        case "p3": return p.hole > 0 ? "Par 3 camera · Hole \(p.hole)" : "Par 3 cameras, each in turn"
        case "cam": return p.hole > 0 ? "Camera · Hole \(p.hole)" : "Cameras, each in turn"
        case "sponsor": return sponsors.first { $0.id == p.sponsor }.map { "Sponsor · \($0.name)" } ?? "One sponsor"
        default: return n
        }
    }
    static func icon(_ k: String) -> String {
        switch k {
        case "lb", "indiv": "list.number"; case "matches": "person.2"; case "p3", "cam": "video"; case "contests": "flag.2.crossed"; case "skins": "dollarsign.circle"
        case "fund": "heart"; case "sponsors", "sponsor": "star"; case "schedule": "clock"; default: "rectangle"
        }
    }
}

/// How long "Show something else" keeps the page on before the TV goes back to normal.
enum SendLength: Int, CaseIterable, Identifiable {
    case five = 5, fifteen = 15, changed = 0
    var id: Int { rawValue }
    var title: String { switch self { case .five: "For 5 minutes"; case .fifteen: "For 15 minutes"; case .changed: "Until I switch back" } }
}

/// "Showing the Leaderboard until 3:42 PM" or "Showing its normal mix".
func screenStatus(_ force: PageRef?, playlist: [PageRef], choices: PageChoices) -> String {
    if let f = force, f.isOn {
        let page = choices.label(f)
        return f.until > 0 ? "Showing \(page) until \(Date(timeIntervalSince1970: f.until / 1000).formatted(date: .omitted, time: .shortened)), then back to normal"
                           : "Showing \(page) until you switch back"
    }
    return "Showing its normal: \(ShowTile.matching(playlist)?.title ?? "your own mix")"
}

// MARK: - what a TV shows normally

/// The big choice on each TV: a ready-made show with sensible timings.
enum ShowTile: String, CaseIterable, Identifiable {
    case mix, leaderboard, camera, sponsors, contests
    var id: String { rawValue }
    var title: String { switch self { case .mix: "Mix"; case .leaderboard: "Leaderboard"; case .camera: "Par 3 camera"; case .sponsors: "Sponsors"; case .contests: "Contests" } }
    var note: String { switch self { case .mix: "Recommended"; case .leaderboard: "Scores only"; case .camera: "The live hole"; case .sponsors: "Logos, in turn"; case .contests: "Closest & longest" } }
    var icon: String { switch self { case .mix: "sparkles.tv"; case .leaderboard: "list.number"; case .camera: "video"; case .sponsors: "star"; case .contests: "flag.2.crossed" } }
    var pages: [PageRef] {
        switch self {
        case .mix: [PageRef(k: "lb", secs: 15), PageRef(k: "p3", secs: 20), PageRef(k: "sponsors", secs: 8)]
        case .leaderboard: [PageRef(k: "lb", secs: 20)]
        case .camera: [PageRef(k: "p3", secs: 30)]
        case .sponsors: [PageRef(k: "sponsors", secs: 10)]
        case .contests: [PageRef(k: "contests", secs: 15)]
        }
    }
    /// the tile a list came from (pages and order; timings may have been changed)
    static func matching(_ list: [PageRef]) -> ShowTile? {
        allCases.first { t in t.pages.count == list.count && zip(t.pages, list).allSatisfy { $0.k == $1.k && $1.fl.isEmpty && $1.hole == 0 && $1.sponsor.isEmpty } }
    }
}

/// One TV as Engineering sees it.
struct EngTV: Identifiable, Hashable {
    var id: String, name: String, place: String, group: String, online: Int, force: PageRef?, playlist: [PageRef]
}

/// What Engineering reads and how it changes things, for the desk (one tournament) or Admin (any club's).
struct EngSource {
    var tvs: [EngTV]
    var choices: PageChoices
    var url: (String) -> URL?
    var scenes: [(id: String, name: String)]
    var currentScene = ""
    var take: Take?
    var phone: PhoneRoute?
    var announcement: Flash?
    var replays: [(id: String, label: String)] = []
    /// a day change (op "screen", "scene", "take", "flash"), with the line to show when it's done
    var day: (_ op: String, _ body: [String: Any], _ done: String?) async -> Void
    /// the desk can edit each TV's pages and group in place (saved with Save); Admin can't
    var playlist: ((String) -> Binding<[PageRef]>?)? = nil
    var group: ((String) -> Binding<String>?)? = nil
}

/// The routing matrix's columns: "Normal" (its own pages) and each page a TV can be switched to.
struct EngRoute: Identifiable, Hashable {
    var id: String, title: String, page: PageRef?
    func matches(_ f: PageRef?) -> Bool {
        guard let f, f.isOn else { return page == nil }
        guard let page else { return false }
        return f.k == page.k && f.fl == page.fl && f.hole == page.hole && f.sponsor == page.sponsor
    }
}

func pageDict(_ p: PageRef?) -> Any { p.map { ["k": $0.k, "fl": $0.fl, "hole": $0.hole, "sponsor": $0.sponsor] as [String: Any] } ?? NSNull() }


extension DeskDoc {
    var pageChoices: PageChoices {
        PageChoices(flights: ev.flights, p3: ev.course.holes.filter { $0.par == 3 }.map(\.n), holes: ev.course.holes.map(\.n),
                    sponsors: ev.sponsors.map { ($0.id, $0.name.isEmpty ? "Sponsor" : $0.name) })
    }
    /// Screens → Engineering for this tournament
    var engSource: EngSource {
        let lv = live
        return EngSource(
            tvs: ev.displays.map { d in EngTV(id: d.id, name: d.name, place: d.place, group: d.group, online: lv?.online[d.id] ?? 0, force: lv?.live.force[d.id], playlist: d.playlist) },
            choices: pageChoices,
            url: { [boardURL] id in URL(string: "\(boardURL.absoluteString)?screen=\(id)") },
            scenes: ev.scenes.map { ($0.id, $0.name) },
            take: lv?.live.take, phone: lv?.live.phone, announcement: lv?.flash,
            replays: (lv?.replays ?? ev.replays).map { ($0.id, "Hole \($0.hole) · \($0.label.isEmpty ? "Replay" : $0.label)") },
            day: { [weak self] op, body, done in
                guard let self else { return }
                await self.day(op, body, done: done)
                if op == "scene" { await self.refreshDay() }
            },
            playlist: { [weak self] id in
                guard let self, self.ev.displays.contains(where: { $0.id == id }) else { return nil }
                return Binding(get: { self.ev.displays.first { $0.id == id }?.playlist ?? [] },
                               set: { v in if let i = self.ev.displays.firstIndex(where: { $0.id == id }) { self.ev.displays[i].playlist = v } })
            },
            group: { [weak self] id in
                guard let self, self.ev.displays.contains(where: { $0.id == id }) else { return nil }
                return Binding(get: { self.ev.displays.first { $0.id == id }?.group ?? "" },
                               set: { v in if let i = self.ev.displays.firstIndex(where: { $0.id == id }) { self.ev.displays[i].group = v } })
            })
    }
}
