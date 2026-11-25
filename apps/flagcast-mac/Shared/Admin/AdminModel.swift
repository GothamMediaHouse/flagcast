import Foundation
import SwiftUI
import Security
import Observation


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
    /// par 3 camera links by hole (set by Flagcast Admin only)
    var cams: [Int: String]
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.str(.id); key = c.str(.key); name = c.str(.name); club = c.str(.club); clubName = c.str(.clubName); date = c.str(.date)
        created = c.dbl(.created, 0); hidden = c.int(.hidden, 0) != 0; archived = c.int(.archived, 0) != 0; gone = c.bool(.gone, false); locked = c.bool(.locked, false); demo = c.bool(.demo, false)
        lastScore = c.dbl(.lastScore, 0); scoringNow = c.int(.scoringNow, 0)
        struct Brand: Decodable { var logo: String? }
        logo = ((try? c.decodeIfPresent(Brand.self, forKey: .brand)) ?? nil)?.logo ?? ""
        teams = c.int(.teams, 0); scored = c.int(.scored, 0); screens = c.int(.screens, 0); online = c.int(.online, 0); replays = c.int(.replays, 0)
        displays = c.list(.displays); p3 = (try? c.decodeIfPresent([Int].self, forKey: .p3)) ?? []; sponsors = c.list(.sponsors); replayList = c.list(.replayList)
        scenes = c.list(.scenes); scene = c.str(.scene); flights = (try? c.decodeIfPresent([String].self, forKey: .flights)) ?? []
        take = try? c.decodeIfPresent(Take.self, forKey: .take); flash = try? c.decodeIfPresent(Flash.self, forKey: .flash); phone = try? c.decodeIfPresent(PhoneRoute.self, forKey: .phone)
        let raw = (try? c.decodeIfPresent([String: String].self, forKey: .cams)) ?? [:]
        cams = Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in Int(k).map { ($0, v) } })
    }
    enum CodingKeys: String, CodingKey { case id, key, name, club, clubName, date, created, hidden, archived, gone, locked, demo, brand, lastScore, scoringNow, teams, scored, screens, online, replays, displays, p3, sponsors, replayList, scenes, scene, flights, take, flash, phone, cams }
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
    func clear() { clubs = []; events = []; log = []; staff = []; error = nil; notice = nil }

    @discardableResult
    func call(_ op: String?, _ extra: [String: Any] = [:]) async throws -> [String: Any] {
        var b = body(extra); if let op { b["op"] = op }
        return Net.json(try await Net.post("/golf/api/club/admin", b))
    }
    func refresh() async throws {
        loading = true; defer { loading = false }
        let d = try await Net.post("/golf/api/club/admin", body([:]))
        struct R: Decodable { var clubs: [Lenient<AdminClub>]; var mail: Bool?; var staff: [Lenient<StaffMember>]?; var deleted: [Lenient<DeletedClub>]? }
        let r = try JSONDecoder().decode(R.self, from: d)
        clubs = r.clubs.compactMap(\.value); mail = r.mail ?? true; staff = (r.staff ?? []).compactMap(\.value); deleted = (r.deleted ?? []).compactMap(\.value)
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
            try await call(op, extra)
            try await refresh()
            if ["lock", "archive", "move", "hide", "unhide", "event", "claim", "demo", "delete", "restore", "purge"].contains(op) { await refreshEvents() }
            if let done { flash(done) }
        } catch { flash(error.localizedDescription) }
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
    func flash(_ s: String) { notice = s; Task { try? await Task.sleep(for: .seconds(4)); if notice == s { notice = nil } } }
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
/// Recently deleted, under the clubs: Restore, or Delete now with the name typed.
struct RecentlyDeleted: View {
    @Environment(AdminModel.self) private var model
    @State private var wiping: DeletedClub?
    @State private var typed = ""
    var body: some View {
        if !model.deleted.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recently deleted").font(.headline)
                Text("Kept 30 days with their tournaments locked, then wiped for good.").font(.footnote).foregroundStyle(.secondary)
                ForEach(model.deleted) { c in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(c.name).font(.subheadline.weight(.semibold))
                            Text("\(c.events) tournament\(c.events == 1 ? "" : "s") · wiped \(Date(timeIntervalSince1970: c.wipes / 1000).formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore") { Task { await model.restoreClub(c) } }
                        Button("Delete Now", role: .destructive) { typed = ""; wiping = c }
                    }
                    .padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
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
