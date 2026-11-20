import Foundation
import Observation

/// One tournament in the sidebar: the club's (from its Flagcast account) or one added on this Mac by its desk link.
struct EventRef: Codable, Hashable, Identifiable {
    var id: String, key: String, name: String
    var date: String? = nil, club: String? = nil, added: Double? = nil
    var fromClub: Bool? = nil
}

/// What the desk views need from the app around them: which section shows, and a way to tell the app a
/// tournament's name or date changed (for its sidebar).
@MainActor @Observable
final class DeskNav {
    var section: Section = .setup
    @ObservationIgnored var onRename: ((_ id: String, _ name: String, _ date: String) -> Void)?
}

/// The sections of a tournament, in the sidebar and the Tournament menu (⌘1–⌘9).
enum Section: String, CaseIterable, Identifiable, Hashable {
    case setup, teams, scores, contests, screens, staff, links, report, map, groups
    var id: String { rawValue }
    var title: String {
        switch self {
        case .setup: "Setup"; case .teams: "Teams"; case .scores: "Scores"; case .contests: "Contests"
        case .screens: "Screens and Sponsors"; case .staff: "Staff and Playlists"; case .links: "Links and Cards"; case .report: "Report"
        case .map: "Course Map"; case .groups: "Where the Groups Are"
        }
    }
    var icon: String {
        switch self {
        case .setup: "slider.horizontal.3"; case .teams: "person.3"; case .scores: "tablecells"; case .contests: "trophy"
        case .screens: "tv"; case .staff: "person.badge.key"; case .links: "link"; case .report: "doc.text"
        case .map: "map"; case .groups: "mappin.and.ellipse"
        }
    }
}
