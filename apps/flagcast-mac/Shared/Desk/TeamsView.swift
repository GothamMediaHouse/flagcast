import SwiftUI

/// Teams (design/Teams.dc.html): photo header with the counts, flight filter and Add team; the teams as a raised
/// table card, and the selected team in a card with its starting hole pictured.
struct TeamsView: View {
    @Bindable var doc: DeskDoc
    @Environment(DeskNav.self) private var nav
    @State private var selection: String?
    @State private var flight = ""
    @State private var pasting = false
    @State private var printing = false
    @State private var pairing = false

    private var shown: [DeskTeam] {
        let q = nav.search.trimmingCharacters(in: .whitespaces).lowercased()
        return doc.ev.teams.filter { t in
            (flight.isEmpty || t.flight == flight) &&
            (q.isEmpty || t.displayName.lowercased().contains(q) || t.code.lowercased().contains(q) || t.players.contains { $0.name.lowercased().contains(q) })
        }
    }
    private var scramble: Bool { doc.ev.format.isScramble }
    private var counts: String {
        let p = doc.ev.teams.reduce(0) { $0 + $1.players.count }, f = Set(doc.ev.teams.map(\.flight).filter { !$0.isEmpty }).count
        return "\(doc.ev.teams.count) team\(doc.ev.teams.count == 1 ? "" : "s") · \(p) player\(p == 1 ? "" : "s")" + (f > 0 ? " · \(f) flight\(f == 1 ? "" : "s")" : "")
    }

    var body: some View {
        DeskPage(doc: doc, section: .teams, height: 200, titleHeight: 92) {
            if !doc.ev.flights.isEmpty {
                FlightPicker(flights: doc.ev.flights, flight: $flight)
            }
            if doc.ev.format.isMatch {
                Button { pairing = true } label: { Label("Matches (\(doc.ev.matches.count))", systemImage: "person.2.badge.gearshape") }.buttonStyle(GlassButton())
            }
            Button("Import from a spreadsheet") { pasting = true }.buttonStyle(GlassButton())
            Button { printing = true } label: { Label("Cart cards", systemImage: "printer") }.buttonStyle(GlassButton())
            Button { add() } label: { Label("Add team", systemImage: "plus") }.buttonStyle(GlassButton()).keyboardShortcut("t", modifiers: [.command, .shift])
        } title: {
            HeroTitle(title: "Teams", size: 52, sub: counts, subBeside: true, help: "teams")
        } content: {
            HStack(alignment: .top, spacing: 16) {
                table
                inspector.frame(width: compact ? 300 : 340)
            }
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { areaWidth = $0 }
            .padding(.horizontal, 20).padding(.bottom, 18)
        }
        .sheet(isPresented: $pasting) { PasteTeamsSheet(doc: doc) }
        .sheet(isPresented: $printing) { CartCardsSheet(doc: doc) }
        .sheet(isPresented: $pairing) { MatchesSheet(doc: doc) }
        .onAppear { if selection == nil { selection = shown.first?.id } }
    }

    // ---- the table ----
    // in a narrow window the handicap and cart columns step aside so the team names keep their room
    @State private var areaWidth: CGFloat = 0
    private var compact: Bool { areaWidth > 0 && areaWidth < 980 }
    private let cols: [GridItem] = []
    private var table: some View {
        VStack(spacing: 0) {
            row(header: true, n: "#", name: "TEAM", players: "", flight: "FLIGHT", hcp: "HCP", cart: "CART", start: "STARTS", status: ("CARD", FC.muted))
                .background(FC.head)
            Divider().overlay(FC.paper2)
            if shown.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.2").font(.system(size: 30)).foregroundStyle(FC.muted)
                    Text(doc.ev.teams.isEmpty ? "No teams yet" : "No team matches").font(.headline)
                    Text(doc.ev.teams.isEmpty ? "Add a team, or import them from a spreadsheet." : "Try another name or flight.").font(.callout).foregroundStyle(FC.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 240)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, t in
                        let on = selection == t.id
                        row(header: false, n: "\(i + 1)", name: t.displayName.isEmpty ? "New team" : t.displayName, players: t.players.map(\.name).joined(separator: " · "),
                            flight: t.flight.isEmpty ? "–" : t.flight, hcp: hcpText(t), cart: t.cart.isEmpty ? "–" : t.cart, start: "Hole \(t.start)", status: status(t), on: on)
                            .background(on ? FC.green : FC.card)
                            .contentShape(Rectangle())
                            .onTapGesture { selection = t.id }
                            .contextMenu { Button("Remove Team", role: .destructive) { remove(t.id) } }
                        Divider().overlay(FC.hairline)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FC.line))
        .background(FC.card, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: FC.scrim.opacity(0.18), radius: 15, y: 8)
        .onDeleteCommand { if let s = selection { remove(s) } }
    }
    private func row(header: Bool, n: String, name: String, players: String, flight: String, hcp: String, cart: String, start: String, status: (String, Color), on: Bool = false) -> some View {
        let fg: Color = on ? FC.onGreen : FC.ink, dim: Color = on ? FC.onGreenMuted : FC.muted
        let hf = Font.system(size: 11, weight: .bold)
        return HStack(spacing: 12) {
            Text(n).font(header ? hf : .system(size: 13, weight: .bold)).foregroundStyle(dim).frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(header ? hf : .system(size: 13, weight: .semibold)).foregroundStyle(header ? dim : fg).lineLimit(1)
                if !header && !players.isEmpty { Text(players).font(.system(size: 11)).foregroundStyle(dim).lineLimit(1) }
            }
            .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
            Group {
                Text(flight).frame(width: 54, alignment: .leading)
                if !compact {
                    Text(hcp).frame(width: 54, alignment: .leading)
                    Text(cart).frame(width: 60, alignment: .leading)
                }
                Text(start).frame(width: 66, alignment: .leading)
            }
            .font(header ? hf : .system(size: 13)).foregroundStyle(header ? dim : fg)
            HStack(spacing: 6) {
                if !header { Circle().fill(status.1).frame(width: 7, height: 7) }
                Text(status.0).font(header ? hf : .system(size: 13, weight: .semibold)).foregroundStyle(header ? dim : (on ? FC.onGreen : status.1))
            }
            .frame(width: 110, alignment: .leading)
        }
        .tracking(header ? 0.8 : 0)
        .padding(.horizontal, 16).frame(height: header ? 34 : 46)
    }
    private func hcpText(_ t: DeskTeam) -> String {
        if scramble { return "\(Int(t.hcp))" }
        // the team's average course handicap (each player's is in the card on the right)
        return t.players.isEmpty ? "–" : String(format: "%.1f", t.players.reduce(0) { $0 + $1.hcp } / Double(t.players.count))
    }
    private func status(_ t: DeskTeam) -> (String, Color) {
        if t.code.isEmpty { return ("After save", FC.muted) }
        let s = doc.live?.scores[t.id] ?? [:]
        let done = doc.ev.playHoles.filter { h in !s.isEmpty && s.values.allSatisfy { h - 1 < $0.count && $0[h - 1] != nil } }.count
        if done == doc.ev.playHoles.count { return ("Finished", FC.muted) }
        if done > 0 { return ("Thru \(done)", FC.ok) }
        return ("Not started", FC.muted)
    }

    // ---- the inspector card ----
    @ViewBuilder private var inspector: some View {
        if let id = selection, let i = doc.ev.teams.firstIndex(where: { $0.id == id }) {
            let t = doc.ev.teams[i]
            VStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    HolePicture(id: doc.id, n: t.start, h: doc.ev.map.holes[t.start], fallback: doc.picture.image)
                    LinearGradient(colors: [Color(hex: 0x0b2219).opacity(0.9), Color(hex: 0x0b2219).opacity(0.1)], startPoint: .bottom, endPoint: .init(x: 0.5, y: 0.25))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(["TEAM \((doc.ev.teams.firstIndex { $0.id == t.id } ?? 0) + 1)", t.flight.isEmpty ? nil : "FLIGHT \(t.flight)", t.cart.isEmpty ? nil : "CART \(t.cart)"].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(FC.flag)
                        Text(t.displayName.isEmpty ? "New team" : t.displayName).font(FC.display(30)).foregroundStyle(FC.onGreen).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .padding(.horizontal, 18).padding(.bottom, 12)
                }
                .frame(height: 150).clipped()
                TeamEditor(team: $doc.ev.teams[i], tees: doc.ev.course.tees, par: doc.ev.course.par, scramble: scramble, flights: doc.ev.flights,
                           cup: doc.ev.format.isMatch && doc.ev.format.cup.on ? doc.ev.format.cup : nil)
                    .scrollContentBackground(.hidden)
                HStack {
                    Button(role: .destructive) { remove(t.id) } label: { Label("Remove", systemImage: "trash") }.buttonStyle(PlainCardButton())
                    Spacer()
                    if !t.code.isEmpty { Button("Open scorecard") { NSWorkspace.shared.open(doc.cartURL(t.code)) }.buttonStyle(GreenButton()) }
                }
                .padding(14)
            }
            .background(FC.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: FC.scrim.opacity(0.18), radius: 15, y: 8)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 30)).foregroundStyle(FC.muted)
                Text("Pick a team").font(.headline)
                Text("Its players, GHIN numbers and tees show here.").font(.callout).foregroundStyle(FC.muted).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 260).raisedCard(padding: 16)
        }
    }

    private func add() {
        let t = DeskTeam(flight: flight.isEmpty ? (doc.ev.flights.first ?? "") : flight, start: 1, players: [DeskPlayer()])
        doc.ev.teams.append(t); selection = t.id; nav.search = ""
    }
    private func remove(_ id: String) { doc.ev.teams.removeAll { $0.id == id }; if selection == id { selection = shown.first?.id } }
}

/// The selected team: name, flight, start, and up to four players with GHIN numbers, Index, tees and course handicap.
struct TeamEditor: View {
    @Binding var team: DeskTeam
    var tees: [Tee], par: Int, scramble: Bool, flights: [String]
    /// match play's team cup, when it's on: the team picks a side
    var cup: Cup? = nil

    var body: some View {
        Form {
            SwiftUI.Section("Team") {
                TextField("Name", text: $team.name, prompt: Text("Uses the last names"))
                if flights.isEmpty { TextField("Flight", text: $team.flight) }
                else { Picker("Flight", selection: $team.flight) { Text("None").tag(""); ForEach(flights, id: \.self) { Text($0).tag($0) } } }
                Stepper("Starts on hole \(team.start)", value: $team.start, in: 1...18)
                if let cup { Picker("Side", selection: $team.side) { Text("None").tag(""); Text(cup.a).tag("A"); Text(cup.b).tag("B") } }
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

/// Match play pairings: who plays who. Pair in order, draw at random, or set each match by hand.
struct MatchesSheet: View {
    @Bindable var doc: DeskDoc
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Matches").font(.title2.bold())
            Text("Who plays who. Put both sides of a match on the same cart code, or the same start hole, so they play together. Strokes come off the lowest player in each match.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Pair in Order") { doc.ev.pairUp(random: false) }
                Button("Draw at Random") { doc.ev.pairUp(random: true) }
                Button { doc.ev.matches.append(MatchPair()) } label: { Label("Add Match", systemImage: "plus") }
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach($doc.ev.matches) { $m in
                        HStack(spacing: 8) {
                            Text("\((doc.ev.matches.firstIndex { $0.id == m.id } ?? 0) + 1)").font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 22)
                            picker($m.a)
                            Text("v").foregroundStyle(.secondary)
                            picker($m.b)
                            Text(doc.ev.teams.first { $0.id == m.a }.map { "Hole \($0.start)" } ?? "").font(.callout).foregroundStyle(.secondary).frame(width: 60)
                            Button(role: .destructive) { doc.ev.matches.removeAll { $0.id == m.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                        }
                    }
                    if doc.ev.matches.isEmpty { Text("No matches yet. Pair in Order makes them from the teams list.").foregroundStyle(.secondary).padding(.vertical, 20) }
                }
            }
            .frame(minHeight: 260)
            HStack {
                let left = doc.ev.unpaired
                Text(left.isEmpty ? "Every team is in a match." : "Not in a match yet: \(left.prefix(6).map(\.shortName).joined(separator: ", "))\(left.count > 6 ? "…" : "")")
                    .foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 640, height: 520)
    }
    private func picker(_ id: Binding<String>) -> some View {
        Picker("", selection: id) {
            Text("Pick a team").tag("")
            ForEach(doc.ev.teams) { t in
                Text((doc.ev.format.cup.on && !t.side.isEmpty ? (t.side == "A" ? "● " : "○ ") : "") + (t.shortName.isEmpty ? "New team" : t.shortName)).tag(t.id)
            }
        }
        .labelsHidden().frame(maxWidth: .infinity)
    }
}

/// The flight filter over the photo.
struct FlightPicker: View {
    let flights: [String]
    @Binding var flight: String
    var body: some View { PhotoSegments(options: [("All", "")] + flights.map { ($0, $0) }, selection: $flight) }
}

/// A switch over the photo: a light segmented control (white 85%), the picked one solid green.
struct PhotoSegments: View {
    let options: [(String, String)]
    @Binding var selection: String
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.1) { o in
                let on = selection == o.1
                Button { selection = o.1 } label: {
                    Text(o.0).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 11).frame(height: 26)
                        .foregroundStyle(on ? FC.onGreen : FC.green)
                        .background(on ? FC.green : .clear, in: RoundedRectangle(cornerRadius: 6)).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2).background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 7))
    }
}
