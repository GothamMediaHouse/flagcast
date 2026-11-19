import Foundation

/// Where the Flagcast server is. Always https://flagcast.app in a release build. A debug build can point at a
/// local copy of the site (`npx wrangler dev`) with the launch argument `-FlagcastServer http://localhost:8787`
/// or the hidden server setting on the home screen (long-press the footer).
enum Server {
    static let production = URL(string: "https://flagcast.app")!
    static let overrideKey = "FlagcastServer"

    static var base: URL {
        #if DEBUG
        if let s = UserDefaults.standard.string(forKey: overrideKey), let u = URL(string: s), u.scheme?.hasPrefix("http") == true { return u }
        #endif
        return production
    }
    static func api(_ id: String, _ op: String) -> URL { base.appendingPathComponent("golf/api/\(id)/\(op)") }
    static func webSocket(_ id: String) -> URL {
        var c = URLComponents(url: api(id, "ws"), resolvingAgainstBaseURL: false)!
        c.scheme = c.scheme == "http" ? "ws" : "wss"
        return c.url!
    }
    /// A page on the website (used for share links).
    static func page(_ path: String) -> URL { base.appendingPathComponent(path) }
}

/// An error the server wrote for golfers ({ error: "…" }), or a plain network problem.
struct APIError: LocalizedError {
    var status: Int
    var message: String
    var errorDescription: String? { message }
    /// No answer at all (no signal, server down): the app keeps what it has and tries again.
    var isOffline: Bool { status == 0 }
}

enum API {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.httpAdditionalHeaders = ["User-Agent": "FlagcastApp-iOS/1.0"]
        return URLSession(configuration: c)
    }()

    static func state(_ id: String) async throws -> EventState {
        let (data, r) = try await call(URLRequest(url: Server.api(id, "state")))
        try check(data, r)
        return try JSONDecoder().decode(EventState.self, from: data)
    }

    /// POST a JSON body to one of the tournament's API ops and return the JSON answer.
    @discardableResult
    static func post(_ id: String, _ op: String, _ body: [String: Any?]) async throws -> [String: Any] {
        var req = URLRequest(url: Server.api(id, op))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body.mapValues { $0 ?? NSNull() })
        let (data, r) = try await call(req)
        try check(data, r)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func call(_ req: URLRequest) async throws -> (Data, URLResponse) {
        do { return try await session.data(for: req) }
        catch { throw APIError(status: 0, message: "No signal. Check your connection and try again.") }
    }

    private static func check(_ data: Data, _ r: URLResponse) throws {
        guard let h = r as? HTTPURLResponse else { return }
        if (200..<300).contains(h.statusCode) { return }
        let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
        throw APIError(status: h.statusCode, message: msg ?? "The server answered \(h.statusCode).")
    }
}

/// Tournament and cart codes, as printed on the cart cards and typed by hand.
enum Codes {
    static func eventId(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        return t.range(of: "^[a-z0-9]{8}$", options: .regularExpression) != nil ? t : nil
    }
    static func cart(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces).uppercased()
        return t.range(of: "^[A-Z0-9]{6}$", options: .regularExpression) != nil ? t : nil
    }

    /// Any Flagcast link or code → where to go: a cart card (https://flagcast.app/g/<id>/s/<CODE>), a tournament
    /// link (/g/<id>), the app's own scheme (flagcast://g/<id>/s/<CODE>) or just the 8-character tournament code.
    static func route(_ text: String) -> Route? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // flagcast://g/abc/s/X puts "g" in the host; read it as a path either way
        let flat = t.replacingOccurrences(of: "flagcast://", with: "/")
        if let m = flat.range(of: "/g/([a-zA-Z0-9]{8})(/s/([a-zA-Z0-9]{6}))?", options: .regularExpression) {
            let parts = flat[m].split(separator: "/").map(String.init)   // ["g", id, "s", code]
            let id = parts[1].lowercased()
            if parts.count >= 4 { return .score(id: id, code: parts[3].uppercased()) }
            return .live(id: id)
        }
        if let id = eventId(t) { return .live(id: id) }
        return nil
    }
}
