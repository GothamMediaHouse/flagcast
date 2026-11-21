import Foundation
import Observation

/// The club account as /golf/api/club/me returns it.
struct ClubMe: Decodable {
    struct Club: Decodable { var id: String, name: String, status: String, credits: Int
        init(from d: Decoder) throws { let c = try d.container(keyedBy: CodingKeys.self); id = c.str(.id); name = c.str(.name); status = c.str(.status); credits = c.int(.credits, 0) }
        enum CodingKeys: String, CodingKey { case id, name, status, credits }
        var canMake: Bool { status == "active" && credits != 0 }
        var stateLine: String {
            status == "pending" ? "Waiting for Flagcast to approve your club. We’ll email you when it’s ready."
            : status == "off" ? "This club is switched off. Contact hello@flagcast.app."
            : credits < 0 ? "Unlimited tournaments." : credits == 0 ? "No tournaments left to make. Contact hello@flagcast.app to add more."
            : "\(credits) tournament\(credits == 1 ? "" : "s") left to make."
        }
    }
    struct Member: Decodable, Hashable { var email: String, role: String }
    struct Ev: Decodable { var id: String, key: String, name: String, created: Double? }
    var email: String, role: String, club: Club?, members: [Member], events: [Ev]
    /// Flagcast staff (an email in the server's ADMIN_EMAIL list): the Admin section shows
    var admin = false
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        email = c.str(.email); role = c.str(.role); club = try? c.decodeIfPresent(Club.self, forKey: .club)
        members = c.list(.members); events = c.list(.events); admin = c.bool(.admin, false)
    }
    enum CodingKeys: String, CodingKey { case email, role, club, members, events, admin }
    var isOwner: Bool { role == "owner" }
}

/// The Manager: who's signed in, the tournaments, and the open one. Kept in the same file the earlier
/// (Electron) Manager used, ~/Library/Application Support/Flagcast Manager/manager.json, so the sign-in carries over.
@MainActor @Observable
final class AppModel {
    private struct Saved: Codable { var base: String?; var token: String?; var events: [EventRef]?; var clubEvents: [EventRef]? }
    private var saved = Saved()
    private let file: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Flagcast Manager")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #if DEBUG
        return dir.appendingPathComponent("manager-debug.json")   // test builds keep their own list
        #else
        return dir.appendingPathComponent("manager.json")
        #endif
    }()

    var me: ClubMe?
    var events: [EventRef] = []
    var selection: String?               // the open tournament's id
    /// which section of the open tournament is showing (shared with the desk views)
    let nav = DeskNav()
    var section: Section { get { nav.section } set { nav.section = newValue } }
    var docs: [String: DeskDoc] = [:]
    var error: String?
    /// ⌘N and “Add by desk link” put the cursor in those boxes on the Home page.
    var focusNew = false
    /// Admin, for Flagcast staff: which admin page shows (nil = a tournament or Home), and tournaments opened from it
    let admin = AdminModel()
    var adminSection: AdminSection?
    var adminRefs: [EventRef] = []
    var isAdmin: Bool { (me?.admin ?? false) || forceAdmin }
    /// test builds' snapshots only
    var forceAdmin = false
    /// the sidebar's tournaments: the club's, then any opened from Admin
    var shownEvents: [EventRef] { events + adminRefs.filter { r in !events.contains { $0.id == r.id } } }
    var focusAdd = false
    var signedIn: Bool { !(saved.token ?? "").isEmpty }

    init() {
        nav.onRename = { [weak self] id, name, date in self?.noteName(id, name: name, date: date) }
        admin.token = { [weak self] in self?.saved.token ?? "" }
        admin.onOpen = { [weak self] e in
            guard let self else { return }
            if !self.shownEvents.contains(where: { $0.id == e.id }) { self.adminRefs.append(EventRef(id: e.id, key: e.key, name: e.name, date: e.date, club: e.clubName)) }
            self.adminSection = nil; self.selection = e.id; self.section = .overview
        }
        if let d = try? Data(contentsOf: file), let s = try? JSONDecoder().decode(Saved.self, from: d) { saved = s }
        listEvents()
    }
    private func write() {
        if let d = try? JSONEncoder().encode(saved) {
            try? d.write(to: file, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)   // desk keys are private
        }
    }
    private func listEvents() {
        let club = (saved.clubEvents ?? []).map { var e = $0; e.fromClub = true; return e }
        let ids = Set(club.map(\.id))
        events = club + (saved.events ?? []).filter { !ids.contains($0.id) }
    }

    func doc(_ id: String) -> DeskDoc? {
        if let d = docs[id] { return d }
        guard let e = shownEvents.first(where: { $0.id == id }) else { return nil }
        let d = DeskDoc(ref: e); docs[id] = d
        return d
    }
    var current: DeskDoc? { selection.flatMap(doc) }

    // ---- the club account ----
    @discardableResult
    func club(_ op: String, _ body: [String: Any] = [:]) async throws -> [String: Any] {
        var b = body; b["token"] = saved.token ?? ""
        do {
            let d = try await Net.post("/golf/api/club/\(op)", b)
            return Net.json(d)
        } catch let e as APIError where e.status == 401 {
            saved.token = nil; saved.clubEvents = []; write(); listEvents(); me = nil
            throw e
        }
    }
    func refresh() async {
        guard signedIn else { me = nil; return }
        do {
            let d = try await Net.post("/golf/api/club/me", ["token": saved.token ?? ""])
            let m = try JSONDecoder().decode(ClubMe.self, from: d)
            me = m
            saved.clubEvents = m.events.map { e in EventRef(id: e.id, key: e.key, name: e.name, date: saved.clubEvents?.first { $0.id == e.id }?.date, added: e.created) }
            write(); listEvents()
            if m.admin { Task { try? await admin.refresh() } }
        } catch let e as APIError where e.status == 401 {
            saved.token = nil; saved.clubEvents = []; write(); listEvents(); me = nil
        } catch { self.error = error.localizedDescription }
    }
    func startSignIn(_ email: String) async throws -> String? {
        let j = try await club("start", ["email": email])
        return j["devCode"] as? String
    }
    func verify(_ email: String, _ code: String) async throws {
        let d = try await Net.post("/golf/api/club/verify", ["email": email, "code": code])
        saved.token = Net.json(d)["token"] as? String
        write()
        await refresh()
    }
    func signOut() async {
        _ = try? await club("signout")
        saved.token = nil; saved.clubEvents = []; me = nil; selection = nil; write(); listEvents()
    }

    // ---- tournaments ----
    func create(_ name: String) async throws {
        let d = try await Net.post("/golf/api/new", ["name": name, "token": saved.token ?? ""])
        let j = Net.json(d)
        guard let id = j["id"] as? String, let key = j["key"] as? String else { throw APIError(status: 500, message: "The tournament wasn’t made. Try again.") }
        saved.clubEvents = [EventRef(id: id, key: key, name: name.isEmpty ? "New tournament" : name, added: Date().timeIntervalSince1970 * 1000)] + (saved.clubEvents ?? [])
        write(); listEvents()
        selection = id; section = .setup
        await refresh()
    }
    /// Add a tournament by its desk link: …/g/abcd2345/desk#longkey
    func add(link: String) async throws {
        guard let m = link.range(of: #"/g/([a-z0-9]{8})/desk#([a-z0-9]{16,40})"#, options: [.regularExpression, .caseInsensitive]) else {
            throw APIError(status: 400, message: "Paste the full desk link. It looks like …/g/abcd2345/desk#longkey")
        }
        let parts = link[m].split(separator: "/").map(String.init)   // ["g", id, "desk#key"]
        let id = parts[1].lowercased(), key = String(parts[2].split(separator: "#").last ?? "")
        let ev = try await Net.deskGet(id, key)
        saved.events = [EventRef(id: id, key: key, name: ev.name.isEmpty ? "Tournament" : ev.name, date: ev.date, added: Date().timeIntervalSince1970 * 1000)]
            + (saved.events ?? []).filter { $0.id != id }
        write(); listEvents()
        selection = id; section = .setup
    }
    func remove(_ id: String) async {
        if (saved.clubEvents ?? []).contains(where: { $0.id == id }), signedIn { _ = try? await club("hide", ["id": id]) }
        saved.clubEvents = (saved.clubEvents ?? []).filter { $0.id != id }
        saved.events = (saved.events ?? []).filter { $0.id != id }
        docs[id] = nil; if selection == id { selection = nil }
        write(); listEvents()
    }
    /// Keep the sidebar's name and date in step with the desk.
    func noteName(_ id: String, name: String, date: String) {
        guard let i = events.firstIndex(where: { $0.id == id }), events[i].name != name || events[i].date != date else { return }
        events[i].name = name; events[i].date = date
        if let j = saved.events?.firstIndex(where: { $0.id == id }) { saved.events?[j].name = name; saved.events?[j].date = date }
        if let j = saved.clubEvents?.firstIndex(where: { $0.id == id }) { saved.clubEvents?[j].name = name; saved.clubEvents?[j].date = date }
        write()
    }
}

