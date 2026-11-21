import SwiftUI

/// Contests: closest to the pin (feet) and long drive (yards). Set them up and Save; results go on the screens
/// as soon as they're added (they save on their own).
struct ContestsView: View {
    @Bindable var doc: DeskDoc

    var body: some View {
        DeskPage(doc: doc, section: .contests) {
            Button { add("ctp") } label: { Label("Closest to the pin", systemImage: "flag") }.buttonStyle(GlassButton())
            Button { add("ld") } label: { Label("Long drive", systemImage: "arrow.up.right") }.buttonStyle(GlassButton())
        } title: {
            HeroTitle(title: "Contests", size: 52, sub: "Closest to the pin and long drive", subBeside: true)
        } content: {
            CardForm {
            if doc.ev.contests.isEmpty {
                SwiftUI.Section { Text("No contests yet. Add closest to the pin or long drive with the buttons above.").foregroundStyle(.secondary) }
            }
            ForEach($doc.ev.contests) { $c in
                SwiftUI.Section {
                    Picker("Contest", selection: $c.kind) { Text("Closest to the pin").tag("ctp"); Text("Long drive").tag("ld") }
                    Picker("Hole", selection: $c.hole) { ForEach(doc.ev.course.holes, id: \.n) { h in Text("Hole \(h.n) · par \(h.par)").tag(h.n) } }
                    TextField("Name on the screens", text: $c.label, prompt: Text(c.isLongDrive ? "Long drive" : "Closest to the pin"))
                    TextField("Sponsor", text: $c.sponsor, prompt: Text("Optional"))
                    ContestResults(doc: doc, contest: c)
                } header: {
                    HStack { Text(c.title + " · hole \(c.hole)"); Spacer()
                        Button(role: .destructive) { doc.ev.contests.removeAll { $0.id == c.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless).help("Remove this contest") }
                }
            }
            Help("Closest to the pin is measured in feet (4.5 = 4 ft 6 in). Long drive in yards. Set the contest’s hole and name, then Save before entering results. Marshals can post results from the Flagcast phone app with their PIN.")
        }
            }
    }
    private func add(_ kind: String) {
        let p3 = doc.ev.course.holes.first { $0.par == 3 }?.n ?? 3, p5 = doc.ev.course.holes.first { $0.par == 5 }?.n ?? 2
        doc.ev.contests.append(Contest(id: Ids.make(), kind: kind, hole: kind == "ld" ? p5 : p3))
    }
}

/// A contest's results: the leaders, and adding or removing an entry (saves at once).
struct ContestResults: View {
    let doc: DeskDoc, contest: Contest
    @State private var name = ""
    @State private var dist = ""
    private var saved: Contest? { (doc.live?.contests ?? []).first { $0.id == contest.id } }

    var body: some View {
        if let saved {
            let lead = Core.contestLeader(saved)
            ForEach(Array(saved.entries.enumerated()), id: \.offset) { _, e in
                HStack {
                    if e == lead.first { Image(systemName: "crown.fill").foregroundStyle(Color.fcFlag) }
                    Text(e.name); Spacer(); Text(Core.fmtDist(saved, e.dist)).monospacedDigit().foregroundStyle(.secondary)
                    Button(role: .destructive) { Task { await doc.day("contest", ["id": saved.id, "entries": saved.entries.filter { $0 != e }.map { ["name": $0.name, "dist": $0.dist] }]) } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("Player", text: $name)
                TextField(saved.isLongDrive ? "Yards" : "Feet", text: $dist).frame(width: 80)
                Button("Add Result") {
                    guard let d = Double(dist), !name.isEmpty else { return }
                    let entries = saved.entries.filter { $0.name.lowercased() != name.lowercased() } + [ContestEntry(name: name, dist: d)]
                    Task { if await doc.day("contest", ["id": saved.id, "entries": entries.map { ["name": $0.name, "dist": $0.dist] }]) != nil { name = ""; dist = "" } }
                }.disabled(name.isEmpty || Double(dist) == nil)
            }
        } else {
            Text("Save (⌘S) before entering results.").foregroundStyle(.secondary)
        }
    }
}
