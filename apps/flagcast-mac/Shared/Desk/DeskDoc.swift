import Foundation
import Observation

/// One open tournament: its setup as the desk has it (edited in place, saved with ⌘S), and its live state
/// (scores, screens) from the shared WebSocket feed.
@MainActor @Observable
final class DeskDoc {
    let ref: EventRef
    var ev = DeskEvent()
    private var savedData = Data()
    var loading = false
    var saving = false
    var error: String?
    var notice: String?
    let feed: EventFeed
    /// the course picture for the page headers
    let picture = CoursePicture()

    init(ref: EventRef) {
        self.ref = ref
        feed = Feeds.feed(ref.id)
        feed.start()
    }
    var id: String { ref.id }
    var key: String { ref.key }
    var loaded: Bool { !savedData.isEmpty }
    /// Unsaved changes: the setup differs from what the server has.
    var dirty: Bool { loaded && ev.setupData != savedData }
    var live: EventState? { feed.state }

    func load() async {
        loading = true; defer { loading = false }
        do { set(try await Net.deskGet(id, key)); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func set(_ e: DeskEvent) { ev = e; savedData = e.setupData }

    func save() async {
        guard dirty, !saving else { return }
        saving = true; defer { saving = false }
        do { set(try await Net.deskSave(id, key, ev)); flash("Saved. The screens and scorecards have it now.") }
        catch { flash(error.localizedDescription) }
    }
    func revert() { if let e = try? JSONDecoder().decode(DeskEvent.self, from: savedData) { var x = ev; x.apply(setup: e); ev = x } }

    func setLocked(_ on: Bool) async {
        do { try await Net.desk(id, key, "lock", ["locked": on]); ev.locked = on; flash(on ? "Results locked. Scoring is closed." : "Results unlocked.") }
        catch { flash(error.localizedDescription) }
    }
    /// A change made on the day (it saves at once, no Save needed).
    @discardableResult
    func day(_ op: String, _ extra: [String: Any] = [:], done: String? = nil) async -> [String: Any]? {
        do {
            let r = try await Net.desk(id, key, op, extra)
            if let done { flash(done) }
            return r
        } catch { flash(error.localizedDescription); return nil }
    }
    /// Reload the read-only parts (contest results, replays, scenes, report) without touching unsaved edits.
    func refreshDay() async {
        guard let fresh = try? await Net.deskGet(id, key) else { return }
        let keep = ev, wasDirty = dirty
        var e = fresh
        if wasDirty { e.apply(setup: keep) }
        ev = e
        savedData = fresh.setupData
    }
    /// A photo golfers see (brand.js): "cover", "h<n>" for a hole, "s-<sponsor id>" for a banner. Saved at once.
    /// nil takes it off. The picture is shrunk to about 1600 px across as a JPEG first.
    func setPhoto(_ slot: String, _ data: Data?) async {
        var extra: [String: Any] = ["slot": slot, "image": ""]
        if let data {
            guard let uri = PhotoPrep.dataURI(data) else { flash("That file isn’t a photo this app can read. Try a JPEG."); return }
            extra["image"] = uri
        }
        photoBusy.insert(slot); defer { photoBusy.remove(slot) }
        guard let r = await day("photo", extra, done: data == nil ? "Photo removed." : "Photo added. Golfers see it now."),
              let p = r["photos"], let d = try? JSONSerialization.data(withJSONObject: p), let ph = try? JSONDecoder().decode(Photos.self, from: d) else { return }
        ev.photos = ph
    }
    var photoBusy: Set<String> = []
    func flash(_ s: String) { notice = s; Task { try? await Task.sleep(for: .seconds(4)); if notice == s { notice = nil } } }

    // ---- links ----
    var base: String { Server.base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
    var liveURL: URL { URL(string: "\(base)/g/\(id)")! }
    var boardURL: URL { URL(string: "\(base)/g/\(id)/board")! }
    var deskURL: URL { URL(string: "\(base)/g/\(id)/desk#\(key)")! }
    func cartURL(_ code: String) -> URL { URL(string: "\(base)/g/\(id)/s/\(code)")! }
}

extension DeskEvent {
    /// Take another copy's setup fields, keeping this one's read-only parts.
    mutating func apply(setup s: DeskEvent) {
        name = s.name; club = s.club; date = s.date; course = s.course; format = s.format; sideGames = s.sideGames; flights = s.flights
        teams = s.teams; screens = s.screens; cams = s.cams; sponsors = s.sponsors; schedule = s.schedule; pins = s.pins
        displays = s.displays; fund = s.fund; contests = s.contests
    }
}
