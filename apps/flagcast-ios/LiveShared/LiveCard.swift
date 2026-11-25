import Foundation
import ActivityKit

/// The golfer's live view on the lock screen and in the Dynamic Island (a Live Activity). Shared by the app, which
/// starts it, and the FlagcastLive widget extension, which draws it.
struct FlagcastLiveAttributes: ActivityAttributes {
    typealias ContentState = LiveCard
    /// the tournament and the cart (so tapping the card opens this scorecard)
    var event: String
    var code: String
    var team: String
    var title: String
    /// the club's accent colour as #rrggbb ('' for Flagcast green), and whether its logo is saved for the widget
    var accent: String
    var logo: Bool
}

/// What one team's card shows. The server sends the same thing in its Apple pushes (liveact.js liveCard), so the
/// names here must match it; change both together.
struct LiveCard: Codable, Hashable {
    var team: String
    var score: String          // "−3", "E", "+2", "31 pts" or "—"
    var tone: Int              // −1 under par, 0 level, 1 over
    var thru: String           // "6", "F", "—"
    var pos: String            // "T4" or "—"
    var of: Int                // teams (or players) on the board
    var hole: Int
    var par: Int
    var yds: Int
    var played: Int
    var holes: Int             // 18, or 9 on a nine-hole round
    var leader: String         // "Park / Chen −7", "You lead" or ""
    var msg: String            // the latest pro shop message (30 minutes), or ""
    var from: String
    var msgAt: Double
    var final: Bool            // results are final
    var at: Double             // when this was worked out (ms since 1970)

    var updated: Date { Date(timeIntervalSince1970: at / 1000) }
}

/// Where the app leaves the club's logo for the widget (the widget can't load it from the internet itself).
enum LiveShared {
    static let group = "group.app.flagcast.golf"
    static func logoFile(_ event: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("live-logo-\(event).png")
    }
}
