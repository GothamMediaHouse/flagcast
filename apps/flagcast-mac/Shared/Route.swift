/// Where a Flagcast link goes (used by the shared Codes.route in Server.swift).
enum Route: Hashable {
    case score(id: String, code: String)
    case live(id: String)
    case pro(id: String)
}
