import SwiftUI

/// Screens and phones for any club's tournament: send a page to one screen or all of them (or back to their
/// playlists), take over every screen, point every player's phone at something, show an announcement, and scenes.
struct ScreenControlView: View {
    @Environment(AdminModel.self) private var model
    @State private var eventId: String?
    @State private var flash = ""
    @State private var takeText = ""
    @State private var takeSecs = 25
    @State private var phoneText = ""
    @State private var sceneName = ""

    private var live: [AdminEvent] { model.events.filter { !$0.gone && !$0.archived && !$0.hidden }.sorted { ($0.online, $0.created) > ($1.online, $1.created) } }
    private var e: AdminEvent? { model.events.first { $0.id == eventId } ?? live.first }

    var body: some View {
        Form {
            SwiftUI.Section {
                Picker("Tournament", selection: Binding(get: { e?.id ?? "" }, set: { eventId = $0 })) {
                    ForEach(live) { x in Text("\(x.name) · \(x.clubName)\(x.online > 0 ? " · \(x.online) screen\(x.online == 1 ? "" : "s") on" : "")").tag(x.id) }
                }
            }
            if let e {
                SwiftUI.Section {
                    if e.displays.isEmpty { Text("This tournament has no screens set up (the desk’s Staff and Playlists page).").foregroundStyle(.secondary) }
                    ForEach(e.displays) { d in
                        HStack {
                            Circle().fill(d.online > 0 ? Color.green : Color.secondary.opacity(0.4)).frame(width: 8, height: 8)
                            Text(d.name).fontWeight(.medium)
                            Text(d.force.map { "Showing: \(label($0))" } ?? "Playing its list (\(d.pages) page\(d.pages == 1 ? "" : "s"))").foregroundStyle(.secondary)
                            Spacer()
                            RouteMenu(e: e) { page in Task { await model.day(e.id, ["op": "screen", "display": d.id, "page": page ?? NSNull()], done: "Sent to \(d.name).") } }
                        }
                    }
                    HStack { Text("Every screen").fontWeight(.medium); Spacer()
                        RouteMenu(e: e) { page in Task { await model.day(e.id, ["op": "screen", "display": "*", "page": page ?? NSNull()], done: "Sent to every screen.") } } }
                } header: { Text("Screens") } footer: { Help("Send a page to a screen until you send it back to its playlist.") }
                SwiftUI.Section("Take over every screen") {
                    if let t = e.take { HStack { Text("Now: \(t.kind)\(t.text.map { " · \($0)" } ?? "")").foregroundStyle(.orange); Spacer(); Button("Clear") { take(e, ["kind": "clear"]) } } }
                    HStack {
                        TextField("Message", text: $takeText, prompt: Text("Lunch is served at the turn"))
                        Stepper("\(takeSecs) s", value: $takeSecs, in: 5...120, step: 5).monospacedDigit()
                        Button("Announce") { take(e, ["kind": "msg", "text": takeText, "secs": takeSecs]) }.disabled(takeText.isEmpty)
                        Button("Hole in One!") { take(e, ["kind": "ace", "text": takeText, "secs": takeSecs]) }
                    }
                    if !e.sponsors.isEmpty {
                        HStack { Text("Sponsor moment"); Spacer()
                            Menu("Pick a Sponsor") { ForEach(e.sponsors) { s in Button(s.name) { take(e, ["kind": "sponsor", "sponsor": s.id, "secs": takeSecs]) } } }.fixedSize() }
                    }
                    if !e.replayList.isEmpty {
                        HStack { Text("Replay"); Spacer()
                            Menu("Pick a Replay") { ForEach(e.replayList) { r in Button("Hole \(r.hole) · \(r.label.isEmpty ? "Replay" : r.label)") { take(e, ["kind": "replay", "replay": r.id]) } } }.fixedSize() }
                    }
                }
                SwiftUI.Section {
                    if let p = e.phone { HStack { Text("Now: \(label(PageRef(k: p.k, fl: p.fl, hole: p.hole, sponsor: p.sponsor)))\(p.text.isEmpty ? "" : " · “\(p.text)”")").foregroundStyle(.orange); Spacer()
                        Button("Clear") { Task { await model.day(e.id, ["op": "screen", "display": "phones", "page": NSNull()], done: "Phones cleared.") } } } }
                    HStack {
                        TextField("Line on the banner", text: $phoneText, prompt: Text("Watch the 7th: closest to the pin is close!"))
                        RouteMenu(e: e, title: "Send to Phones", playlist: false) { page in Task { await model.day(e.id, ["op": "screen", "display": "phones", "page": page ?? NSNull(), "text": phoneText], done: "On every player’s phone.") } }
                    }
                } header: { Text("Players’ phones") } footer: { Help("Puts a banner on every player’s scorecard and the live leaderboard, pointing at the page you pick.") }
                SwiftUI.Section("Announcement") {
                    if let f = e.flash { HStack { Text("Showing: “\(f.text)”").foregroundStyle(.secondary); Spacer(); Button("Clear") { Task { await model.day(e.id, ["op": "flash", "text": ""], done: "Cleared.") } } } }
                    HStack { TextField("Announcement", text: $flash, prompt: Text("Shotgun start in 10 minutes"))
                        Button("Show on Every Screen") { Task { await model.day(e.id, ["op": "flash", "text": flash], done: "On every screen."); flash = "" } }.disabled(flash.isEmpty) }
                }
                SwiftUI.Section {
                    ForEach(e.scenes) { s in
                        HStack { Text(s.name).fontWeight(e.scene == s.id ? .semibold : .regular); if e.scene == s.id { Text("on now").font(.caption).foregroundStyle(.green) }; Spacer()
                            Button("Put Back") { Task { await model.day(e.id, ["op": "scene", "apply": s.id], done: "Scene on.") } }
                            Button(role: .destructive) { Task { await model.day(e.id, ["op": "scene", "remove": s.id]) } } label: { Image(systemName: "trash") }.buttonStyle(.borderless) }
                    }
                    HStack { TextField("Save what every screen shows now as", text: $sceneName, prompt: Text("Lunch")); Button("Save Scene") { Task { await model.day(e.id, ["op": "scene", "save": sceneName], done: "Scene saved."); sceneName = "" } }.disabled(sceneName.isEmpty) }
                } header: { Text("Scenes") }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(FC.card).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(FC.line))
        .padding(20)
        .safeAreaInset(edge: .top, spacing: 0) {
            AdminHeader(title: "Screens & phones", sub: "Any club’s screens and every player’s phone", search: .constant(""), prompt: "") {
                Button { Task { await model.refreshEvents() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(PlainCardButton())
            }
        }
        .background(FC.paper)
        .task { while !Task.isCancelled { await model.refreshEvents(); try? await Task.sleep(for: .seconds(15)) } }
    }
    private func take(_ e: AdminEvent, _ b: [String: Any]) { var d = b; d["op"] = "take"; Task { await model.day(e.id, d, done: b["kind"] as? String == "clear" ? "Back to the playlists." : "On every screen now.") } }
    private func label(_ p: PageRef) -> String {
        let n = PAGE_NAMES.first { $0.0 == p.k }?.1 ?? p.k
        return n + (p.hole > 0 ? " · hole \(p.hole)" : "") + (p.fl.isEmpty ? "" : " · flight \(p.fl)")
    }
}

/// The pages a screen or the phones can be sent to.
struct RouteMenu: View {
    let e: AdminEvent
    var title = "Send…"
    var playlist = true
    let send: ([String: Any]?) -> Void
    var body: some View {
        Menu(title) {
            if playlist { Button("Back to Its Playlist") { send(nil) }; Divider() }
            Button("Leaderboard") { send(["k": "lb"]) }
            ForEach(e.flights, id: \.self) { f in Button("Leaderboard · Flight \(f)") { send(["k": "lb", "fl": f]) } }
            ForEach(e.p3, id: \.self) { h in Button("Par 3 Camera · Hole \(h)") { send(["k": "p3", "hole": h]) } }
            Button("Contests") { send(["k": "contests"]) }
            Button("Skins") { send(["k": "skins"]) }
            Button("Fundraising") { send(["k": "fund"]) }
            Button("All Sponsors") { send(["k": "sponsors"]) }
            ForEach(e.sponsors) { s in Button("Sponsor · \(s.name)") { send(["k": "sponsor", "sponsor": s.id]) } }
            Button("Schedule") { send(["k": "schedule"]) }
        }
        .fixedSize()
    }
}
