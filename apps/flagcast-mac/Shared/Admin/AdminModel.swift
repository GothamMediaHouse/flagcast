import Foundation
import SwiftUI
import Security
import Observation


struct AdminClub: Decodable, Identifiable, Hashable {
    struct Member: Decodable, Hashable { var email: String, role: String, added: Double, seen: Double
        init(from d: Decoder) throws { let c = try d.container(keyedBy: CodingKeys.self); email = c.str(.email); role = c.str(.role); added = c.dbl(.added, 0); seen = c.dbl(.seen, 0) }
        enum CodingKeys: String, CodingKey { case email, role, added, seen }
    }
    struct Ev: Decodable, Hashable, Identifiable { var id: String, key: String, name: String, created: Double, hidden: Bool, archived: Bool, demo: Bool
        init(from d: Decoder) throws { let c = try d.container(keyedBy: CodingKeys.self); id = c.str(.id); key = c.str(.key); name = c.str(.name); created = c.dbl(.created, 0); hidden = c.int(.hidden, 0) != 0; archived = c.int(.archived, 0) != 0; demo = c.int(.demo, 0) != 0 }
        enum CodingKeys: String, CodingKey { case id, key, name, created, hidden, archived, demo }
    }
    struct Payment: Decodable, Hashable, Identifiable { var id: String, amount: Double, credits: Int, what: String, note: String, at: Double
        init(from d: Decoder) throws { let c = try d.container(keyedBy: CodingKeys.self); id = c.str(.id); amount = c.dbl(.amount, 0); credits = c.int(.credits, 0); what = c.str(.what); note = c.str(.note); at = c.dbl(.at, 0) }
        enum CodingKeys: String, CodingKey { case id, amount, credits, what, note, at }
    }
    var id: String, name: String, contact: String, phone: String, city: String, status: String, notes: String, by: String
    var created: Double, credits: Int
    var logo: String, accent: String, powered: Bool   // branding: logo is its address on the server ('' = none, Flagcast's shows)
    var members: [Member], events: [Ev], payments: [Payment]
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.str(.id); name = c.str(.name); contact = c.str(.contact); phone = c.str(.phone); city = c.str(.city); status = c.str(.status); notes = c.str(.notes); by = c.str(.by)
        created = c.dbl(.created, 0); credits = c.int(.credits, 0); members = c.list(.members); events = c.list(.events); payments = c.list(.payments)
        logo = c.str(.logo); accent = c.str(.accent); powered = c.bool(.powered, false)
    }
    enum CodingKeys: String, CodingKey { case id, name, contact, phone, city, status, notes, by, created, credits, members, events, payments, logo, accent, powered }
    var creditsText: String { credits < 0 ? "Unlimited" : "\(credits)" }
    var statusText: String { status == "active" ? "Active" : status == "pending" ? "Waiting" : "Off" }
    var paid: Double { payments.reduce(0) { $0 + $1.amount } }
    /// the Demo club: one with a tournament Admin marked Demo, or "Demo" as its town
    var isDemo: Bool { events.contains { $0.demo } || city.caseInsensitiveCompare("Demo") == .orderedSame }
    /// tournaments still showing (deleted ones are only archived)
    var liveEvents: Int { events.filter { !$0.archived }.count }
}

/// A heading's worth of Admin's Clubs list.
struct ClubSection: Identifiable { var id: String; var title: String; var clubs: [AdminClub] }

extension Array where Element == AdminClub {
    /// Admin's Clubs list in sections, A to Z in each: waiting to join, active, switched off, then the Demo on its own
    var clubSections: [ClubSection] {
        let byName = sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let real = byName.filter { !$0.isDemo }
        return [ClubSection(id: "pending", title: "Waiting to join", clubs: real.filter { $0.status == "pending" }),
                ClubSection(id: "active", title: "Active", clubs: real.filter { $0.status == "active" }),
                ClubSection(id: "off", title: "Switched off", clubs: real.filter { !["pending", "active"].contains($0.status) }),
                ClubSection(id: "demo", title: "Demo", clubs: byName.filter { $0.isDemo })].filter { !$0.clubs.isEmpty }
    }
}

/// A club in Recently deleted (clubs.js admin op 'delete'): kept 30 days with its tournaments locked, then wiped.
struct DeletedClub: Decodable, Identifiable, Hashable {
    var id: String, name: String, city: String, deleted: Double, wipes: Double, events: Int
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.str(.id); name = c.str(.name); city = c.str(.city); deleted = c.dbl(.deleted, 0); wipes = c.dbl(.wipes, 0); events = c.int(.events, 0)
    }
    enum CodingKeys: String, CodingKey { case id, name, city, deleted, wipes, events }
}

/// One tournament on any club's list, with how it's going (op "events").
struct AdminEvent: Decodable, Identifiable, Hashable {
    struct Disp: Decodable, Hashable, Identifiable { var id: String, name: String, place: String, group: String, online: Int, pages: Int, force: PageRef?, list: [PageRef]
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self); id = c.str(.id); name = c.str(.name); place = c.str(.place); group = c.str(.group)
            online = c.int(.online, 0); pages = c.int(.pages, 0); force = try? c.decodeIfPresent(PageRef.self, forKey: .force); list = c.list(.list)
        }
        enum CodingKeys: String, CodingKey { case id, name, place = "where", group, online, pages, force, list }
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
    var lastScore = 0.0, scoringNow = 0   // when a cart last scored (ms), and how many carts scored in the last 20 minutes
    var demo = false   // Admin marked it Demo: it shows the Flagcast logo whatever its club has
    var logo = ""   // the logo the tournament shows (its own from Setup, else its club's; '' when it shows Flagcast's)
    var teams: Int, scored: Int, screens: Int, online: Int, replays: Int
    var displays: [Disp], p3: [Int], sponsors: [Named], replayList: [Rep], scenes: [Named], scene: String, flights: [String]
    var take: Take?, flash: Flash?, phone: PhoneRoute?
    /// camera links by hole, 0 for the clubhouse (set by Flagcast Admin only)
    var cams: [Int: String]
    /// where Admin offers a camera link: the clubhouse (0), par 3s, contest holes, the 18th green, and holes that have one
    var camHoles: [Int] = []
    /// contest holes → "Closest to the pin" / "Long drive"
    var contestHoles: [Int: String] = [:]
    /// "Clubhouse", "Hole 7 · Closest to the pin", "Hole 18 · 18th green"
    func camName(_ h: Int) -> String {
        h == 0 ? "Clubhouse" : (["Hole \(h)", contestHoles[h] ?? (h == 18 && !p3.contains(18) ? "18th green" : "")].filter { !$0.isEmpty }.joined(separator: " · "))
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.str(.id); key = c.str(.key); name = c.str(.name); club = c.str(.club); clubName = c.str(.clubName); date = c.str(.date)
        created = c.dbl(.created, 0); hidden = c.int(.hidden, 0) != 0; archived = c.int(.archived, 0) != 0; gone = c.bool(.gone, false); locked = c.bool(.locked, false); demo = c.bool(.demo, false)
        lastScore = c.dbl(.lastScore, 0); scoringNow = c.int(.scoringNow, 0)
        struct Brand: Decodable { var logo: String? }
        logo = ((try? c.decodeIfPresent(Brand.self, forKey: .brand)) ?? nil)?.logo ?? ""
        teams = c.int(.teams, 0); scored = c.int(.scored, 0); screens = c.int(.screens, 0); online = c.int(.online, 0); replays = c.int(.replays, 0)
        displays = c.list(.displays); p3 = (try? c.decodeIfPresent([Int].self, forKey: .p3)) ?? [];
        camHoles = (try? c.decodeIfPresent([Int].self, forKey: .camHoles)) ?? p3
        contestHoles = Dictionary(uniqueKeysWithValues: ((try? c.decodeIfPresent([String: String].self, forKey: .contestHoles)) ?? [:]).compactMap { k, v in Int(k).map { ($0, v) } }); sponsors = c.list(.sponsors); replayList = c.list(.replayList)
        scenes = c.list(.scenes); scene = c.str(.scene); flights = (try? c.decodeIfPresent([String].self, forKey: .flights)) ?? []
        take = try? c.decodeIfPresent(Take.self, forKey: .take); flash = try? c.decodeIfPresent(Flash.self, forKey: .flash); phone = try? c.decodeIfPresent(PhoneRoute.self, forKey: .phone)
        let raw = (try? c.decodeIfPresent([String: String].self, forKey: .cams)) ?? [:]
        cams = Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in Int(k).map { ($0, v) } })
    }
    enum CodingKeys: String, CodingKey { case id, key, name, club, clubName, date, created, hidden, archived, gone, locked, demo, brand, lastScore, scoringNow, teams, scored, screens, online, replays, displays, p3, sponsors, replayList, scenes, scene, flights, take, flash, phone, cams, camHoles, contestHoles }
    var isToday: Bool { date == ISO8601DateFormatter.day.string(from: Date()) }
    var ref: EventRef { EventRef(id: id, key: key, name: name, date: date, club: clubName) }
}

struct LogLine: Decodable, Hashable, Identifiable {
    var n: Int, at: Double, who: String, club: String, what: String
    var id: Int { n }
    init(from d: Decoder) throws { let c = try d.container(keyedBy: CodingKeys.self); n = c.int(.n, 0); at = c.dbl(.at, 0); who = c.str(.who); club = c.str(.club); what = c.str(.what) }
    enum CodingKeys: String, CodingKey { case n, at, who, club, what }
}

/// Someone with Flagcast Admin: fixed when it comes from the server's ADMIN_EMAIL (changed in Cloudflare), else added in Staff
struct StaffMember: Decodable, Hashable, Identifiable {
    var email: String, fixed: Bool, added: Double, by: String, seen: Double
    var id: String { email }
    init(from d: Decoder) throws { let c = try d.container(keyedBy: CodingKeys.self); email = c.str(.email); fixed = (try? c.decode(Bool.self, forKey: .fixed)) ?? false; added = c.dbl(.added, 0); by = c.str(.by); seen = c.dbl(.seen, 0) }
    enum CodingKeys: String, CodingKey { case email, fixed, added, by, seen }
}

/// Someone who Can go live (Admin → Staff): they stream from their iPhone to a hole, and nothing else. where: any (every
/// tournament), club (that club's) or event (one tournament, done when it's over). Admins can always go live.
struct GoLivePerson: Decodable, Hashable, Identifiable {
    var email: String, name: String, added: Double, by: String, seen: Double
    var where_: String, club: String, clubName: String, event: String, eventName: String
    var id: String { email }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        email = c.str(.email); name = c.str(.name); added = c.dbl(.added, 0); by = c.str(.by); seen = c.dbl(.seen, 0)
        where_ = c.str(.where_, "any"); club = c.str(.club); clubName = c.str(.clubName); event = c.str(.event); eventName = c.str(.eventName)
    }
    enum CodingKeys: String, CodingKey { case email, name, added, by, seen, club, clubName, event, eventName; case where_ = "where" }
    /// where, in words
    var whereText: String {
        switch where_ {
        case "club": "\(clubName) (all its tournaments)"
        case "event": clubName.isEmpty ? eventName : "\(eventName) · \(clubName)"
        default: "Any tournament"
        }
    }
}

/// One row on the Staff screen: an admin, a camera person, or both
struct StaffPerson: Identifiable, Hashable {
    var email: String, admin: StaffMember?, live: GoLivePerson?
    var id: String { email }
    var seen: Double { max(admin?.seen ?? 0, live?.seen ?? 0) }
    var fixed: Bool { admin?.fixed ?? false }
    var whereText: String { admin != nil ? "Everywhere" : live?.whereText ?? "" }
    var detail: String {
        let s = seen > 0 ? Date(timeIntervalSince1970: seen / 1000).formatted(date: .abbreviated, time: .shortened) : "never"
        if fixed { return "Set in Cloudflare (ADMIN_EMAIL) · last signed in \(s)" }
        let added = admin.map { ($0.added, $0.by) } ?? live.map { ($0.added, $0.by) } ?? (0, "")
        return "Added \(Date(timeIntervalSince1970: added.0 / 1000).formatted(date: .abbreviated, time: .omitted))\(added.1.isEmpty ? "" : " by \(added.1)") · last signed in \(s)"
    }
}

enum AdminSection: String, CaseIterable, Identifiable {
    case overview, today, signups, clubs, tournaments, cameras, screens, staff, activity
    var id: String { rawValue }
    var title: String {
        switch self { case .overview: "Overview"; case .today: "Event day"; case .signups: "Sign-ups"; case .clubs: "Clubs"; case .tournaments: "Tournaments"; case .cameras: "Cameras"; case .screens: "Screens & phones"; case .staff: "Staff"; case .activity: "Activity" }
    }
    var icon: String {
        switch self { case .overview: "square.grid.2x2"; case .today: "sun.max"; case .signups: "person.badge.plus"; case .clubs: "building.2"; case .tournaments: "flag.2.crossed"; case .cameras: "video"; case .screens: "tv.and.mediabox"; case .staff: "checkmark.shield"; case .activity: "list.bullet.rectangle" }
    }
}

/// Flagcast Admin inside the Manager: every club and tournament, through POST /golf/api/club/admin { token, op, … }
/// with the Manager's own sign-in (the server lets in staff: its ADMIN_EMAIL list plus the ones added in Staff). Clubs never see it.
@MainActor @Observable
final class AdminModel {
    var section: AdminSection = .clubs
    var clubs: [AdminClub] = []
    var deleted: [DeletedClub] = []
    var events: [AdminEvent] = []
    var log: [LogLine] = []
    var staff: [StaffMember] = []
    /// Can go live (not Admin): see GoLivePerson
    var golive: [GoLivePerson] = []
    var mail = true
    var loading = false
    var error: String?
    var notice: String?
    var newClub = false
    /// the Manager's sign-in token
    @ObservationIgnored var token: () -> String = { "" }
    /// whether the saved passcode may be used now (the Manager says no while a club's own account is signed in)
    @ObservationIgnored var passAllowed: () -> Bool = { true }
    /// The Flagcast Admin passcode (the server's GOLF_CREATE_PASS), kept in the login Keychain. With it, Admin works
    /// without signing in by email.
    var pass: String? = Keychain.pass
    /// open a tournament in the Manager's desk
    @ObservationIgnored var onOpen: ((AdminEvent) -> Void)?

    private func body(_ extra: [String: Any]) -> [String: Any] {
        var b = extra; b["token"] = token()
        if let pass, !pass.isEmpty, passAllowed() { b["pass"] = pass }
        return b
    }
    /// Try a passcode: kept in the Keychain if the server takes it.
    func unlock(_ p: String) async throws {
        guard passAllowed() else { throw APIError(status: 403, message: "Sign out of the club’s account first. The passcode only works for Flagcast staff.") }
        let old = pass
        pass = p.trimmingCharacters(in: .whitespacesAndNewlines)
        do { try await refresh(); Keychain.pass = pass; await refreshEvents() }
        catch { pass = old; throw error }
    }
    func forget() { pass = nil; Keychain.pass = nil; clear() }
    /// drop every club's data from memory (sign-out, or another account signing in)
    func clear() { clubs = []; events = []; log = []; staff = []; golive = []; error = nil; notice = nil }

    @discardableResult
    func call(_ op: String?, _ extra: [String: Any] = [:]) async throws -> [String: Any] {
        var b = body(extra); if let op { b["op"] = op }
        return Net.json(try await Net.post("/golf/api/club/admin", b))
    }
    func refresh() async throws {
        loading = true; defer { loading = false }
        let d = try await Net.post("/golf/api/club/admin", body([:]))
        struct R: Decodable { var clubs: [Lenient<AdminClub>]; var mail: Bool?; var staff: [Lenient<StaffMember>]?; var golive: [Lenient<GoLivePerson>]?; var deleted: [Lenient<DeletedClub>]? }
        let r = try JSONDecoder().decode(R.self, from: d)
        clubs = r.clubs.compactMap(\.value); mail = r.mail ?? true; staff = (r.staff ?? []).compactMap(\.value); deleted = (r.deleted ?? []).compactMap(\.value)
        golive = (r.golive ?? []).compactMap(\.value)
    }
    func refreshEvents() async {
        do {
            let d = try await Net.post("/golf/api/club/admin", body(["op": "events"]))
            struct R: Decodable { var events: [Lenient<AdminEvent>] }
            events = try JSONDecoder().decode(R.self, from: d).events.compactMap(\.value)
        } catch { self.error = error.localizedDescription }
    }
    func refreshLog() async {
        do {
            let d = try await Net.post("/golf/api/club/admin", body(["op": "log"]))
            struct R: Decodable { var log: [Lenient<LogLine>] }
            log = try JSONDecoder().decode(R.self, from: d).log.compactMap(\.value)
        } catch { self.error = error.localizedDescription }
    }
    /// A club or tournament change, then the lists again.
    func act(_ op: String, _ extra: [String: Any] = [:], done: String? = nil) async {
        do {
            let j = try await call(op, extra)
            try await refresh()
            if ["lock", "archive", "move", "hide", "unhide", "event", "claim", "demo", "delete", "restore", "purge"].contains(op) { await refreshEvents() }
            // Add club with a course: what was filled in (scorecard, tees, how many holes mapped)
            if let note = j["courseNote"] as? String, !note.isEmpty { flash(note, seconds: 10) } else if let done { flash(done) }
        } catch { flash(error.localizedDescription) }
    }
    /// Admins and camera people, one row each
    var people: [StaffPerson] {
        var out = staff.map { StaffPerson(email: $0.email, admin: $0, live: golive.first { g in g.email == $0.email }) }
        for g in golive where !out.contains(where: { $0.email == g.email }) { out.append(StaffPerson(email: g.email, admin: nil, live: g)) }
        return out
    }
    /// Save someone from the Add / Edit person sheet: Admin on or off, Can go live on or off and where. True when it worked.
    func savePerson(_ email: String, admin wantAdmin: Bool, live wantLive: Bool, where w: String, club: String, event: String, name: String, mail: Bool) async -> Bool {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let was = people.first { $0.email == e }
        do {
            if wantAdmin && was?.admin == nil { try await call("staff-add", ["email": e]) }
            if !wantAdmin, was?.admin != nil { try await call("staff-remove", ["email": e]) }
            if wantLive && !wantAdmin {
                var b: [String: Any] = ["email": e, "where": w, "name": name, "mail": mail]
                if w == "club" { b["club"] = club }; if w == "event" { b["event"] = event }
                try await call("golive-set", b)
            } else if was?.live != nil { try await call("golive-remove", ["email": e]) }
            try await refresh()
            flash(!wantAdmin && !wantLive ? "Removed." : wantLive && !wantAdmin && mail ? "Saved. They’ve been emailed how to go live." : "Saved.")
            return true
        } catch { try? await refresh(); flash(error.localizedDescription); return false }
    }
    /// the tournaments Can go live can be given for: every club's that aren't deleted or archived
    var liveEventChoices: [(id: String, name: String)] {
        clubs.flatMap { c in c.events.filter { !$0.hidden && !$0.archived }.map { (id: $0.id, name: "\($0.name) · \(c.name)") } }
    }

    /// Delete a club. One with tournaments (a test club) goes with them, and only with its name typed (the server checks too). True when it's gone.
    func deleteClub(_ club: AdminClub, typed: String = "") async -> Bool {
        await act("delete", ["club": club.id, "confirm": typed], done: "Deleted. It’s in Recently deleted for 30 days.")
        return !clubs.contains { $0.id == club.id }
    }
    /// The typed name matches the club's (case, spaces and curly quotes don't matter).
    static func nameMatches(_ typed: String, _ name: String) -> Bool {
        let f = { (x: String) in x.lowercased().replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "‘", with: "'").split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        return !f(typed).isEmpty && f(typed) == f(name)
    }
    /// What deleting a club does, for the confirm.
    static func deleteMessage(_ club: AdminClub) -> String {
        let n = club.events.count
        return n == 0 ? "For a mistaken or spam sign-up. Its people lose access to it. It waits 30 days in Recently deleted, where you can restore it."
            : "Its people lose access and its \(n == 1 ? "tournament is" : "\(n) tournaments are") locked. After 30 days in Recently deleted every score, team and photo is wiped and the links stop working. Type \(club.name) to confirm."
    }
    func restoreClub(_ c: DeletedClub) async { await act("restore", ["club": c.id], done: "Restored. Its tournaments stay locked until a desk unlocks them.") }
    /// Wipe a deleted club now (its name typed again).
    func purgeClub(_ c: DeletedClub, typed: String) async { await act("purge", ["club": c.id, "confirm": typed], done: "Wiped for good.") }
    /// A club's branding (logo, accent, powered): nil when saved, else what went wrong (for the branding editor).
    func brand(_ club: String, _ changes: [String: Any]) async -> String? {
        do { var b = changes; b["club"] = club; try await call("brand", b); try await refresh(); return nil }
        catch { return error.localizedDescription }
    }
    /// Screens and phones for one tournament: screen, take, flash or scene (op "day").
    func day(_ event: String, _ d: [String: Any], done: String? = nil) async {
        do { try await call("day", ["id": event, "day": d]); await refreshEvents(); if let done { flash(done) } }
        catch { flash(error.localizedDescription) }
    }
    /// Change a tournament's TVs (name, where, what they show normally, remove) from Admin, with its desk key.
    func editTVs(_ e: AdminEvent, done: String, _ change: @escaping (inout [Display]) -> Void) async {
        do {
            var ev = try await Net.deskGet(e.id, e.key)
            change(&ev.displays)
            _ = try await Net.deskSave(e.id, e.key, ev)
            await refreshEvents(); flash(done)
        } catch { flash(error.localizedDescription) }
    }
    /// Set a tournament's par 3 camera links (Flagcast only; clubs can't).
    func saveCams(_ id: String, _ cams: [Int: String]) async -> Bool {
        do {
            try await call("cams", ["id": id, "cams": Dictionary(uniqueKeysWithValues: cams.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }.map { ("\($0.key)", $0.value.trimmingCharacters(in: .whitespaces)) })])
            await refreshEvents(); flash("Cameras saved. TVs and phones have them now.")
            return true
        } catch { flash(error.localizedDescription); return false }
    }
    /// An NDI camera's Cloudflare Stream input for one hole: the RTMPS address to push to (with its key), or nil when
    /// Stream isn't set up on the server. The server also points the hole's camera link at the Stream playback.
    func streamTarget(_ id: String, _ hole: Int) async -> (push: String?, problem: String?) {
        do {
            let j = try await call("stream", ["id": id, "hole": hole])
            let r = j["rtmps"] as? [String: Any]
            guard let url = r?["url"] as? String, let key = r?["streamKey"] as? String, !url.isEmpty, !key.isEmpty else { return (nil, "Cloudflare Stream gave no address.") }
            return ((url.hasSuffix("/") ? url : url + "/") + key, nil)
        } catch { return (nil, error.localizedDescription) }
    }
    /// Is each streamed hole's camera reaching Cloudflare? → [hole: "connected" | "disconnected" | "unknown"], nil = Stream not set up
    func streamHealth(_ id: String) async -> [Int: String]? {
        guard let j = try? await call("streams", ["id": id]), j["ready"] as? Bool == true else { return nil }
        let h = j["holes"] as? [String: String] ?? [:]
        return Dictionary(uniqueKeysWithValues: h.compactMap { k, v in Int(k).map { ($0, v) } })
    }
    func flash(_ s: String, seconds: Double = 4) { notice = s; Task { try? await Task.sleep(for: .seconds(seconds)); if notice == s { notice = nil } } }
    func open(_ id: String) {
        if let e = events.first(where: { $0.id == id }) { onOpen?(e); return }
        Task { await refreshEvents(); if let e = events.first(where: { $0.id == id }) { onOpen?(e) } }
    }
}

/// The Admin passcode in the login Keychain (Flagcast Manager's own item; test builds keep their own).
enum Keychain {
    private static let service = Bundle.main.bundleIdentifier ?? "app.flagcast.manager", account = "admin-passcode"
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

/// Delete a club from Admin: a plain confirm when it has no tournaments, else type its name (a test club and its tournaments).
struct DeleteClubAlert: ViewModifier {
    @Environment(AdminModel.self) private var model
    @Binding var club: AdminClub?
    var deleted: () -> Void = {}
    @State private var typed = ""
    func body(content: Content) -> some View {
        content.alert("Delete \(club?.name ?? "club")?", isPresented: Binding(get: { club != nil }, set: { if !$0 { club = nil; typed = "" } }), presenting: club) { c in
            if !c.events.isEmpty { TextField(c.name, text: $typed).autocorrectionDisabled() }
            Button("Delete Club", role: .destructive) { let t = typed; Task { if await model.deleteClub(c, typed: t) { deleted() } } }
                .disabled(!c.events.isEmpty && !AdminModel.nameMatches(typed, c.name))
            Button("Cancel", role: .cancel) {}
        } message: { c in Text(AdminModel.deleteMessage(c)) }
    }
}
/// Recently deleted, under the clubs: one quiet line, folded until clicked, then a slim list with days left,
/// Restore, and Delete Now tucked in the ••• menu (typed name to confirm).
struct RecentlyDeleted: View {
    @Environment(AdminModel.self) private var model
    @State private var open = false
    @State private var wiping: DeletedClub?
    @State private var typed = ""
    static func daysLeft(_ c: DeletedClub) -> String {
        let d = max(0, Int(ceil((c.wipes / 1000 - Date().timeIntervalSince1970) / 86400)))
        return d == 0 ? "Wiped today" : "\(d) day\(d == 1 ? "" : "s") left"
    }
    var body: some View {
        if !model.deleted.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Button { withAnimation(.snappy) { open.toggle() } } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).rotationEffect(.degrees(open ? 90 : 0))
                        Text("Recently deleted").font(.subheadline.weight(.semibold))
                        Text("\(model.deleted.count)").font(.caption.weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                        if open { Text("Wiped for good after 30 days").font(.caption).foregroundStyle(.tertiary) }
                    }
                    .foregroundStyle(.secondary).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if open {
                    VStack(spacing: 0) {
                        ForEach(Array(model.deleted.enumerated()), id: \.element.id) { i, c in
                            if i > 0 { Divider() }
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(c.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(c.events == 0 ? "No tournaments" : "\(c.events) tournament\(c.events == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Text(Self.daysLeft(c)).font(.caption).foregroundStyle(Color(red: 0.54, green: 0.43, blue: 0.11))
                                    .padding(.horizontal, 8).padding(.vertical, 2).background(Color(red: 0.98, green: 0.95, blue: 0.86), in: Capsule())
                                Button("Restore") { Task { await model.restoreClub(c) } }
                                    .buttonStyle(.plain).font(.subheadline.weight(.semibold)).foregroundStyle(FC.green)
                                Menu {
                                    Button("Restore") { Task { await model.restoreClub(c) } }
                                    Button("Delete Now…", role: .destructive) { typed = ""; wiping = c }
                                } label: { Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 24, height: 22).contentShape(Rectangle()) }
                                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                        }
                    }
                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                    .frame(maxWidth: 640, alignment: .leading)
                }
            }
            .alert("Wipe \(wiping?.name ?? "") now?", isPresented: Binding(get: { wiping != nil }, set: { if !$0 { wiping = nil } }), presenting: wiping) { c in
                TextField(c.name, text: $typed)
                Button("Delete Now", role: .destructive) { let t = typed; Task { await model.purgeClub(c, typed: t) } }.disabled(!AdminModel.nameMatches(typed, c.name))
                Button("Cancel", role: .cancel) {}
            } message: { c in Text("Its tournaments, scores, teams and photos are deleted for good and their links stop working. This can’t be undone. Type \(c.name) to confirm.") }
        }
    }
}
extension View {
    func deleteClubAlert(_ club: Binding<AdminClub?>, deleted: @escaping () -> Void = {}) -> some View { modifier(DeleteClubAlert(club: club, deleted: deleted)) }
}

/// Find the course in Add club: type a name, pick it from the list. The server fills in its scorecard, tees and hole map
/// (golf.js adminWithCourse), so the club's tournaments start with the course in. Shared by the Mac and iPhone/iPad.
struct ClubCoursePicker: View {
    @Binding var picked: Net.FoundCourse?
    @State private var q = ""
    @State private var found: [Net.FoundCourse] = []
    @State private var msg: String?
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let c = picked {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.name).font(.system(size: 14, weight: .semibold))
                        Text("Scorecard, tees and hole map are added").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Change") { picked = nil }
                }
            } else {
                HStack(spacing: 8) {
                    TextField("Course name or town", text: $q).onSubmit(search)
                    Button(busy ? "Looking…" : "Find", action: search).disabled(busy || q.trimmingCharacters(in: .whitespaces).count < 3)
                }
                if let msg { Text(msg).font(.caption).foregroundStyle(.secondary) }
                ForEach(found) { c in
                    Button { picked = c; found = [] } label: {
                        HStack(spacing: 6) {
                            if c.library { Text("FLAGCAST").font(.system(size: 9, weight: .bold)).foregroundStyle(.green) }
                            Text(c.name).foregroundStyle(.primary).lineLimit(1)
                            if !c.place.isEmpty { Text(c.place).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).padding(.vertical, 3)
                }
                if found.isEmpty && msg == nil { Text("Optional. Pick it and every tournament starts with the course in.").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
    private func search() {
        let t = q.trimmingCharacters(in: .whitespaces); guard t.count >= 3, !busy else { return }
        busy = true; msg = nil
        Task { defer { busy = false }
            do { found = try await Net.findCourses(t); if found.isEmpty { msg = "No course by that name. Try the club’s name or the town." } }
            catch { found = []; msg = error.localizedDescription }
        }
    }
}


/// an email to open in the Add / Edit person sheet
struct StaffEmail: Identifiable { var id: String }

/// Add or edit someone on Staff (Mac, iPhone and iPad): Admin, Can go live, and where they can go live.
struct StaffPersonSheet: View {
    @Environment(AdminModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let email: String
    @State private var admin = false
    @State private var live = true
    @State private var where_ = "any"
    @State private var club = ""
    @State private var event = ""
    @State private var name = ""
    @State private var mail = true
    @State private var saving = false
    @State private var confirmRemove = false
    private var was: StaffPerson? { model.people.first { $0.email == email.lowercased() } }

    var body: some View {
        NavigationStack {
            Form {
                Section { Text(email) } header: { Text("Email") }
                Section {
                    Toggle(isOn: $admin) { VStack(alignment: .leading, spacing: 2) { Text("Admin"); Text("Everything in Admin: clubs, tournaments, cameras, payments").font(.caption).foregroundStyle(.secondary) } }
                    Toggle(isOn: admin ? .constant(true) : $live) { VStack(alignment: .leading, spacing: 2) { Text("Can go live"); Text(admin ? "Admins can always go live, at any tournament." : "Stream from their iPhone to a hole. Nothing else.").font(.caption).foregroundStyle(.secondary) } }
                        .disabled(admin)
                } header: { Text("What they can do") }
                if live && !admin {
                    Section {
                        Picker("Where", selection: $where_) {
                            Text("Any tournament").tag("any"); Text("One club’s tournaments").tag("club"); Text("One tournament").tag("event")
                        }
                        if where_ == "club" {
                            Picker("Club", selection: $club) { ForEach(model.clubs) { Text($0.name).tag($0.id) } }
                        }
                        if where_ == "event" {
                            Picker("Tournament", selection: $event) { ForEach(model.liveEventChoices, id: \.id) { Text($0.name).tag($0.id) } }
                        }
                        TextField("Their name (for “live from …’s phone”)", text: $name)
                        Toggle("Email them how to go live", isOn: $mail)
                    } header: { Text("Where") } footer: {
                        Text(where_ == "event" ? "Ends by itself when that tournament is over. They sign in to the Flagcast Manager on their iPhone with this email and only see a Go live screen." : "They sign in to the Flagcast Manager on their iPhone with this email and only see a Go live screen.")
                    }
                }
                if was != nil && !(was?.fixed ?? false) {
                    Section { Button("Remove", role: .destructive) { confirmRemove = true } }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(was == nil ? "Add person" : "Edit person")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(was == nil ? "Add" : "Save") { save(admin: admin, live: live) }
                        .disabled(saving || (!admin && !live) || (live && !admin && ((where_ == "club" && club.isEmpty) || (where_ == "event" && event.isEmpty))))
                }
            }
            .confirmationDialog("Take \(email) off? \(was?.admin != nil ? "They lose Admin and" : "They") can’t go live any more.", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { save(admin: false, live: false) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 440)
        #endif
        .onAppear {
            let p = was
            admin = p?.admin != nil; live = p == nil || p?.live != nil || admin; mail = p?.live == nil
            if let g = p?.live { where_ = g.where_; club = g.club; event = g.event; name = g.name }
            if club.isEmpty { club = model.clubs.first?.id ?? "" }
            if event.isEmpty { event = model.liveEventChoices.first?.id ?? "" }
        }
    }
    private func save(admin: Bool, live: Bool) {
        saving = true
        Task {
            let ok = await model.savePerson(email, admin: admin, live: live, where: where_, club: club, event: event, name: name, mail: mail)
            saving = false; if ok { dismiss() }
        }
    }
}
