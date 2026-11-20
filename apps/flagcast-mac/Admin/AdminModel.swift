import Foundation
import Observation
import Security
import AppKit

/// Flagcast Admin: every club and tournament, through POST /golf/api/club/admin { pass, op, … } (clubs.js).
/// The passcode (the GOLF_CREATE_PASS secret) is kept in this Mac's Keychain.
struct AdminClub: Decodable, Identifiable, Hashable {
    struct Member: Decodable, Hashable { var email: String, role: String, added: Double, seen: Double
        init(from d: Decoder) throws { let c = try d.container(keyedBy: CodingKeys.self); email = c.str(.email); role = c.str(.role); added = c.dbl(.added, 0); seen = c.dbl(.seen, 0) }
        enum CodingKeys: String, CodingKey { case email, role, added, seen }
    }
    struct Ev: Decodable, Hashable, Identifiable { var id: String, key: String, name: String, created: Double, hidden: Bool, archived: Bool
        init(from d: Decoder) throws { let c = try d.container(keyedBy: CodingKeys.self); id = c.str(.id); key = c.str(.key); name = c.str(.name); created = c.dbl(.created, 0); hidden = c.int(.hidden, 0) != 0; archived = c.int(.archived, 0) != 0 }
        enum CodingKeys: String, CodingKey { case id, key, name, created, hidden, archived }
    }
    struct Payment: Decodable, Hashable, Identifiable { var id: String, amount: Double, credits: Int, what: String, note: String, at: Double
        init(from d: Decoder) throws { let c = try d.container(keyedBy: CodingKeys.self); id = c.str(.id); amount = c.dbl(.amount, 0); credits = c.int(.credits, 0); what = c.str(.what); note = c.str(.note); at = c.dbl(.at, 0) }
        enum CodingKeys: String, CodingKey { case id, amount, credits, what, note, at }
    }
    var id: String, name: String, contact: String, phone: String, city: String, status: String, notes: String, by: String
    var created: Double, credits: Int
    var members: [Member], events: [Ev], payments: [Payment]
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.str(.id); name = c.str(.name); contact = c.str(.contact); phone = c.str(.phone); city = c.str(.city); status = c.str(.status); notes = c.str(.notes); by = c.str(.by)
        created = c.dbl(.created, 0); credits = c.int(.credits, 0); members = c.list(.members); events = c.list(.events); payments = c.list(.payments)
    }
    enum CodingKeys: String, CodingKey { case id, name, contact, phone, city, status, notes, by, created, credits, members, events, payments }
    var creditsText: String { credits < 0 ? "Unlimited" : "\(credits)" }
    var statusText: String { status == "active" ? "Active" : status == "pending" ? "Waiting" : "Off" }
    var paid: Double { payments.reduce(0) { $0 + $1.amount } }
}

/// One tournament on any club's list, with how it's going (op "events").
struct AdminEvent: Decodable, Identifiable, Hashable {
    struct Disp: Decodable, Hashable, Identifiable { var id: String, name: String, online: Int, pages: Int, force: PageRef?
        init(from d: Decoder) throws { let c = try d.container(keyedBy: CodingKeys.self); id = c.str(.id); name = c.str(.name); online = c.int(.online, 0); pages = c.int(.pages, 0); force = try? c.decodeIfPresent(PageRef.self, forKey: .force) }
        enum CodingKeys: String, CodingKey { case id, name, online, pages, force }
    }
    struct Named: Decodable, Hashable, Identifiable { var id: String, name: String
        init(from d: Decoder) throws { let c = try d.container(keyedBy: CodingKeys.self); id = c.str(.id); name = c.str(.name) }
        enum CodingKeys: String, CodingKey { case id, name }
    }
    struct Rep: Decodable, Hashable, Identifiable { var id: String, hole: Int, label: String, at: Double
        init(from d: Decoder) throws { let c = try d.container(keyedBy: CodingKeys.self); id = c.str(.id); hole = c.int(.hole, 0); label = c.str(.label); at = c.dbl(.at, 0) }
        enum CodingKeys: String, CodingKey { case id, hole, label, at }
    }
    var id: String, key: String, name: String, club: String, clubName: String, date: String
    var created: Double, hidden: Bool, archived: Bool, gone: Bool, locked: Bool
    var teams: Int, scored: Int, screens: Int, online: Int, replays: Int
    var displays: [Disp], p3: [Int], sponsors: [Named], replayList: [Rep], scenes: [Named], scene: String, flights: [String]
    var take: Take?, flash: Flash?, phone: PhoneRoute?
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.str(.id); key = c.str(.key); name = c.str(.name); club = c.str(.club); clubName = c.str(.clubName); date = c.str(.date)
        created = c.dbl(.created, 0); hidden = c.int(.hidden, 0) != 0; archived = c.int(.archived, 0) != 0; gone = c.bool(.gone, false); locked = c.bool(.locked, false)
        teams = c.int(.teams, 0); scored = c.int(.scored, 0); screens = c.int(.screens, 0); online = c.int(.online, 0); replays = c.int(.replays, 0)
        displays = c.list(.displays); p3 = (try? c.decodeIfPresent([Int].self, forKey: .p3)) ?? []; sponsors = c.list(.sponsors); replayList = c.list(.replayList)
        scenes = c.list(.scenes); scene = c.str(.scene); flights = (try? c.decodeIfPresent([String].self, forKey: .flights)) ?? []
        take = try? c.decodeIfPresent(Take.self, forKey: .take); flash = try? c.decodeIfPresent(Flash.self, forKey: .flash); phone = try? c.decodeIfPresent(PhoneRoute.self, forKey: .phone)
    }
    enum CodingKeys: String, CodingKey { case id, key, name, club, clubName, date, created, hidden, archived, gone, locked, teams, scored, screens, online, replays, displays, p3, sponsors, replayList, scenes, scene, flights, take, flash, phone }
    var ref: EventRef { EventRef(id: id, key: key, name: name, date: date, club: clubName) }
}

struct LogLine: Decodable, Hashable, Identifiable {
    var n: Int, at: Double, who: String, club: String, what: String
    var id: Int { n }
    init(from d: Decoder) throws { let c = try d.container(keyedBy: CodingKeys.self); n = c.int(.n, 0); at = c.dbl(.at, 0); who = c.str(.who); club = c.str(.club); what = c.str(.what) }
    enum CodingKeys: String, CodingKey { case n, at, who, club, what }
}

enum AdminSection: String, CaseIterable, Identifiable {
    case clubs, tournaments, screens, activity
    var id: String { rawValue }
    var title: String { switch self { case .clubs: "Clubs"; case .tournaments: "Tournaments"; case .screens: "Screens and Phones"; case .activity: "Activity" } }
    var icon: String { switch self { case .clubs: "building.2"; case .tournaments: "flag.2.crossed"; case .screens: "tv.and.mediabox"; case .activity: "list.bullet.rectangle" } }
}

@MainActor @Observable
final class AdminModel {
    var section: AdminSection = .clubs
    var clubs: [AdminClub] = []
    var events: [AdminEvent] = []
    var log: [LogLine] = []
    var mail = true
    var loading = false
    var error: String?
    var notice: String?
    var unlocked = false
    var docs: [String: DeskDoc] = [:]
    /// tournaments opened in the desk (in the sidebar), and the one showing
    var opened: [String] = []
    var openDesk: String?
    var newClub = false
    func open(_ id: String) { if !opened.contains(id) { opened.append(id) }; openDesk = id }

    init() {
        unlocked = Keychain.pass != nil
        #if DEBUG
        // test builds: FLAGCAST_ADMIN_TEST=<passcode> unlocks, loads everything and prints what came back
        if let p = ProcessInfo.processInfo.environment["FLAGCAST_ADMIN_TEST"] {
            Task {
                do {
                    try await unlock(p); await refreshEvents(); await refreshLog()
                    let line = "admintest: \(clubs.count) clubs, \(events.count) tournaments (\(events.reduce(0) { $0 + $1.displays.count }) screens), \(log.count) log lines; first club: \(clubs.first?.name ?? "-") with \(clubs.first?.events.count ?? 0) tournaments\n"
                    FileHandle.standardError.write(line.data(using: .utf8)!)
                } catch { FileHandle.standardError.write("admintest: \(error)\n".data(using: .utf8)!) }
                lock(); NSApp.terminate(nil)
            }
        }
        #endif
    }

    /// POST /golf/api/club/admin with the passcode.
    @discardableResult
    func call(_ op: String?, _ extra: [String: Any] = [:]) async throws -> [String: Any] {
        var b = extra; b["pass"] = Keychain.pass ?? ""
        if let op { b["op"] = op }
        do { return Net.json(try await Net.post("/golf/api/club/admin", b)) }
        catch let e as APIError where e.status == 403 { Keychain.pass = nil; unlocked = false; throw e }
    }
    func unlock(_ pass: String) async throws {
        Keychain.pass = pass
        do { try await refresh(); unlocked = true } catch { Keychain.pass = nil; throw error }
    }
    func lock() { Keychain.pass = nil; unlocked = false; clubs = []; events = [] }

    func refresh() async throws {
        loading = true; defer { loading = false }
        let d = try await Net.post("/golf/api/club/admin", ["pass": Keychain.pass ?? ""])
        struct R: Decodable { var clubs: [Lenient<AdminClub>]; var mail: Bool? }
        let r = try JSONDecoder().decode(R.self, from: d)
        clubs = r.clubs.compactMap(\.value); mail = r.mail ?? true
    }
    func refreshEvents() async {
        do {
            let d = try await Net.post("/golf/api/club/admin", ["pass": Keychain.pass ?? "", "op": "events"])
            struct R: Decodable { var events: [Lenient<AdminEvent>] }
            events = try JSONDecoder().decode(R.self, from: d).events.compactMap(\.value)
        } catch { self.error = error.localizedDescription }
    }
    func refreshLog() async {
        do {
            let d = try await Net.post("/golf/api/club/admin", ["pass": Keychain.pass ?? "", "op": "log"])
            struct R: Decodable { var log: [Lenient<LogLine>] }
            log = try JSONDecoder().decode(R.self, from: d).log.compactMap(\.value)
        } catch { self.error = error.localizedDescription }
    }
    /// A club or tournament change, then the lists again.
    func act(_ op: String, _ extra: [String: Any] = [:], done: String? = nil) async {
        do {
            try await call(op, extra)
            try await refresh()
            if ["lock", "archive", "move", "hide", "unhide", "event", "claim"].contains(op) { await refreshEvents() }
            if let done { flash(done) }
        } catch { flash(error.localizedDescription) }
    }
    /// Screens and phones for one tournament: screen, take, flash or scene (op "day").
    func day(_ event: String, _ d: [String: Any], done: String? = nil) async {
        do { try await call("day", ["id": event, "day": d]); await refreshEvents(); if let done { flash(done) } }
        catch { flash(error.localizedDescription) }
    }
    func flash(_ s: String) { notice = s; Task { try? await Task.sleep(for: .seconds(4)); if notice == s { notice = nil } } }

    func doc(_ e: AdminEvent) -> DeskDoc {
        if let d = docs[e.id] { return d }
        let d = DeskDoc(ref: e.ref); docs[e.id] = d; return d
    }
}

/// The Admin passcode in the login Keychain.
enum Keychain {
    private static let service = Bundle.main.bundleIdentifier ?? "app.flagcast.admin", account = "admin-passcode"   // test builds keep their own
    static var pass: String? {
        get {
            var out: AnyObject?
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true]
            guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
            return String(data: d, encoding: .utf8)
        }
        set {
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
            SecItemDelete(q as CFDictionary)
            if let v = newValue, !v.isEmpty { var a = q; a[kSecValueData as String] = Data(v.utf8); SecItemAdd(a as CFDictionary, nil) }
        }
    }
}
