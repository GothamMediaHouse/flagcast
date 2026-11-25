import SwiftUI

/// A golf pro or marshal, signed in with the PIN from the Manager (matches public/golf/app/pro/).
/// Pros get Live, Scores, Screens, Pins (pin sheet + contests) and Replays; marshals post contest results and replays.
@MainActor @Observable
final class ProModel {
    let id: String
    let feed: EventFeed
    var pin: String?
    var name = ""
    var role = ""
    var toast: String?
    var signedOut = false
    var failed: String?
    var log: [[String: Any]] = []
    var busy = false

    init(id: String) {
        self.id = id
        feed = Feeds.feed(id)
        pin = PinStore.load(id)
        if let s = ProSignIns.all().first(where: { $0.id == id }) { name = s.name; role = s.role }
    }

    func hello() async {
        guard let pin else { signedOut = true; return }
        do {
            let r = try await API.post(id, "pro", ["pin": pin, "op": "hello"])
            name = r["name"] as? String ?? name
            role = r["role"] as? String ?? role
            failed = nil
            ProSignIns.save(ProSignIn(id: id, event: id, name: name, role: role))
        } catch let e as APIError where e.status == 403 || e.status == 404 {
            signOut()
        } catch let e as APIError {
            if role.isEmpty { failed = e.message }   // never signed in here before, and no signal
        } catch {}
    }

    /// One of the day ops (fix, ctp, flash, nudge, fund, lock, take, screen, stats). Shows the server's own words on failure.
    @discardableResult
    func op(_ body: [String: Any?], ok: String? = nil) async -> [String: Any]? {
        guard let pin else { return nil }
        busy = true; defer { busy = false }
        var b = body; b["pin"] = pin
        do {
            let r = try await API.post(id, "pro", b)
            if let ok { toast = ok }
            return r
        } catch let e as APIError {
            toast = e.message
            if e.status == 403 && e.message.contains("PIN") { signOut() }
            return nil
        } catch { return nil }
    }

    func loadLog() async {
        if let r = await op(["op": "stats"]) { log = (r["log"] as? [[String: Any]]) ?? [] }
    }

    func signOut() {
        ProSignIns.remove(id)
        pin = nil
        signedOut = true
    }
}

struct ProScreen: View {
    @State private var model: ProModel
    @Environment(Router.self) private var router
    init(id: String) { _model = State(initialValue: ProModel(id: id)) }

    var body: some View {
        Group {
            if let f = model.failed {
                ContentUnavailableView("No signal", systemImage: "wifi.slash", description: Text(f))
            } else if let s = model.feed.state, !model.role.isEmpty {
                if model.role == "pro" {
                    TabView {
                        ProLiveTab(model: model, s: s).tabItem { Label("Live", systemImage: "waveform.path.ecg") }
                        ProScoresTab(model: model, s: s).tabItem { Label("Scores", systemImage: "list.clipboard") }
                        ProScreensTab(model: model, s: s).tabItem { Label("Screens", systemImage: "tv") }
                        ProPinsTab(model: model, s: s).tabItem { Label("Pins", systemImage: "flag") }
                        ProReplaysTab(model: model, s: s).tabItem { Label("Replays", systemImage: "arrow.counterclockwise.circle") }
                    }
                } else {
                    // marshals post contest results and save replays of shots at their hole
                    TabView {
                        ProContestsTab(model: model, s: s).tabItem { Label("Contests", systemImage: "flag") }
                        ProReplaysTab(model: model, s: s).tabItem { Label("Replays", systemImage: "arrow.counterclockwise.circle") }
                    }
                }
            } else {
                ProgressView("Signing in").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.fcPaper)
        .navigationTitle(model.feed.state?.name ?? "Golf pro")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.fcGreen, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { LivePill(online: model.feed.online, offText: "Offline") }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !model.name.isEmpty { Text("\(model.name) · \(model.role == "pro" ? "Golf pro" : "Marshal")") }
                    Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { model.signOut() }
                } label: { Image(systemName: "person.crop.circle") }
                .accessibilityLabel("Account")
            }
        }
        .toast($model.toast)
        .task { await model.hello() }
        .onAppear { model.feed.start() }
        .onDisappear { model.feed.stop() }
        .onChange(of: model.signedOut) { _, out in if out { router.path = [] } }
    }
}

// ---- LIVE: every cart and a nudge; news to the screens; fundraising total; lock scoring ----
struct ProLiveTab: View {
    var model: ProModel
    var s: EventState
    @State private var flash = ""
    @State private var raised = ""
    @State private var messaging: MessageTo?
    @State private var confirmLock = false
    @State private var files: [URL] = []
    @State private var gettingFiles = false

    var body: some View {
        let stab = s.format.isStableford
        List {
            Section {
                Button { messaging = MessageTo(team: nil) } label: { Label("Message every golfer", systemImage: "megaphone") }
                NavigationLink { ProTeamsView(model: model, s: s) } label: { Label("Fix a team or add a late group", systemImage: "person.2.badge.gearshape") }
            } header: { Text("Golfers") } footer: { Text("Messages pop up on their phones. Nudge one cart below, or one golfer on it.") }
            Section("On the course") {
                let lb = Core.leaderboard(s, s.scores)
                if lb.isEmpty { Text("No teams yet.").foregroundStyle(Color.fcMuted) }
                ForEach(lb) { l in
                    HStack(spacing: 10) {
                        Text(l.pos).font(.subheadline.monospaced()).foregroundStyle(Color.fcMuted).frame(width: 30, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(l.name).font(.body.weight(.semibold)).lineLimit(1)
                            Text((l.sub.isEmpty ? "" : "\(l.sub) · ") + "Thru \(l.thru)").font(.caption).foregroundStyle(Color.fcMuted).lineLimit(1)
                        }
                        Spacer()
                        Text(l.played > 0 ? Core.fmtPar(l.score, stab) : "—").font(.body.monospaced().weight(.semibold))
                            .foregroundStyle(!stab && l.score < 0 && l.played > 0 ? Color.fcRed : Color.fcInk)
                        Button("Nudge") { messaging = MessageTo(team: s.team(l.teamId) ?? l.team) }
                            .buttonStyle(.bordered).tint(Color.fcGreen2)
                    }
                }
            }
            Section {
                TextField("Shotgun start in 10 minutes", text: $flash, axis: .vertical).lineLimit(1...3)
                    .onChange(of: flash) { _, v in if v.count > 140 { flash = String(v.prefix(140)) } }
                Button("Post to every screen") {
                    let t = flash.trimmingCharacters(in: .whitespaces); guard !t.isEmpty else { return }
                    Task { if await model.op(["op": "flash", "text": t], ok: "On the screens") != nil { flash = "" } }
                }
                .disabled(flash.trimmingCharacters(in: .whitespaces).isEmpty)
                ForEach(Array(s.news.suffix(3).reversed().enumerated()), id: \.offset) { _, n in
                    Text("\(Fmt.time(n.at)) · \(n.text)").font(.footnote).foregroundStyle(Color.fcMuted)
                }
            } header: { Text("News on every screen") }
            if s.fund.on {
                Section("Fundraising") {
                    HStack {
                        TextField("Total raised", text: $raised).keyboardType(.numberPad).font(.body.monospaced())
                        Button("Update total") { Task { await model.op(["op": "fund", "raised": Double(raised) ?? 0], ok: "Total updated") } }
                    }
                    .onAppear { raised = String(Int(s.fund.raised)) }
                }
            }
            Section("Scoring") {
                Button(s.locked ? "Open scoring again" : "Close scoring (results final)", role: s.locked ? nil : .destructive) {
                    if s.locked { Task { await model.op(["op": "lock", "locked": false], ok: "Scoring open") } } else { confirmLock = true }
                }
            }
            Section {
                Button { Task { await getFiles() } } label: {
                    HStack { Label(files.isEmpty ? "Get the results files" : "Get them again (latest scores)", systemImage: "arrow.down.doc"); if gettingFiles { Spacer(); ProgressView() } }
                }
                .disabled(gettingFiles)
                ForEach(files, id: \.self) { u in
                    ShareLink(item: u) { Label(u.deletingPathExtension().lastPathComponent, systemImage: "square.and.arrow.up") }
                }
            } header: { Text("Results") } footer: {
                Text("Results by flight, and every player’s round ready to post to GHIN (each hole capped at net double bogey). Send them to the handicap chair, or open them in Numbers or Excel.")
            }
        }
        .refreshable { await model.feed.refresh() }
        .confirmationDialog("Close scoring?", isPresented: $confirmLock, titleVisibility: .visible) {
            Button("Close scoring", role: .destructive) { Task { await model.op(["op": "lock", "locked": true], ok: "Scoring closed") } }
        } message: { Text("Players won’t be able to change scores.") }
        .sheet(item: $messaging) { m in ProMessageSheet(model: model, to: m.team).presentationDetents([.medium, .large]) }
    }

    /// The day's two files from the server (results, GHIN posting), saved as CSV to share.
    private func getFiles() async {
        gettingFiles = true; defer { gettingFiles = false }
        guard let r = await model.op(["op": "report"]) else { return }
        let base = ((r["name"] as? String) ?? "").replacingOccurrences(of: "[^A-Za-z0-9 -]+", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("results", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var out: [URL] = []
        for (key, what) in [("results", "results"), ("ghin", "GHIN posting")] {
            guard let rows = r[key] as? [[Any]], rows.count > 1 else { continue }
            let text = rows.map { row in
                row.map { c -> String in
                    let v = c is NSNull ? "" : "\(c)"
                    return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                }.joined(separator: ",")
            }.joined(separator: "\r\n")
            let u = dir.appendingPathComponent("\(base.isEmpty ? "Tournament" : base) - \(what).csv")
            if (try? ("\u{FEFF}" + text).write(to: u, atomically: true, encoding: .utf8)) != nil { out.append(u) }
        }
        files = out
        model.toast = out.isEmpty ? "No scores yet." : (r["ghin"] is NSNull ? "Ready. Scramble scores can’t be posted for handicaps." : "Ready to share")
    }
}

struct MessageTo: Identifiable { var team: Team?; var id: String { team?.id ?? "*" } }

/// A message to every golfer (to == nil), a whole cart, or one golfer on it.
struct ProMessageSheet: View {
    var model: ProModel
    var to: Team?
    @State private var player = ""
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss
    private let quick = ["Weather delay. Please head back to the clubhouse.", "Play has resumed. Back to your holes.",
                         "Lunch is ready at the clubhouse.", "Shotgun start in 10 minutes. Please head to your carts."]
    var body: some View {
        NavigationStack {
            Form {
                if let t = to, t.players.count > 1 {
                    Picker("To", selection: $player) {
                        Text("The whole cart").tag("")
                        ForEach(t.players, id: \.id) { p in Text(p.name).tag(p.id) }
                    }
                }
                Section {
                    TextField("Message", text: $text, axis: .vertical).lineLimit(2...5)
                        .onChange(of: text) { _, v in if v.count > 140 { text = String(v.prefix(140)) } }
                } footer: {
                    Text(to == nil ? "Pops up on every golfer’s phone." : player.isEmpty ? "Pops up on this cart’s phones."
                         : "Pops up on their phone if they picked their name on the scorecard, otherwise on the cart’s phones.")
                }
                if to == nil {
                    Section("Quick messages") { ForEach(quick, id: \.self) { q in Button(q) { text = q } } }
                }
            }
            .navigationTitle(to.map { "Message \($0.displayName)" } ?? "Message every golfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        var b: [String: Any?] = ["op": "nudge", "team": to?.id ?? "*", "text": t]
                        if !player.isEmpty { b["player"] = player }
                        Task { if await model.op(b, ok: to == nil ? "Sent to every golfer" : "Sent to their phone") != nil { dismiss() } }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { if to != nil && text.isEmpty { text = "Please keep up the pace of play. Thank you!" } }
        }
    }
}

// ---- TEAMS: fix a team on the day (names, handicaps, add, take off or move a player) or add a late group ----
struct ProTeamsView: View {
    var model: ProModel
    var s: EventState
    var body: some View {
        let st = model.feed.state ?? s
        List {
            Section {
                NavigationLink { ProTeamEditor(model: model, team: nil) } label: { Label("Add a late group", systemImage: "plus.circle.fill") }
            }
            Section("Teams") {
                ForEach(st.teams, id: \.id) { t in
                    NavigationLink { ProTeamEditor(model: model, team: t) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.displayName).font(.body.weight(.semibold)).lineLimit(1)
                            Text(t.players.map(\.name).joined(separator: ", ")).font(.caption).foregroundStyle(Color.fcMuted).lineLimit(1)
                        }
                    }
                }
            }
        }
        .navigationTitle("Teams")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ProTeamEditor: View {
    var model: ProModel
    var team: Team?
    struct Row: Identifiable { var id = UUID().uuidString; var pid: String?; var name: String; var hcp: String; var index: Double? }
    @State private var name = ""
    @State private var rows: [Row] = []
    @State private var start = 1
    @State private var newCode: String?
    @State private var loaded = false
    @Environment(\.dismiss) private var dismiss

    private static func num(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }

    var body: some View {
        let others = (model.feed.state?.teams ?? []).filter { $0.id != team?.id && $0.players.count < 4 }
        Form {
            Section("Team name") { TextField("Optional", text: $name).textInputAutocapitalization(.words) }
            if team == nil {
                Picker("Starts on hole", selection: $start) { ForEach(1...18, id: \.self) { Text("\($0)").tag($0) } }
            }
            Section {
                ForEach($rows) { $r in
                    HStack {
                        TextField("Player name", text: $r.name).textInputAutocapitalization(.words)
                        if r.index != nil {
                            Text("Index \(Core.fmtIndex(r.index))").font(.caption).foregroundStyle(Color.fcMuted)
                        } else {
                            TextField("Hcp", text: $r.hcp).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                                .frame(width: 56).font(.body.monospaced())
                        }
                        if let pid = r.pid, team != nil, !others.isEmpty {
                            Menu {
                                Section("Move to") {
                                    ForEach(others, id: \.id) { o in
                                        Button(o.displayName) {
                                            Task { if await model.op(["op": "move", "player": pid, "to": o.id], ok: "Moved to \(o.displayName)") != nil { dismiss() } }
                                        }
                                    }
                                }
                            } label: { Image(systemName: "arrow.left.arrow.right.circle") }
                            .accessibilityLabel("Move to another cart")
                        }
                    }
                }
                .onDelete { rows.remove(atOffsets: $0) }
                if rows.count < 4 {
                    Button { rows.append(Row(pid: nil, name: "", hcp: "", index: nil)) } label: { Label("Add a player", systemImage: "person.badge.plus") }
                }
            } header: { Text("Players") } footer: {
                Text(team == nil ? "Save to get the new cart’s code for their scorecard."
                     : "Swipe left on a player to take them off. The arrows move a player, with their scores, to another cart.")
            }
        }
        .navigationTitle(team?.displayName ?? "Late group")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }.disabled(rows.allSatisfy { $0.name.trimmingCharacters(in: .whitespaces).isEmpty })
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let t = team {
                name = t.name
                rows = t.players.map { Row(pid: $0.id, name: $0.name, hcp: Self.num($0.hcp), index: $0.index) }
            } else { rows = [Row(pid: nil, name: "", hcp: "", index: nil)] }
        }
        .alert("Late group added", isPresented: Binding(get: { newCode != nil }, set: { if !$0 { newCode = nil; dismiss() } })) {
            Button("OK", role: .cancel) {}
        } message: { Text("Their cart code is \(newCode ?? ""). They type the tournament code and this code in the Flagcast app.") }
    }

    private func save() async {
        let players: [[String: Any]] = rows.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }.map { r in
            var p: [String: Any] = ["name": r.name.trimmingCharacters(in: .whitespaces)]
            if let id = r.pid { p["id"] = id }
            if r.index == nil { p["hcp"] = Double(r.hcp.replacingOccurrences(of: ",", with: ".")) ?? 0 }
            return p
        }
        var b: [String: Any?] = ["op": "team", "team": team?.id ?? "new", "name": name.trimmingCharacters(in: .whitespaces), "players": players]
        if team == nil { b["start"] = start }
        guard let r = await model.op(b, ok: team == nil ? nil : "Team saved") else { return }
        if team == nil { newCode = r["code"] as? String ?? "" } else { dismiss() }
    }
}

// ---- SCORES: fix any score; every fix is logged with who made it ----
struct ProScoresTab: View {
    var model: ProModel
    var s: EventState
    @State private var teamId: String?
    @State private var editing: Fix?
    struct Fix: Identifiable { var p: Player; var h: Int; var id: String { "\(p.id):\(h)" } }

    var body: some View {
        let t = s.team(teamId) ?? s.teams.first
        List {
            if let t {
                Section {
                    Picker("Team", selection: Binding(get: { t.id }, set: { teamId = $0 })) {
                        ForEach(s.teams) { Text($0.displayName).tag($0.id) }
                    }
                    ScrollView(.horizontal, showsIndicators: false) { grid(t) }
                } header: { Text("Fix a score") } footer: { Text("Tap a hole to change it. PU means picked up.") }
            } else {
                Text("No teams yet.").foregroundStyle(Color.fcMuted)
            }
            Section("Changes today") {
                if model.log.isEmpty { Text("No changes yet.").foregroundStyle(Color.fcMuted) }
                ForEach(Array(model.log.suffix(20).reversed().enumerated()), id: \.offset) { _, x in
                    let from = (x["from"] as? Int).map(String.init) ?? "–", to = (x["to"] as? Int).map(String.init) ?? "cleared"
                    Text("\(Fmt.time((x["at"] as? Double) ?? 0)) · \(x["by"] as? String ?? "") · \(x["player"] as? String ?? "") (\(x["team"] as? String ?? "")) hole \(x["h"] as? Int ?? 0): \(from) → \(to)")
                        .font(.footnote).foregroundStyle(Color.fcMuted)
                }
            }
        }
        .task { await model.loadLog() }
        .refreshable { await model.feed.refresh(); await model.loadLog() }
        .sheet(item: $editing) { f in
            if let t { ScorePad(team: t, player: f.p, hole: s.course.holes[f.h - 1]) { v in
                editing = nil
                Task {
                    if await model.op(["op": "fix", "team": t.id, "p": f.p.id, "h": f.h, "v": v.map { $0 as Any } ?? NSNull()], ok: "Score fixed") != nil { await model.loadLog() }
                }
            }
            .presentationDetents([.height(400)]) }
        }
    }

    private func grid(_ t: Team) -> some View {
        let sc = s.scores[t.id] ?? [:]
        let rows = s.format.isScramble ? [Player(id: "T", name: "Team")] : t.players
        let holes = s.course.holes.filter { Core.playHoles(s).contains($0.n) }   // only the 9 on a 9-hole round
        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                Text("Hole").fcLabel().gridColumnAlignment(.leading)
                ForEach(holes, id: \.n) { h in Text("\(h.n)").font(.caption.monospaced()).foregroundStyle(Color.fcMuted).frame(width: 38) }
            }
            GridRow {
                Text("Par").fcLabel()
                ForEach(holes, id: \.n) { h in Text("\(h.par)").font(.caption.monospaced()).foregroundStyle(Color.fcMuted) }
            }
            ForEach(rows) { p in
                GridRow {
                    Text(Fmt.firstName(p.name)).font(.subheadline.weight(.semibold)).padding(.trailing, 8)
                    ForEach(holes, id: \.n) { h in
                        let v = (sc[p.id] ?? []).count >= h.n ? sc[p.id]![h.n - 1] : nil
                        Button { editing = Fix(p: p, h: h.n) } label: {
                            Text(v == nil ? "·" : v == 0 ? "PU" : "\(v!)").font(.subheadline.monospaced())
                                .foregroundStyle(v == nil ? Color.fcLine : Color.fcInk)
                                .frame(width: 38, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(p.name) hole \(h.n), \(v == nil ? "no score" : v == 0 ? "picked up" : "\(v!)")")
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
            }
        }
        .padding(.vertical, 4)
    }
}

/// The number pad for fixing one score.
struct ScorePad: View {
    var team: Team
    var player: Player
    var hole: Hole
    var done: (Int?) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(team.displayName).fcLabel()
            Text("\(player.name) · Hole \(hole.n)").fcHeading(.title2)
            Text("Par \(hole.par)").font(.subheadline).foregroundStyle(Color.fcMuted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(1...10, id: \.self) { n in
                    Button("\(n)") { done(n) }.buttonStyle(FCButton(kind: n == hole.par ? .primary : .plain)).font(.title3.monospaced())
                }
            }
            HStack(spacing: 8) {
                Button("Picked up") { done(0) }.buttonStyle(.fcPlain)
                Button("Clear") { done(nil) }.buttonStyle(.fcDanger)
                Button("Cancel") { dismiss() }.buttonStyle(.fcPlain)
            }
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.fcCard)
    }
}

// ---- SCREENS: take over every screen, or switch one screen to a page ----
struct ProScreensTab: View {
    var model: ProModel
    var s: EventState
    @State private var text = ""
    @State private var secs = 25
    @State private var sponsor = ""
    static let pages: [(String, String)] = [("lb", "Leaderboard"), ("p3", "Par 3"), ("contests", "Contests"), ("sponsors", "Sponsors"),
                                            ("schedule", "Schedule"), ("fund", "Fundraising"), ("skins", "Skins")]

    var body: some View {
        List {
            Section {
                TextField("Announcement (for example: Awards in 10 minutes)", text: $text, axis: .vertical).lineLimit(1...3)
                HStack {
                    Button("Announcement") {
                        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { model.toast = "Type the announcement first."; return }
                        take("msg")
                    }.buttonStyle(.fc(.dark, full: true))
                    Button("Hole in one!") { take("ace") }.buttonStyle(.fc(.primary, full: true))
                }
                .listRowSeparator(.hidden)
                if !s.sponsors.isEmpty {
                    Picker("Sponsor", selection: Binding(get: { sponsor.isEmpty ? s.sponsors[0].id : sponsor }, set: { sponsor = $0 })) {
                        ForEach(s.sponsors) { Text($0.name).tag($0.id) }
                    }
                    Button("Sponsor moment") { take("sponsor") }
                }
                Stepper("For \(secs) seconds", value: $secs, in: 5...120, step: 5)
                Button("Clear and go back to playlists", role: .destructive) { take("clear") }
                if let tk = s.live.take {
                    Text("Last take-over: \(tk.kind)\((tk.text ?? "").isEmpty ? "" : " · \(tk.text!)")").font(.footnote).foregroundStyle(Color.fcMuted)
                }
            } header: { Text("Take over every screen") }
            Section("Screens") {
                if s.displays.isEmpty { Text("No screens yet. Add them in the Manager.").foregroundStyle(Color.fcMuted) }
                ForEach(s.displays) { d in screen(d) }
            }
        }
    }

    private func take(_ kind: String) {
        let sp = kind == "sponsor" ? (sponsor.isEmpty ? (s.sponsors.first?.id ?? "") : sponsor) : ""
        Task { await model.op(["op": "take", "kind": kind, "text": text, "sponsor": sp, "secs": secs], ok: kind == "clear" ? "Screens back to normal" : "On every screen") }
    }

    private func screen(_ d: Display) -> some View {
        let f = s.live.force[d.id], on = (s.online[d.id] ?? 0) > 0
        let p3 = s.course.holes.filter { $0.par == 3 }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(on ? Color.fcOK : Color.fcMuted).frame(width: 9, height: 9).accessibilityLabel(on ? "Connected" : "Not connected")
                Text(d.name).font(.headline)
                Spacer()
                Button("Back to playlist") { switchTo(d, nil) }.buttonStyle(.bordered).disabled(f == nil)
            }
            Text((f != nil ? "Showing one page" : "Playing its list" + (d.playlist.isEmpty ? "" : " (\(d.playlist.count) pages)")) + (on ? "" : " · not connected"))
                .font(.footnote).foregroundStyle(Color.fcMuted)
            FlowLayout(spacing: 6) {
                ForEach(Self.pages, id: \.0) { k, label in
                    if k == "p3" {
                        ForEach(p3, id: \.n) { h in
                            Chip(title: "Hole \(h.n) cam", on: f?.k == "p3" && f?.hole == h.n) { switchTo(d, PageRef(k: "p3", hole: h.n)) }
                        }
                    } else {
                        Chip(title: label, on: f?.k == k) { switchTo(d, PageRef(k: k)) }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func switchTo(_ d: Display, _ page: PageRef?) {
        let p: Any = page.map { ["k": $0.k, "hole": $0.hole] as [String: Any] } ?? NSNull()
        Task { await model.op(["op": "screen", "display": d.id, "page": p], ok: page == nil ? "Back to its playlist" : "Screen switched") }
    }
}

// ---- PINS: today's pin sheet (golfers see it as soon as it's set) and the contests, one tab so it fits ----
struct ProPinsTab: View {
    var model: ProModel
    var s: EventState
    @State private var part = 0
    var body: some View {
        VStack(spacing: 0) {
            Picker("Show", selection: $part) { Text("Pin sheet").tag(0); Text("Contests").tag(1) }
                .pickerStyle(.segmented).padding(.horizontal, 16).padding(.vertical, 8)
            if part == 0 { ProPinSheet(model: model, s: s) } else { ProContestsTab(model: model, s: s) }
        }
    }
}

/// Every hole: Front / Middle / Back and Left / Center / Right, paces optional. Saves as you tap (day op pinsheet).
struct ProPinSheet: View {
    var model: ProModel
    var s: EventState
    @State private var pending: [Int: PinSpot?] = [:]
    @State private var saves: [Int: Task<Void, Never>] = [:]

    private func pin(_ n: Int) -> PinSpot? { if let p = pending[n] { return p }; return s.pinsheet[n] }

    var body: some View {
        List {
            Section { EmptyView() } footer: { Text("Tap front, middle or back for each green. Golfers see the pin and the yards to it right away.") }
            ForEach(s.course.holes, id: \.n) { h in
                let p = pin(h.n)
                Section {
                    Picker("Depth", selection: Binding(get: { p?.d ?? "" }, set: { d in var q = p ?? PinSpot(); q.d = d; set(h.n, q) })) {
                        Text("Front").tag("F"); Text("Middle").tag("M"); Text("Back").tag("B")
                    }.pickerStyle(.segmented)
                    Picker("Side", selection: Binding(get: { p == nil ? "" : p!.s }, set: { x in var q = p ?? PinSpot(); q.s = x; if x == "C" { q.off = 0 }; set(h.n, q) })) {
                        Text("Left").tag("L"); Text("Center").tag("C"); Text("Right").tag("R")
                    }.pickerStyle(.segmented)
                    if let p {
                        Stepper(value: Binding(get: { p.on }, set: { v in var q = p; q.on = v; set(h.n, q, wait: true) }), in: 0...60) {
                            LabeledContent("Paces on", value: p.on > 0 ? "\(p.on)" : "—")
                        }
                        if p.s != "C" {
                            Stepper(value: Binding(get: { p.off }, set: { v in var q = p; q.off = v; set(h.n, q, wait: true) }), in: 0...30) {
                                LabeledContent("From the \(p.s == "L" ? "left" : "right")", value: p.off > 0 ? "\(p.off)" : "—")
                            }
                        }
                        Button("Take this pin off", role: .destructive) { set(h.n, nil) }
                    }
                } header: {
                    HStack {
                        Text("Hole \(h.n) · Par \(h.par)")
                        Spacer()
                        Text(p.map { [$0.label, $0.paces].filter { !$0.isEmpty }.joined(separator: " · ") } ?? "Not set")
                            .foregroundStyle(p == nil ? Color.fcMuted : Color.fcGreen)
                    }
                }
            }
        }
        .refreshable { await model.feed.refresh() }
        .onChange(of: s.pinsheet) { _, now in pending = pending.filter { n, p in now[n] != p } }
    }

    private func set(_ n: Int, _ p: PinSpot?, wait: Bool = false) {
        pending[n] = .some(p)
        saves[n]?.cancel()
        saves[n] = Task {
            if wait { try? await Task.sleep(for: .milliseconds(600)); if Task.isCancelled { return } }
            let r = await model.op(["op": "pinsheet", "hole": n, "spot": p.map { $0.json as Any } ?? NSNull()], ok: p.map { "Hole \(n): \($0.label)" } ?? "Hole \(n) cleared")
            if r == nil { pending[n] = nil }
        }
    }
}

// ---- CONTESTS: closest to the pin and long drive results ----
struct ProContestsTab: View {
    var model: ProModel
    var s: EventState
    @State private var names: [String: String] = [:]
    @State private var dists: [String: String] = [:]
    @State private var changing: (Contest, ContestEntry)?
    @State private var changeDist = ""

    var body: some View {
        let everyone = s.teams.flatMap { $0.players.map(\.name) }.filter { !$0.isEmpty }
        List {
            if s.contests.isEmpty { Text("No contests set up.").foregroundStyle(Color.fcMuted) }
            ForEach(s.contests) { c in
                Section {
                    let lead = Core.contestLeader(c)
                    if lead.isEmpty { Text("No one yet.").foregroundStyle(Color.fcMuted) }
                    // golfers' own entries: ✓ checked, ◷ waiting (OK it, or swipe to change or remove)
                    ForEach(Array(lead.prefix(10).enumerated()), id: \.offset) { i, e in
                        let flag = Core.contestFlag(c, e)
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(i + 1). \(e.name)")
                                if !flag.isEmpty { Text(flag).font(.caption).foregroundStyle(Color.fcWarn) }
                                else if e.byGolfer { Text(e.gps > 0 ? "Golfer · GPS \(Int(e.gps.rounded())) yds" : "Golfer · typed").font(.caption).foregroundStyle(Color.fcMuted) }
                            }
                            Spacer()
                            Text(Core.fmtDist(c, e.dist)).monospacedDigit()
                            if e.waiting {
                                Button("OK") { check(c, e, "ok") }.buttonStyle(.borderedProminent).tint(Color.fcOK).controlSize(.small)
                            } else if e.byGolfer { Image(systemName: "checkmark").foregroundStyle(Color.fcOK) }
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) { check(c, e, "remove") }
                            Button("Change") { changeDist = Self.plain(e.dist); changing = (c, e) }.tint(.orange)
                        }
                    }
                    HStack {
                        TextField("Player", text: Binding(get: { names[c.id] ?? "" }, set: { names[c.id] = $0 }))
                            .textInputAutocapitalization(.words)
                        Menu {
                            let typed = (names[c.id] ?? "").lowercased()
                            ForEach(everyone.filter { typed.isEmpty || $0.lowercased().contains(typed) }.prefix(40), id: \.self) { n in
                                Button(n) { names[c.id] = n }
                            }
                        } label: { Image(systemName: "person.crop.circle.badge.plus").font(.title3) }
                        .accessibilityLabel("Pick a player")
                    }
                    HStack {
                        TextField(c.isLongDrive ? "Yards" : "Feet (6.5 = 6 ft 6 in)", text: Binding(get: { dists[c.id] ?? "" }, set: { dists[c.id] = $0 }))
                            .keyboardType(.decimalPad).font(.body.monospaced())
                        Button("Post") { post(c) }.buttonStyle(.borderedProminent).tint(Color.fcGreen)
                    }
                } header: {
                    Text("\(c.isLongDrive ? "Long drive" : "Closest to the pin") · Hole \(c.hole)")
                } footer: { if !c.sponsor.isEmpty { Text(c.sponsor) } }
            }
        }
        .refreshable { await model.feed.refresh() }
        .alert(changing.map { "\($0.1.name): the right distance" } ?? "", isPresented: Binding(get: { changing != nil }, set: { if !$0 { changing = nil } })) {
            TextField(changing?.0.isLongDrive == true ? "Yards" : "Feet (6.5 = 6 ft 6 in)", text: $changeDist).keyboardType(.decimalPad)
            Button("Save") {
                if let x = changing, let d = Double(changeDist.replacingOccurrences(of: ",", with: ".")), d > 0 {
                    Task { _ = await model.op(["op": "check", "id": x.0.id, "name": x.1.name, "do": "change", "dist": d], ok: "Changed and checked") }
                }
                changing = nil
            }
            Button("Cancel", role: .cancel) { changing = nil }
        }
    }

    static func plain(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(format: "%.2f", d) }
    private func check(_ c: Contest, _ e: ContestEntry, _ what: String) {
        Task { _ = await model.op(["op": "check", "id": c.id, "name": e.name, "do": what], ok: what == "remove" ? "Taken off" : "Checked") }
    }

    private func post(_ c: Contest) {
        let name = (names[c.id] ?? "").trimmingCharacters(in: .whitespaces)
        let dist = Double((dists[c.id] ?? "").replacingOccurrences(of: ",", with: ".")) ?? 0
        guard !name.isEmpty, dist > 0 else { model.toast = "Type the player and the distance."; return }
        Task {
            if await model.op(["op": "ctp", "id": c.id, "name": name, "dist": dist], ok: "Posted") != nil { names[c.id] = ""; dists[c.id] = "" }
        }
    }
}

// ---- REPLAYS: right after a great shot, save a replay (the hole's camera from 25 s back, or a clip link) ----
struct ProReplaysTab: View {
    var model: ProModel
    var s: EventState
    @State private var hole = 0
    @State private var label = ""
    @State private var clip = ""
    @State private var screens = false
    @State private var removing: Replay?

    var body: some View {
        let pro = model.role == "pro"
        // par 3s first, then the rest
        let holes = s.course.holes.filter { $0.par == 3 } + s.course.holes.filter { $0.par != 3 }
        List {
            Section {
                Picker("Hole", selection: Binding(get: { hole == 0 ? (holes.first?.n ?? 1) : hole }, set: { hole = $0 })) {
                    ForEach(holes, id: \.n) { h in Text("Hole \(h.n) · par \(h.par)\(s.cams[h.n] != nil ? " · camera" : "")").tag(h.n) }
                }
                TextField("What happened (for example: Ana’s tee shot)", text: $label)
                    .onChange(of: label) { _, v in if v.count > 80 { label = String(v.prefix(80)) } }
                TextField("Clip link (optional, https://…)", text: $clip).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                if pro { Toggle("Show it on every screen now", isOn: $screens) }
                Button { save(holes) } label: { Label("Save replay", systemImage: "arrow.counterclockwise.circle.fill") }
                    .buttonStyle(.fcPrimary).listRowSeparator(.hidden)
                    .disabled(model.busy)
            } header: { Text("Save replay") } footer: {
                Text("Right after a great shot, tap Save replay. Players can watch it on their phones\(pro ? ", and you can put it on every screen" : ""). It replays the hole’s camera from 25 seconds back, or paste a clip link instead.")
            }
            Section("Replays") {
                if s.replays.isEmpty { Text("No replays yet.").foregroundStyle(Color.fcMuted) }
                ForEach(s.replays.prefix(12)) { r in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.label.isEmpty ? "Replay" : r.label).font(.body.weight(.semibold))
                            Text("Hole \(r.hole) · \(Fmt.time(r.at))\(r.isClip ? " · clip" : "")\(r.by.isEmpty ? "" : " · \(r.by)")").font(.caption).foregroundStyle(Color.fcMuted)
                        }
                        Spacer()
                        if pro {
                            Button("On screens") { Task { await model.op(["op": "take", "kind": "replay", "replay": r.id], ok: "Replay on the screens") } }
                                .buttonStyle(.bordered).tint(Color.fcGreen2)
                            Button(role: .destructive) { removing = r } label: { Image(systemName: "trash") }
                                .buttonStyle(.bordered).accessibilityLabel("Remove")
                        }
                    }
                }
            }
        }
        .confirmationDialog("Remove this replay?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) { if let r = removing { Task { await model.op(["op": "replay", "remove": r.id], ok: "Removed") } } }
        }
    }

    private func save(_ holes: [Hole]) {
        let h = hole == 0 ? (holes.first?.n ?? 1) : hole
        let url = clip.trimmingCharacters(in: .whitespaces)
        if !url.isEmpty && !url.hasPrefix("https://") { model.toast = "The clip link must start with https://"; return }
        Task {
            let r = await model.op(["op": "replay", "hole": h, "label": label.trimmingCharacters(in: .whitespaces), "url": url, "screens": screens && model.role == "pro"],
                                   ok: screens ? "Replay on the screens" : "Replay saved")
            if r != nil { label = ""; clip = ""; screens = false }
        }
    }
}
