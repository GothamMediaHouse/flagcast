import Foundation

// What the server sends a Flagcast TV (tv.js / tvfeed.js on flagcast.app). Every field is optional-tolerant so an older
// app keeps working when the server adds pages.

struct Hello: Decodable { var code: String; var pair: String; var exp: Double }
struct Wait: Decodable { var waiting: Bool?; var expired: Bool?; var tv: String?; var token: String? }

struct Now: Decodable {
    struct TV: Decodable { var id: String; var name: String }
    struct Club: Decodable { var name: String; var logo: String; var accent: String; var flagcast: Bool }
    struct Event: Decodable { var id: String; var name: String; var date: String }
    var tv: TV
    var club: Club
    var event: Event?
    var next: Event?
    var check: Double?
    var feed: Feed?
}

struct Sponsor: Decodable, Hashable { var name: String; var line: String?; var logo: String }

struct Row: Decodable, Hashable { var pos: String; var name: String; var sub: String; var score: String; var under: Bool; var thru: String }

struct Page: Decodable, Identifiable {
    var k: String
    var secs: Double?
    // lb
    var title: String?; var sub: String?; var page: Int?; var pages: Int?; var rows: [Row]?; var points: Bool?
    // cam
    var hole: Int?; var par: Int?; var yards: Int?; var url: String?
    // sponsor(s), phone, empty
    var sponsor: Sponsor?; var name: String?; var line: String?; var logo: String?; var list: [Sponsor]?; var text: String?
    /// a stable id so a page that's still on screen isn't rebuilt when new scores come in
    var id: String { "\(k)|\(sub ?? "")|\(page ?? 0)|\(hole ?? 0)|\(name ?? "")" }
}

struct Take: Decodable { var kind: String; var text: String; var until: Double }

struct Feed: Decodable {
    var title: String
    var ticker: String
    var flash: String
    var logo: String
    var accent: String
    var flagcast: Bool
    var locked: Bool
    var take: Take?
    var pages: [Page]
}

enum ServerError: LocalizedError {
    case answer(Int, String)
    var errorDescription: String? { if case let .answer(_, m) = self { return m }; return nil }
    var status: Int { if case let .answer(s, _) = self { return s }; return 0 }
}

enum Server {
    /// -FlagcastServer http://localhost:8787 in the scheme's arguments points it at a local `wrangler dev`
    static let base = URL(string: UserDefaults.standard.string(forKey: "FlagcastServer") ?? "https://flagcast.app")!

    static func post<T: Decodable>(_ op: String, _ body: [String: Any]) async throws -> T {
        var r = URLRequest(url: base.appendingPathComponent("golf/api/tv/\(op)"))
        r.httpMethod = "POST"; r.timeoutInterval = 20
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: r)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(status) {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw ServerError.answer(status, msg ?? "Flagcast answered \(status).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    static func url(_ s: String) -> URL? { s.isEmpty ? nil : URL(string: s, relativeTo: base)?.absoluteURL }
}
