import SwiftUI

// Golfers' own long drive / closest to the pin entries (golf.js enter): the To check list, OK / Change / Remove,
// and a contest's settings. Shared by the Mac Manager and the iPhone/iPad Manager.

/// OK, Change (type the right distance) and Remove for one result. Each saves at once (desk op 'check').
struct ContestCheckButtons: View {
    let doc: DeskDoc, contest: Contest, entry: ContestEntry
    @State private var changing = false
    @State private var dist = ""

    var body: some View {
        HStack(spacing: 6) {
            if entry.waiting {
                Button("OK") { Task { await doc.day("check", ["id": contest.id, "name": entry.name, "do": "ok"], done: "Checked. It’s on the screens.") } }
                    .buttonStyle(.borderedProminent).tint(.green)
            }
            Button("Change") { dist = Self.plain(entry.dist); changing = true }.buttonStyle(.bordered)
            Button("Remove", role: .destructive) { Task { await doc.day("check", ["id": contest.id, "name": entry.name, "do": "remove"], done: "Taken off.") } }
                .buttonStyle(.bordered)
        }
        .controlSize(.small)
        .alert("\(entry.name): the right distance", isPresented: $changing) {
            TextField(contest.isLongDrive ? "Yards" : "Feet (4.5 = 4 ft 6 in)", text: $dist)
            Button("Save") {
                guard let d = Double(dist.replacingOccurrences(of: ",", with: ".")), d > 0 else { return }
                Task { await doc.day("check", ["id": contest.id, "name": entry.name, "do": "change", "dist": d], done: "Changed and checked.") }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text(contest.isLongDrive ? "In yards." : "In feet: 4.5 is 4 ft 6 in.") }
    }
    static func plain(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(format: "%.2f", d) }
}

/// One result line: place, name, distance, ✓ / ◷, a warning when it looks wrong, and the buttons.
struct ContestResultRow: View {
    let doc: DeskDoc, contest: Contest, entry: ContestEntry, place: Int?
    var showContest = false

    var body: some View {
        let flag = Core.contestFlag(contest, entry)
        VStack(alignment: .trailing, spacing: 4) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let place { Text("\(place).").monospacedDigit().foregroundStyle(.secondary).frame(width: 26, alignment: .leading) }
            VStack(alignment: .leading, spacing: 1) {
                Text(showContest ? "\(entry.name) · \(contest.title) \(contest.hole)" : entry.name)
                Text(flag.isEmpty ? note : flag).font(.caption).foregroundStyle(flag.isEmpty ? Color.secondary : Color.orange)
            }
            Spacer(minLength: 6)
            Text(Core.fmtDist(contest, entry.dist)).monospacedDigit().fontWeight(.semibold)
            Image(systemName: entry.ok ? "checkmark.circle.fill" : "clock").foregroundStyle(entry.ok ? Color.green : Color.orange)
                .help(entry.ok ? "On the screens" : "Waiting for a check: phones show it, TVs don’t")
        }
            ContestCheckButtons(doc: doc, contest: contest, entry: entry)
        }
    }
    private var note: String {
        if entry.byGolfer { return entry.gps > 0 ? "Golfer · GPS from the tee \(Int(entry.gps.rounded())) yds" : "Golfer · typed" + (entry.okBy.isEmpty ? "" : " · OK’d by \(entry.okBy)") }
        return entry.by.isEmpty ? "Desk" : entry.by
    }
}

/// Every golfer entry still waiting for a check, across the contests.
struct ContestToCheck: View {
    let doc: DeskDoc
    var body: some View {
        let live = doc.live?.contests ?? []
        let wait = live.flatMap { c in c.waiting.map { (c, $0) } }
        if !wait.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("To check").font(.headline); Text("\(wait.count) waiting").foregroundStyle(.secondary) }
                ForEach(Array(wait.enumerated()), id: \.offset) { _, x in
                    ContestResultRow(doc: doc, contest: x.0, entry: x.1, place: nil, showContest: true)
                    Divider()
                }
                Text("Golfers’ entries near the top wait for an OK before the TVs show them. Phones show them with a clock.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// A contest's settings for golfers' own entries (saved with the setup).
struct ContestSettings: View {
    @Binding var c: Contest
    var body: some View {
        Toggle(isOn: $c.golfersEnter) {
            VStack(alignment: .leading) { Text("Golfers enter their own"); Text("Shows “\(c.isLongDrive ? "Enter my drive" : "Enter my shot")” on hole \(c.hole) in the Flagcast app").font(.caption).foregroundStyle(.secondary) }
        }
        if c.golfersEnter {
            Picker(selection: $c.check) {
                Text("Only the top 3").tag("top"); Text("Every entry").tag("all"); Text("Trust golfers").tag("none")
            } label: {
                VStack(alignment: .leading) { Text("Check entries"); Text("Waiting entries show on phones with a clock, not on TVs").font(.caption).foregroundStyle(.secondary) }
            }
        }
        Picker("Winner gets", selection: $c.prize) {
            Text("No prize").tag(0)
            ForEach([10, 25, 50, 100, 250, 500], id: \.self) { Text("\($0) points").tag($0) }
            if ![0, 10, 25, 50, 100, 250, 500].contains(c.prize) { Text("\(c.prize) points").tag(c.prize) }
        }
    }
}
