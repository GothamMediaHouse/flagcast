import SwiftUI

/// The club's TVs with the Flagcast TV app (Apple TV, Google TV, Fire TV, Roku) or a TV browser at flagcast.app/tv
/// (tv.js on the server). They belong to the club, not to one tournament: add one once with the code it shows and it
/// plays the tournament of the day by itself, as one of that tournament's TVs. Shared by the Mac and iPhone/iPad Managers.
struct ClubTV: Decodable, Identifiable, Hashable {
    var id: String, name: String, `where`: String, kind: String, on: Bool
    /// the tournament it always shows ('' = the tournament of the day)
    var event: String = "", eventName: String = ""
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); name = (try? c.decode(String.self, forKey: .name)) ?? "TV"
        `where` = (try? c.decode(String.self, forKey: .where)) ?? ""; kind = (try? c.decode(String.self, forKey: .kind)) ?? ""
        on = (try? c.decode(Bool.self, forKey: .on)) ?? false
        event = (try? c.decode(String.self, forKey: .event)) ?? ""; eventName = (try? c.decode(String.self, forKey: .eventName)) ?? ""
    }
    enum CodingKeys: String, CodingKey { case id, name, `where`, kind, on, event, eventName }
    var kindName: String { ["appletv": "Apple TV", "androidtv": "Google TV", "firetv": "Fire TV", "roku": "Roku"][kind] ?? "TV browser" }
}

@MainActor @Observable
final class ClubTVs {
    var list: [ClubTV] = []
    var loaded = false
    var error: String?
    private struct Answer: Decodable { var tvs: [ClubTV]; var added: Int? }

    /// The server makes every club TV one of this tournament's screens when it's asked from here: when one is new, its
    /// card shows (the setup reloads, keeping unsaved edits).
    private func call(_ op: String, _ doc: DeskDoc, _ extra: [String: Any] = [:]) async throws -> [ClubTV] {
        var b = extra; b["id"] = doc.id; b["key"] = doc.key
        let d = try await Net.post("/golf/api/tv/\(op)", b)
        let a = try JSONDecoder().decode(Answer.self, from: d)
        let missing = a.tvs.contains { t in !doc.ev.displays.contains { $0.id == t.id } }
        if (a.added ?? 0) > 0 || (missing && doc.loaded) { await doc.refreshDay() }
        return a.tvs
    }
    func load(_ doc: DeskDoc) async {
        do { list = try await call("list", doc); error = nil } catch { self.error = (error as? APIError)?.message ?? error.localizedDescription }
        loaded = true
    }
    /// true when the TV was connected
    func add(_ doc: DeskDoc, code: String, name: String, place: String) async -> Bool {
        do { list = try await call("add", doc, ["code": code, "name": name, "where": place]); doc.flash("\(name.isEmpty ? "The TV" : name) is connected. It shows this tournament on the day."); return true }
        catch { doc.flash((error as? APIError)?.message ?? "That didn’t work. Try again."); return false }
    }
    func rename(_ doc: DeskDoc, _ tv: ClubTV, name: String) async {
        do { list = try await call("edit", doc, ["tv": tv.id, "name": name]) } catch { doc.flash((error as? APIError)?.message ?? "That didn’t work.") }
    }
    /// Always show this tournament on it (nil: back to the tournament of the day)
    func pin(_ doc: DeskDoc, _ tv: ClubTV, _ on: Bool) async {
        do { list = try await call("edit", doc, ["tv": tv.id, "event": on ? doc.id : ""])
             doc.flash(on ? "\(tv.name) always shows this tournament now." : "\(tv.name) shows the tournament of the day.") }
        catch { doc.flash((error as? APIError)?.message ?? "That didn’t work.") }
    }
    func remove(_ doc: DeskDoc, _ tv: ClubTV) async {
        do { list = try await call("remove", doc, ["tv": tv.id]); await doc.refreshDay(); doc.flash("\(tv.name) is removed. It shows a new code.") } catch { doc.flash((error as? APIError)?.message ?? "That didn’t work.") }
    }
}

/// "Club TVs": the list, and Add a TV with the code on the TV
struct ClubTVsCard: View {
    @Bindable var doc: DeskDoc
    @State private var tvs = ClubTVs()
    @State private var adding = false
    @State private var code = ""
    @State private var name = ""
    @State private var place = ""
    @State private var busy = false
    @State private var renaming: ClubTV?
    @State private var newName = ""
    @State private var removing: ClubTV?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Club TVs").font(FC.display(24))
                    Text("Apple TV, Google TV, Fire TV or Roku with the Flagcast TV app, or any TV’s browser at flagcast.app/tv. Add a TV once: it shows the tournament of the day by itself. Each one also has a card below, where you pick what it shows in this tournament.")
                        .font(.system(size: 13)).foregroundStyle(FC.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button { adding = true } label: { Label("Add a TV", systemImage: "plus") }.buttonStyle(GreenButton())
            }
            if let e = tvs.error { Text(e).font(.system(size: 13)).foregroundStyle(FC.muted) }
            else if tvs.loaded && tvs.list.isEmpty { Text("No club TVs yet.").font(.system(size: 13)).foregroundStyle(FC.muted) }
            ForEach(tvs.list) { t in
                HStack(spacing: 10) {
                    Image(systemName: t.kind == "appletv" ? "appletv" : "tv").foregroundStyle(FC.muted).frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.name).font(.system(size: 15, weight: .semibold))
                        Text([t.kindName, t.where, pinNote(t)].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(FC.muted)
                    }
                    Spacer()
                    Text(t.on ? "On" : "Off").font(.system(size: 12, weight: .semibold)).foregroundStyle(t.on ? FC.link : FC.muted)
                    Menu {
                        if t.event == doc.id { Button("Show the Tournament of the Day") { Task { await tvs.pin(doc, t, false) } } }
                        else { Button("Always Show This Tournament") { Task { await tvs.pin(doc, t, true) } } }
                        Button("Rename…") { newName = t.name; renaming = t }
                        Button("Remove", role: .destructive) { removing = t }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .fixedSize()
                    .accessibilityLabel("More for \(t.name)")
                }
                .padding(.vertical, 6)
                Divider().overlay(FC.hairline)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(FC.line))
        .task { await tvs.load(doc); while !Task.isCancelled { try? await Task.sleep(for: .seconds(60)); await tvs.load(doc) } }
        .sheet(isPresented: $adding) { addSheet }
        .alert("Rename this TV", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") { if let t = renaming { Task { await tvs.rename(doc, t, name: newName) } } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Remove \(removing?.name ?? "this TV")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) { if let t = removing { Task { await tvs.remove(doc, t) } } }
        } message: { Text("It goes back to showing a code.") }
    }

    private func pinNote(_ t: ClubTV) -> String {
        t.event.isEmpty ? "" : t.event == doc.id ? "Always shows this tournament" : "Always shows \(t.eventName.isEmpty ? "another tournament" : t.eventName)"
    }

    private var addSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a TV").font(FC.display(30))
            Text("Open the Flagcast TV app on the TV, or go to flagcast.app/tv in its browser. Type the code it shows.")
                .font(.system(size: 14)).foregroundStyle(FC.muted).fixedSize(horizontal: false, vertical: true)
            TextField("TV code", text: $code, prompt: Text("K7PMR4"))
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .onChange(of: code) { _, v in let c = String(v.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6)); if c != v { code = c } }
                .autocorrectionDisabled()
            TextField("Name", text: $name, prompt: Text("Clubhouse bar")).textFieldStyle(.roundedBorder)
            TextField("Where is it?", text: $place, prompt: Text("Over the taps (optional)")).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { adding = false }
                Button(busy ? "Connecting…" : "Connect TV") {
                    busy = true
                    Task { if await tvs.add(doc, code: code, name: name, place: place) { adding = false; code = ""; name = ""; place = "" }; busy = false }
                }
                .buttonStyle(GreenButton()).disabled(code.count != 6 || busy)
            }
        }
        .padding(28)
        .frame(minWidth: 380, idealWidth: 440)
    }
}
