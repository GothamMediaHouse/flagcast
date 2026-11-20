import SwiftUI

/// Teams: a table of every team, and an inspector for the selected one's players.
struct TeamsView: View {
    @Bindable var doc: DeskDoc
    @State private var selection = Set<String>()
    @State private var search = ""
    @State private var pasting = false
    @State private var printing = false
    @State private var sort = [KeyPathComparator(\DeskTeam.start)]

    private var shown: [DeskTeam] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let list = q.isEmpty ? doc.ev.teams : doc.ev.teams.filter { t in
            t.displayName.lowercased().contains(q) || t.code.lowercased().contains(q) || t.players.contains { $0.name.lowercased().contains(q) } || t.flight.lowercased() == q
        }
        return list.sorted(using: sort)
    }
    private var scramble: Bool { doc.ev.format.isScramble }

    var body: some View {
        Table(shown, selection: $selection, sortOrder: $sort) {
            TableColumn("Team", value: \.name) { t in
                Text(t.displayName.isEmpty ? "New team" : t.displayName).foregroundStyle(t.displayName.isEmpty ? .secondary : .primary)
            }.width(min: 140, ideal: 220)
            TableColumn("Flight", value: \.flight) { t in Text(t.flight) }.width(50)
            TableColumn("Start", value: \.start) { t in Text("\(t.start)").monospacedDigit() }.width(44)
            TableColumn("Players") { t in
                Text(t.players.map { "\($0.name) (\(hcpText($0)))" }.joined(separator: ", ")).foregroundStyle(.secondary).lineLimit(1)
            }.width(min: 200, ideal: 380)
            TableColumn("Cart code", value: \.code) { t in Text(t.code.isEmpty ? "After save" : t.code).font(.body.monospaced()).foregroundStyle(t.code.isEmpty ? .tertiary : .primary) }.width(80)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            Button("Remove \(ids.count == 1 ? "Team" : "\(ids.count) Teams")", role: .destructive) { remove(ids) }.disabled(ids.isEmpty)
        }
        .onDeleteCommand { remove(selection) }
        .searchable(text: $search, placement: .toolbar, prompt: "Find a team or player")
        .inspector(isPresented: .constant(true)) {
            if selection.count == 1, let i = doc.ev.teams.firstIndex(where: { $0.id == selection.first }) {
                TeamEditor(team: $doc.ev.teams[i], tees: doc.ev.course.tees, par: doc.ev.course.par, scramble: scramble, flights: doc.ev.flights)
                    .inspectorColumnWidth(min: 340, ideal: 400, max: 520)
            } else {
                ContentUnavailableView(selection.isEmpty ? "Select a team" : "\(selection.count) teams selected", systemImage: "person.3",
                                       description: Text("\(doc.ev.teams.count) team\(doc.ev.teams.count == 1 ? "" : "s") · \(doc.ev.teams.reduce(0) { $0 + $1.players.count }) players"))
                    .inspectorColumnWidth(min: 340, ideal: 400, max: 520)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { add() } label: { Label("Add Team", systemImage: "plus") }.keyboardShortcut("t", modifiers: [.command, .shift]).help("Add a team (⇧⌘T)")
                Button { remove(selection) } label: { Label("Remove", systemImage: "minus") }.disabled(selection.isEmpty).help("Remove the selected teams (⌫)")
                Button { pasting = true } label: { Label("Paste from a Spreadsheet", systemImage: "tablecells.badge.ellipsis") }.help("Add teams copied from Excel or Google Sheets")
                Button { printing = true } label: { Label("Print Cart Cards", systemImage: "printer") }.help("One card per team with its QR code")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if doc.ev.teams.contains(where: { $0.code.isEmpty }) && doc.dirty {
                Text("New teams get their cart code and QR card when you save (⌘S).").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(8).background(.bar)
            }
        }
        .sheet(isPresented: $pasting) { PasteTeamsSheet(doc: doc) }
        .sheet(isPresented: $printing) { CartCardsSheet(doc: doc) }
    }

    private func hcpText(_ p: DeskPlayer) -> String { p.index != nil ? "\(Int(p.hcp)) · \(Core.fmtIndex(p.index))" : "\(Int(p.hcp))" }
    private func add() {
        let t = DeskTeam(flight: doc.ev.flights.first ?? "", start: 1, players: [DeskPlayer()])
        doc.ev.teams.append(t); selection = [t.id]; search = ""
    }
    private func remove(_ ids: Set<String>) { doc.ev.teams.removeAll { ids.contains($0.id) }; selection = [] }
}

/// The selected team: name, flight, start, and up to four players with GHIN numbers, Index, tees and course handicap.
struct TeamEditor: View {
    @Binding var team: DeskTeam
    var tees: [Tee], par: Int, scramble: Bool, flights: [String]

    var body: some View {
        Form {
            SwiftUI.Section("Team") {
                TextField("Name", text: $team.name, prompt: Text("Uses the last names"))
                if flights.isEmpty { TextField("Flight", text: $team.flight) }
                else { Picker("Flight", selection: $team.flight) { Text("None").tag(""); ForEach(flights, id: \.self) { Text($0).tag($0) } } }
                Stepper("Starts on hole \(team.start)", value: $team.start, in: 1...18)
                if scramble { LabeledContent("Team handicap") { TextField("", value: $team.hcp, format: .number).frame(width: 70).multilineTextAlignment(.trailing) } }
                TextField("Cart", text: $team.cart, prompt: Text("Cart number (optional)"))
                if !team.code.isEmpty { LabeledContent("Cart code") { Text(team.code).font(.body.monospaced()).textSelection(.enabled) } }
            }
            ForEach($team.players) { $p in
                SwiftUI.Section {
                    TextField("Name", text: $p.name)
                    TextField("GHIN number", text: Binding(get: { p.ghin }, set: { p.ghin = String($0.filter(\.isNumber).prefix(11)) }))
                    TextField("Handicap Index", text: Binding(get: { Core.fmtIndex(p.index) }, set: { p.index = Hcp.parseIndex($0); recalc(&p) }), prompt: Text("e.g. 8.4 or +1.2"))
                    if !tees.isEmpty {
                        Picker("Tees", selection: Binding(get: { p.tee.isEmpty ? tees[0].id : p.tee }, set: { p.tee = $0; recalc(&p) })) { ForEach(tees) { Text($0.name).tag($0.id) } }
                    }
                    if let ch = Hcp.course(p.index, tee(p), par: par) {
                        LabeledContent("Course handicap") { Text("\(ch)").monospacedDigit().fontWeight(.semibold) }
                    } else {
                        LabeledContent("Course handicap") { TextField("", value: $p.hcp, format: .number).frame(width: 70).multilineTextAlignment(.trailing) }
                    }
                    Toggle("Guest", isOn: $p.guest)
                } header: {
                    HStack { Text("Player \((team.players.firstIndex { $0.id == p.id } ?? 0) + 1)"); Spacer()
                        Button(role: .destructive) { team.players.removeAll { $0.id == p.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).help("Remove this player") }
                }
            }
            if team.players.count < 4 {
                Button { team.players.append(DeskPlayer()) } label: { Label("Add Player", systemImage: "plus") }
            }
            Help("Type a player’s Handicap Index (use + for plus handicaps, like +1.2) and pick their tees to have the course handicap worked out. Or leave Index empty and type the course handicap yourself.")
        }
        .formStyle(.grouped)
    }
    private func tee(_ p: DeskPlayer) -> Tee? { tees.first { $0.id == p.tee } ?? tees.first }
    private func recalc(_ p: inout DeskPlayer) { if let ch = Hcp.course(p.index, tee(p), par: par) { p.hcp = Double(ch); if p.tee.isEmpty { p.tee = tees.first?.id ?? "" } } }
}

/// Paste rows from a spreadsheet: Team name, Flight, Start hole, Player 1, Handicap 1, Player 2, Handicap 2…
struct PasteTeamsSheet: View {
    @Bindable var doc: DeskDoc
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    private var parsed: [DeskTeam] {
        text.split(whereSeparator: \.isNewline).compactMap { line -> DeskTeam? in
            let c = line.contains("\t") ? line.split(separator: "\t", omittingEmptySubsequences: false) : line.split(separator: ",", omittingEmptySubsequences: false)
            let f = c.map { $0.trimmingCharacters(in: .whitespaces) }
            guard f.count >= 4 else { return nil }
            var players: [DeskPlayer] = []
            var k = 3
            while k < f.count, players.count < 4 {
                if !f[k].isEmpty { players.append(DeskPlayer(name: f[k], hcp: k + 1 < f.count ? Double(f[k + 1]) ?? 0 : 0)) }
                k += 2
            }
            return players.isEmpty ? nil : DeskTeam(name: f[0], flight: f[1], start: min(18, max(1, Int(f[2]) ?? 1)), players: players)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paste teams").font(.title2.bold())
            Text("One team per line, columns split by tabs or commas: Team name, Flight, Start hole, Player 1, Handicap 1, Player 2, Handicap 2, and so on (up to 4 players). Copy the rows straight out of Excel or Google Sheets.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $text).font(.body.monospaced()).frame(minHeight: 200).overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            HStack {
                Text(parsed.isEmpty ? "" : "\(parsed.count) team\(parsed.count == 1 ? "" : "s"), \(parsed.reduce(0) { $0 + $1.players.count }) players").foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add These Teams") { doc.ev.teams += parsed; dismiss() }.keyboardShortcut(.defaultAction).disabled(parsed.isEmpty)
            }
        }
        .padding(20).frame(width: 620)
    }
}
