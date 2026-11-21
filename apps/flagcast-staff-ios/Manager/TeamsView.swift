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
        PhotoPage(image: doc.picture.image, kicker: "\(doc.ev.teams.count) teams · \(doc.ev.teams.reduce(0) { $0 + $1.players.count }) players", title: "Teams", height: 220) {
            EmptyView()
        } content: {
            // a search box in the page (the system one sat on top of the photo header's words)
            if doc.ev.teams.count > 6 { BoxField(placeholder: "Find a team or player", text: $search) }
            if doc.ev.flights.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) { ForEach([""] + doc.ev.flights, id: \.self) { f in chip(f.isEmpty ? "All" : "Flight \(f)", on: flight == f) { flight = f } } }
                }
            }
            if doc.ev.teams.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.3").font(.system(size: 34)).foregroundStyle(FC.muted)
                    Text("No teams yet").font(FC.display(28))
                    Text("Add each team or cart. Players can be added now or later.").font(.subheadline).foregroundStyle(FC.muted).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).card(padding: 24)
            }
            ForEach(teams) { t in
                Button { editing = t.id } label: { TeamCard(team: t, doc: doc) }.buttonStyle(.plain)
            }
            Button { addTeam() } label: { Label("Add a Team", systemImage: "plus") }.buttonStyle(GreenButton(full: true))
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
                TextField("Cart number", text: $team.cart)
            }
            SwiftUI.Section {
                ForEach($team.players) { $p in
                    HStack {
                        TextField("Player name", text: $p.name).textContentType(.name)
                        TextField("Hcp", value: $p.hcp, format: .number.precision(.fractionLength(0...1))).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 60)
                    }
                }
                .onDelete { team.players.remove(atOffsets: $0) }
                Button { team.players.append(DeskPlayer()) } label: { Label("Add a Player", systemImage: "plus") }.disabled(team.players.count >= 6)
            } header: { Text("Players and handicaps") }
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
}
