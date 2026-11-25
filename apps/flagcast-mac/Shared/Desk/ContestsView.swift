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
            if (doc.live?.contests ?? []).contains(where: { !$0.waiting.isEmpty }) {
                SwiftUI.Section { ContestToCheck(doc: doc) }
            }
            if doc.ev.contests.isEmpty {
                SwiftUI.Section { Text("No contests yet. Add closest to the pin or long drive with the buttons above.").foregroundStyle(.secondary) }
            }
            ForEach($doc.ev.contests) { $c in
                SwiftUI.Section {
                    Picker("Contest", selection: $c.kind) { Text("Closest to the pin").tag("ctp"); Text("Long drive").tag("ld") }
                    Picker("Hole", selection: $c.hole) { ForEach(doc.ev.course.holes, id: \.n) { h in Text("Hole \(h.n) · par \(h.par)").tag(h.n) } }
                    TextField("Name on the screens", text: $c.label, prompt: Text(c.isLongDrive ? "Long drive" : "Closest to the pin"))
                    TextField("Sponsor", text: $c.sponsor, prompt: Text("Optional"))
                    ContestSettings(c: $c)
                    ContestResults(doc: doc, contest: c)
                } header: {
                    HStack { Text(c.title + " · hole \(c.hole)"); Spacer()
                        Button(role: .destructive) { doc.ev.contests.removeAll { $0.id == c.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless).help("Remove this contest") }
                }
            }
            Help("Closest to the pin is measured in feet (4.5 = 4 ft 6 in). Long drive in yards. Golfers can enter their own on the contest hole in the Flagcast app; marshals and the pro can post and check results from the app with their PIN. TVs only show checked results. Points only, no money. Save a new contest before entering results.")
        }
            }
    }
    private func add(_ kind: String) {
        let p3 = doc.ev.course.holes.first { $0.par == 3 }?.n ?? 3, p5 = doc.ev.course.holes.first { $0.par == 5 }?.n ?? 2
        doc.ev.contests.append(Contest(id: Ids.make(), kind: kind, hole: kind == "ld" ? p5 : p3))
    }
}

/// A contest's results: the leaders with ✓ / ◷, OK / Change / Remove, and adding a result (saves at once, checked).
struct ContestResults: View {
    let doc: DeskDoc, contest: Contest
    @State private var name = ""
    @State private var dist = ""
    private var saved: Contest? { (doc.live?.contests ?? []).first { $0.id == contest.id } }

    var body: some View {
        if let saved {
            let lead = Core.contestLeader(saved)
            ForEach(Array(lead.enumerated()), id: \.offset) { i, e in
                ContestResultRow(doc: doc, contest: saved, entry: e, place: i + 1)
            }
            HStack {
                TextField("Player", text: $name)
                TextField(saved.isLongDrive ? "Yards" : "Feet", text: $dist).frame(width: 80)
                Button("Add Result") {
                    guard let d = Double(dist), !name.isEmpty else { return }
                    Task { if await doc.day("ctp", ["id": saved.id, "name": name, "dist": d]) != nil { name = ""; dist = "" } }
                }.disabled(name.isEmpty || Double(dist) == nil)
            }
        } else {
            Text("Save (⌘S) before entering results.").foregroundStyle(.secondary)
        }
    }
}
