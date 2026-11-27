import SwiftUI

/// Teams: every team as a card (players, flight, starting hole, its scorecard link). Tap one to change it; add teams.
/// Changes are saved with Save.
struct TeamsView: View {
    var body: some View {
        WithTournament { doc in TeamsPage(doc: doc) }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { TournamentMenu() } }
    }
}

private struct TeamsPage: View {
    @Bindable var doc: DeskDoc
    @State private var search = ""
    @State private var flight = ""
    @State private var editing: String?

    private var teams: [DeskTeam] {
        let q = search.lowercased()
        return doc.ev.teams.filter { t in (flight.isEmpty || t.flight == flight) && (q.isEmpty || t.displayName.lowercased().contains(q) || t.players.contains { $0.name.lowercased().contains(q) }) }
    }

    var body: some View {
        PhotoPage(image: doc.picture.image, title: "Teams",
                  sub: "\(doc.ev.teams.count) teams · \(doc.ev.teams.reduce(0) { $0 + $1.players.count }) players" + (doc.ev.flights.count > 1 ? " · \(doc.ev.flights.count) flights" : ""), height: 230) {
            Button { addTeam() } label: { Label("Add team", systemImage: "plus") }.buttonStyle(WhiteButton())
        } content: {
            // a search box in the page (the system one sat on top of the photo header's words)
            if doc.ev.teams.count > 6 { BoxField(placeholder: "Find a team or player", text: $search) }
            if doc.ev.flights.count > 1 {
                // the Mac's flight control
                Picker("Flight", selection: $flight) { Text("All").tag(""); ForEach(doc.ev.flights, id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
            }
            if doc.ev.teams.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.3").font(.system(size: 34)).foregroundStyle(FC.muted)
                    Text("No teams yet").font(FC.display(28))
                    Text("Add each team or cart. Players can be added now or later.").font(.subheadline).foregroundStyle(FC.muted).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).card(padding: 24)
            }
            if !teams.isEmpty {
                // one table card, like the Mac's: starting hole, team and players, flight
                VStack(spacing: 0) {
                    ForEach(Array(teams.enumerated()), id: \.element.id) { i, t in
                        Button { editing = t.id } label: { TeamRow(team: t, last: i == teams.count - 1) }.buttonStyle(.plain)
                    }
                }
                .background(FC.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(FC.line))
                Help("Tap a team for its players, GHIN, handicaps, starting hole, scorer and PIN.")
            }
            if doc.ev.format.isMatch { MatchesCard(doc: doc) }
        }
        .sheet(item: Binding(get: { editing.map { EditID(id: $0) } }, set: { editing = $0?.id })) { e in
            if let i = doc.ev.teams.firstIndex(where: { $0.id == e.id }) {
                NavigationStack { TeamEditor(team: $doc.ev.teams[i], doc: doc, remove: { doc.ev.teams.removeAll { $0.id == e.id }; editing = nil }) }
            }
        }
    }
    private func addTeam() {
        let t = DeskTeam(name: "", flight: flight.isEmpty ? (doc.ev.flights.first ?? "") : flight, start: 1, players: [DeskPlayer(), DeskPlayer()])
        doc.ev.teams.append(t); editing = t.id
    }
    private func chip(_ t: String, on: Bool, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).font(.subheadline.weight(.semibold)).padding(.horizontal, 12).frame(minHeight: 34)
                .foregroundStyle(on ? FC.onGreen : FC.ink).background(on ? FC.green : FC.card, in: Capsule())
                .overlay(Capsule().stroke(on ? .clear : FC.line))
        }
        .buttonStyle(.plain)
    }
}

struct EditID: Identifiable { var id: String }

/// Match play pairings: who plays who (Pair in order, Draw at random, or each match by hand). Saved with Save.
private struct MatchesCard: View {
    @Bindable var doc: DeskDoc
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Matches").font(.system(size: 15, weight: .bold))
                Spacer()
                Menu {
                    Button("Pair in Order") { doc.ev.pairUp(random: false) }
                    Button("Draw at Random") { doc.ev.pairUp(random: true) }
                    Button { doc.ev.matches.append(MatchPair()) } label: { Label("Add a Match", systemImage: "plus") }
                } label: { Label("Pair", systemImage: "person.2") }
            }
            if doc.ev.matches.isEmpty {
                Text("No matches yet. Pair in Order makes them from the teams list.").font(.callout).foregroundStyle(FC.muted)
            }
            ForEach($doc.ev.matches) { $m in
                HStack(spacing: 6) {
                    Text("\((doc.ev.matches.firstIndex { $0.id == m.id } ?? 0) + 1)").font(.footnote.monospacedDigit()).foregroundStyle(FC.muted).frame(width: 20)
                    pick($m.a)
                    Text("v").foregroundStyle(FC.muted)
                    pick($m.b)
                    Button(role: .destructive) { doc.ev.matches.removeAll { $0.id == m.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
            let left = doc.ev.unpaired
            if !left.isEmpty && !doc.ev.matches.isEmpty {
                Text("Not in a match yet: \(left.prefix(6).map(\.shortName).joined(separator: ", "))\(left.count > 6 ? "…" : "")").font(.footnote).foregroundStyle(FC.muted)
            }
            Help("Put both sides of a match on the same cart code, or the same start hole. Strokes come off the lowest player in each match.")
        }
        .padding(14)
        .background(FC.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FC.line))
    }
    private func pick(_ id: Binding<String>) -> some View {
        Picker("", selection: id) {
            Text("Pick a team").tag("")
            ForEach(doc.ev.teams) { t in Text(t.shortName.isEmpty ? "New team" : t.shortName).tag(t.id) }
        }
        .labelsHidden().frame(maxWidth: .infinity)
    }
}

/// A row of the Teams table: the starting hole in a tile, the team and its players, the flight.
struct TeamRow: View {
    let team: DeskTeam
    var last = false
    var body: some View {
        HStack(spacing: 12) {
            Text("\(team.start)").font(FC.display(18)).foregroundStyle(FC.green)
                .frame(width: 32, height: 32).background(Color(uiColor: GreenBars.cream), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(team.displayName.isEmpty ? "New team" : team.displayName).font(.system(size: 15, weight: .semibold)).foregroundStyle(FC.ink).lineLimit(1)
                Text(team.players.isEmpty ? "No players yet" : team.players.map { $0.name.isEmpty ? "Player" : $0.name }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(FC.muted).lineLimit(1)
            }
            Spacer(minLength: 6)
            if !team.flight.isEmpty { Text("Flight \(team.flight)").font(.caption.weight(.semibold)).foregroundStyle(FC.muted) }
            Chevron()
        }
        .padding(.horizontal, 14).frame(minHeight: 58)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(FC.hairline).frame(height: 1).padding(.leading, 58) } }
    }
}

struct TeamCard: View {
    let team: DeskTeam
    let doc: DeskDoc
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(team.displayName.isEmpty ? "New team" : team.displayName).font(.headline).foregroundStyle(FC.ink)
                Text(team.players.map { $0.name.isEmpty ? "Player" : "\($0.name) \(fmtHcp($0.hcp))" }.joined(separator: " · ")).font(.subheadline).foregroundStyle(FC.muted).lineLimit(2)
                HStack(spacing: 6) {
                    if !team.flight.isEmpty { pill("Flight \(team.flight)") }
                    pill("Starts on \(team.start)")
                    if !team.cart.isEmpty { pill("Cart \(team.cart)") }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(FC.muted)
        }
        .card()
    }
    private func pill(_ t: String) -> some View { Text(t).font(.caption.weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 3).background(FC.paper2, in: Capsule()).foregroundStyle(FC.muted) }
}

func fmtHcp(_ h: Double) -> String { h == h.rounded() ? "\(Int(h))" : String(format: "%.1f", h) }

/// One team: name, flight, starting hole, cart, players and handicaps, its scorecard link.
struct TeamEditor: View {
    @Binding var team: DeskTeam
    let doc: DeskDoc
    var remove: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirm = false
    var body: some View {
        Form {
            SwiftUI.Section("Team") {
                TextField("Team name (optional)", text: $team.name)
                if !doc.ev.flights.isEmpty {
                    Picker("Flight", selection: $team.flight) { Text("None").tag(""); ForEach(doc.ev.flights, id: \.self) { Text("Flight \($0)").tag($0) } }
                }
                Stepper("Starts on hole \(team.start)", value: $team.start, in: 1...18)
                if doc.ev.format.isMatch && doc.ev.format.cup.on {
                    Picker("Side", selection: $team.side) { Text("None").tag(""); Text(doc.ev.format.cup.a).tag("A"); Text(doc.ev.format.cup.b).tag("B") }
                }
                if doc.ev.format.isScramble { LabeledContent("Team handicap") { TextField("", value: $team.hcp, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 70) } }
                TextField("Cart number", text: $team.cart)
            }
            SwiftUI.Section {
                ForEach($team.players) { $p in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Player name", text: $p.name).textContentType(.name)
                            // worked out from Index and tees when there's an Index, else typed (as on the Mac)
                            if let ch = Hcp.course(p.index, tee(p), par: doc.ev.course.par) {
                                Text("\(ch)").monospacedDigit().fontWeight(.semibold)
                            } else {
                                TextField("Hcp", value: $p.hcp, format: .number.precision(.fractionLength(0...1))).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 60)
                            }
                        }
                        HStack(spacing: 8) {
                            Text("Index").foregroundStyle(FC.muted)
                            TextField("e.g. 8.4", text: Binding(get: { Core.fmtIndex(p.index) }, set: { p.index = Hcp.parseIndex($0); recalc(&p) }))
                                .keyboardType(.numbersAndPunctuation).frame(width: 70)
                            Spacer()
                            if !tees.isEmpty {
                                Picker("Tees", selection: Binding(get: { tee(p)?.id ?? "" }, set: { p.tee = $0; recalc(&p) })) {
                                    ForEach(tees) { Text("\($0.name) tees").tag($0.id) }
                                }
                                .pickerStyle(.menu).labelsHidden().fixedSize()
                            }
                        }
                        .font(.subheadline)
                        // for the email invite (Today → Email invites); golfers never see it
                        TextField("Email for the invite (optional)", text: $p.email)
                            .textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .font(.subheadline).foregroundStyle(p.email.isEmpty || Invites.ok(p.email) ? FC.ink : Color.red)
                    }
                }
                .onDelete { team.players.remove(atOffsets: $0) }
                Button { team.players.append(DeskPlayer()) } label: { Label("Add a Player", systemImage: "plus") }.disabled(team.players.count >= 6)
            } header: { Text("Players and handicaps") } footer: {
                Text(tees.isEmpty ? "Type each player’s course handicap. A player’s email is optional. It’s only for the email invite on Today."
                     : "Type a player’s Handicap Index (use + for plus handicaps, like +1.2) and pick their tees, and the course handicap on the right is worked out. Or leave Index empty and type the course handicap yourself. A player’s email is optional. It’s only for the email invite on Today.")
            }
            if !team.code.isEmpty {
                SwiftUI.Section {
                    ShareLink(item: doc.cartURL(team.code)) { Label("Send this team its scorecard link", systemImage: "square.and.arrow.up") }
                    LabeledContent("Cart code", value: team.code.uppercased())
                } footer: { Text("They open it on a phone in the cart to keep score.") }
            } else {
                SwiftUI.Section { Help("Save to make this team’s scorecard link.") }
            }
            SwiftUI.Section { Button("Remove This Team", role: .destructive) { confirm = true } }
        }
        .navigationTitle(team.displayName.isEmpty ? "New team" : team.displayName).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .confirmationDialog("Remove this team and its scores?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Remove Team", role: .destructive) { remove(); dismiss() }
        } message: { Text("It goes when you Save.") }
    }
    private var tees: [Tee] { doc.ev.course.tees }
    private func tee(_ p: DeskPlayer) -> Tee? { tees.first { $0.id == p.tee } ?? tees.first }
    private func recalc(_ p: inout DeskPlayer) {
        if let ch = Hcp.course(p.index, tee(p), par: doc.ev.course.par) { p.hcp = Double(ch); if p.tee.isEmpty { p.tee = tees.first?.id ?? "" } }
    }
}

/// Setup's Tees card: each set of tees with its rating and slope (as on the Mac), and one tap to put every player on the same tees.
struct TeesCard: View {
    @Bindable var doc: DeskDoc
    var body: some View {
        CardBox(title: "Tees", footer: doc.ev.course.tees.isEmpty ? "Add the tees to work out course handicaps from each player’s Handicap Index."
                : "Players start on the top tees. Change one player’s tees on Teams. Course handicap = Index × Slope ÷ 113 + (Rating − Par).") {
            VStack(alignment: .leading, spacing: 0) {
                if !doc.ev.course.tees.isEmpty {
                    HStack { Text("Tees"); Spacer(); Text("Rating").frame(width: 60, alignment: .trailing); Text("Slope").frame(width: 50, alignment: .trailing); Color.clear.frame(width: 22) }
                        .font(.caption.weight(.bold)).foregroundStyle(FC.muted).padding(.bottom, 6)
                }
                ForEach($doc.ev.course.tees) { $t in
                    HStack(spacing: 8) {
                        Circle().fill(swatch(t.name)).frame(width: 14, height: 14).overlay(Circle().stroke(.black.opacity(0.25)))
                        TextField("Name", text: $t.name)
                        TextField("", value: $t.rating, format: .number.precision(.fractionLength(1))).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 60)
                        TextField("", value: $t.slope, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 50)
                        Button { doc.ev.course.tees.removeAll { $0.id == t.id } } label: { Image(systemName: "minus.circle.fill").foregroundStyle(FC.muted.opacity(0.6)) }
                            .buttonStyle(.plain).frame(width: 22)
                    }
                    .padding(.vertical, 9)
                    Divider().overlay(FC.hairline)
                }
                HStack {
                    Button { doc.ev.course.tees.append(Tee(name: ["Blue", "White", "Gold", "Red"][min(doc.ev.course.tees.count, 3)], slope: 113, rating: 72)) } label: { Label("Add Tees", systemImage: "plus") }
                    Spacer()
                    if !doc.ev.course.tees.isEmpty && doc.ev.teams.contains(where: { !$0.players.isEmpty }) {
                        Menu {
                            ForEach(doc.ev.course.tees) { t in Button("\(t.name) tees") { everyone(on: t) } }
                        } label: { Label("Put everyone on…", systemImage: "person.3") }
                    }
                }
                .font(.subheadline.weight(.semibold)).foregroundStyle(FC.link).padding(.top, 10)
            }
            .padding(14)
        }
        // a changed rating or slope changes the course handicap of everyone with an Index
        .onChange(of: doc.ev.course.tees) { recalcAll() }
    }
    private func everyone(on t: Tee) {
        for i in doc.ev.teams.indices { for j in doc.ev.teams[i].players.indices { doc.ev.teams[i].players[j].tee = t.id } }
        recalcAll()
    }
    private func recalcAll() {
        let T = doc.ev.course.tees, par = doc.ev.course.par
        for i in doc.ev.teams.indices { for j in doc.ev.teams[i].players.indices {
            let p = doc.ev.teams[i].players[j]
            if let ch = Hcp.course(p.index, T.first { $0.id == p.tee } ?? T.first, par: par), Double(ch) != p.hcp { doc.ev.teams[i].players[j].hcp = Double(ch) }
        } }
    }
    private func swatch(_ name: String) -> Color {
        let n = name.lowercased()
        for (k, c) in [("black", Color.black), ("blue", Color(hex: 0x1f5aa6)), ("white", Color.white), ("gold", Color(hex: 0xd4a72c)), ("yellow", Color(hex: 0xe8c547)),
                       ("green", Color(hex: 0x2f8a57)), ("red", Color(hex: 0xc8312b)), ("orange", Color(hex: 0xe07b28)), ("silver", Color.gray), ("copper", Color(hex: 0xb06a3b))] where n.hasPrefix(k) { return c }
        return FC.paper2
    }
}
