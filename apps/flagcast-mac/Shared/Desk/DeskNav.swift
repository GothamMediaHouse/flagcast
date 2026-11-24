import SwiftUI
import Observation

/// One tournament in the sidebar: the club's (from its Flagcast account) or one added on this Mac by its desk link.
struct EventRef: Codable, Hashable, Identifiable {
    var id: String, key: String, name: String
    var date: String? = nil, club: String? = nil, added: Double? = nil
    var fromClub: Bool? = nil
    /// a desk-link tournament: the email signed in when it was added ('' or nil = added while signed out). It only
    /// shows for that account, so one club never sees another's on a shared computer.
    var owner: String? = nil
}

/// What the desk views need from the app around them: which section shows, and a way to tell the app a
/// tournament's name or date changed (for its sidebar).
@MainActor @Observable
final class DeskNav {
    var section: Section = .overview
    /// the sidebar's find box: shown on the Teams page
    var search = ""
    @ObservationIgnored var onRename: ((_ id: String, _ name: String, _ date: String) -> Void)?
    /// Screens → Engineering is offered (always to Flagcast admins; to others when Settings → Show engineering tools is on)
    @ObservationIgnored var canEngineer: () -> Bool = { false }
}

/// The sections of a tournament, in the sidebar and menus: ⌘1–⌘9, ⌘0 for the course map.
enum Section: String, CaseIterable, Identifiable, Hashable {
    case overview, setup, teams, scores, contests, pins, screens, staff, links, report, map, groups
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: "Overview"; case .setup: "Setup"; case .teams: "Teams"; case .scores: "Scores"; case .contests: "Contests"; case .pins: "Pin sheet"
        case .screens: "Screens & sponsors"; case .staff: "Staff"; case .links: "Links & cart cards"; case .report: "Report"
        case .map: "Course map"; case .groups: "Where the groups are"
        }
    }
    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"; case .setup: "gearshape"; case .teams: "person.2"; case .scores: "list.number"; case .contests: "trophy"; case .pins: "flag"
        case .screens: "tv"; case .staff: "person.crop.circle"; case .links: "link"; case .report: "chart.bar"
        case .map: "map"; case .groups: "mappin.and.ellipse"
        }
    }
    /// ⌘1 … ⌘9 for the first nine, ⌘0 for the course map; Report and "Where the groups are" have none.
    var key: KeyEquivalent? { if self == .map { return "0" }; let i = Section.allCases.firstIndex(of: self)!; return i < 9 ? KeyEquivalent(Character(String(i + 1))) : nil }
    var keyLabel: String { key.map { "⌘\($0.character)" } ?? "" }
}
