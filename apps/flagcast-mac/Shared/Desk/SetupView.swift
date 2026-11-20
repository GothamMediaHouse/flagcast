import SwiftUI

/// Setup: the tournament, its format and the course (Find the course, holes, tees).
struct SetupView: View {
    @Bindable var doc: DeskDoc
    @Environment(DeskNav.self) private var model
    @State private var finding = false

    var body: some View {
        Form {
            SwiftUI.Section("Tournament") {
                TextField("Name", text: $doc.ev.name)
                TextField("Club", text: $doc.ev.club)
                DayPicker(text: $doc.ev.date)
                TextField("Course name", text: $doc.ev.course.name)
            }
            SwiftUI.Section {
                Picker("Format", selection: $doc.ev.format.type) {
                    Text("Best ball (teams)").tag("bestball"); Text("Scramble (one team score)").tag("scramble")
                    Text("Stroke play (each player)").tag("stroke"); Text("Stableford points").tag("stableford")
                }
                if doc.ev.format.type == "bestball" || doc.ev.format.type == "stableford" {
                    Picker("Best balls that count on each hole", selection: $doc.ev.format.count) { ForEach(1...3, id: \.self) { Text("\($0)").tag($0) } }
                }
                LabeledContent("Handicap allowance") {
                    HStack { TextField("", value: $doc.ev.format.allowance, format: .number).frame(width: 60).multilineTextAlignment(.trailing); Text("%").foregroundStyle(.secondary)
                        Stepper("", value: $doc.ev.format.allowance, in: 0...100, step: 5).labelsHidden() }
                }
                Picker("Holes", selection: $doc.ev.format.nine) { Text("18 holes").tag(""); Text("Front 9 (holes 1–9)").tag("front"); Text("Back 9 (holes 10–18)").tag("back") }
                Picker("Leaderboard shows", selection: $doc.ev.format.show) { Text("Net scores").tag("net"); Text("Gross scores").tag("gross") }
                TextField("Flights", text: Binding(get: { doc.ev.flights.joined(separator: ", ") },
                                                   set: { doc.ev.flights = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }),
                          prompt: Text("A, B, C"))
                Toggle("Side games on the scorecard (skins, Nassau and birdies)", isOn: $doc.ev.sideGames)
            } header: { Text("Format") } footer: {
                Help("Handicaps on the Teams page are each player’s course handicap. The allowance is applied to it, and strokes fall on the holes by stroke index. A picked-up ball counts as net double bogey. Ties are broken on the back 9, 6, 3 and last hole.")
            }
            SwiftUI.Section {
                HStack {
                    Button { finding = true } label: { Label("Find the Course…", systemImage: "magnifyingglass") }
                    Button("Fill a Standard Par 72") { doc.ev.course.holes = Core.defaultHoles() }
                    Spacer()
                    Button { model.section = .map } label: { Label(doc.ev.map.holes.isEmpty ? "Map the Course…" : "Course Map (\(doc.ev.map.holes.count) of 18 holes)", systemImage: "map") }
                }
                HoleGrid(holes: $doc.ev.course.holes, playing: Set(doc.ev.playHoles))
            } header: { Text("Course") } footer: {
                Help("Find the course fills in par, yardage, stroke index and every set of tees with its rating and slope. Stroke index (SI) 1 is the hardest hole: check against the club’s scorecard.")
            }
            SwiftUI.Section {
                TeeTable(tees: $doc.ev.course.tees, par: doc.ev.course.par)
            } header: { Text("Tees (for GHIN handicaps)") } footer: {
                Help("Add each set of tees with its course rating and slope. Give players their Handicap Index on the Teams page and Flagcast works out each course handicap: Index × Slope ÷ 113 + (Rating − Par).")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $finding) { FindCourseSheet(doc: doc) }
    }
}

/// A yyyy-mm-dd date (or none).
struct DayPicker: View {
    @Binding var text: String
    var body: some View {
        let date = ISO8601DateFormatter.day.date(from: text)
        LabeledContent("Date") {
            HStack {
                if let date {
                    DatePicker("", selection: Binding(get: { date }, set: { text = ISO8601DateFormatter.day.string(from: $0) }), displayedComponents: .date).labelsHidden()
                    Button("Clear") { text = "" }.buttonStyle(.borderless)
                } else {
                    Button("Set Date") { text = ISO8601DateFormatter.day.string(from: Date()) }
                }
            }
        }
    }
}

/// Par, yards and stroke index for the 18 holes, like the club's scorecard. Holes not played in a 9-hole round are dimmed.
struct HoleGrid: View {
    @Binding var holes: [Hole]
    var playing: Set<Int>
    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .center, horizontalSpacing: 4, verticalSpacing: 6) {
                GridRow {
                    Text("Hole").font(.caption.weight(.semibold)).foregroundStyle(.secondary).gridColumnAlignment(.leading)
                    ForEach(holes.indices, id: \.self) { i in Text("\(holes[i].n)").font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(playing.contains(holes[i].n) ? .primary : .tertiary) }
                    Text("Total").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                row("Par", \.par, total: holes.reduce(0) { $0 + $1.par })
                row("Yards", \.yds, total: holes.reduce(0) { $0 + $1.yds })
                row("SI", \.hcp, total: nil)
            }
            .padding(.vertical, 4)
        }
    }
    private func row(_ label: String, _ k: WritableKeyPath<Hole, Int>, total: Int?) -> some View {
        GridRow {
            Text(label).font(.callout).foregroundStyle(.secondary)
            ForEach(holes.indices, id: \.self) { i in
                TextField("", value: Binding(get: { holes[i][keyPath: k] }, set: { holes[i][keyPath: k] = $0 }), format: .number)
                    .multilineTextAlignment(.center).frame(width: label == "Yards" ? 44 : 34).font(.callout.monospacedDigit())
                    .opacity(playing.contains(holes[i].n) ? 1 : 0.45)
            }
            Text(total.map(String.init) ?? "").font(.callout.monospacedDigit().weight(.semibold)).frame(minWidth: 44)
        }
    }
}

struct TeeTable: View {
    @Binding var tees: [Tee]
    var par: Int
    var body: some View {
        if tees.isEmpty { Text("No tees yet. Add them to use Handicap Index.").foregroundStyle(.secondary) }
        else {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow { Text("Tees"); Text("Course rating"); Text("Slope"); Text("Par"); Text("") }.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach($tees) { $t in
                    GridRow {
                        TextField("", text: $t.name, prompt: Text("Blue")).frame(minWidth: 160)
                        TextField("", value: $t.rating, format: .number.precision(.fractionLength(1))).frame(width: 70)
                        TextField("", value: $t.slope, format: .number).frame(width: 60)
                        TextField("", value: Binding(get: { t.par == 0 ? nil : t.par }, set: { t.par = $0 ?? 0 }), format: .number, prompt: Text("\(par)")).frame(width: 60)
                        Button(role: .destructive) { tees.removeAll { $0.id == t.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).help("Remove these tees")
                    }
                }
            }
        }
        Button { tees.append(Tee(name: ["Blue", "White", "Gold", "Red"][min(tees.count, 3)], slope: 113, rating: 72)) } label: { Label("Add Tees", systemImage: "plus") }
    }
}

/// Find the course: search the course database, pick the course, then the tees the field plays.
struct FindCourseSheet: View {
    @Bindable var doc: DeskDoc
    @Environment(\.dismiss) private var dismiss
    @State private var q = ""
    @State private var busy = false
    @State private var msg: String?
    @State private var found: [Net.FoundCourse] = []
    @State private var card: Net.CourseCard?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Find the course").font(.title2.bold())
            HStack {
                TextField("Course name or town", text: $q).textFieldStyle(.roundedBorder).onSubmit(search)
                Button("Search", action: search).keyboardShortcut(.defaultAction).disabled(q.trimmingCharacters(in: .whitespaces).count < 3 || busy)
            }
            if busy { ProgressView().frame(maxWidth: .infinity) }
            if let msg { Text(msg).foregroundStyle(.secondary) }
            if let k = card {
                Text(k.name).font(.headline)
                if !k.city.isEmpty { Text([k.city, k.state].filter { !$0.isEmpty }.joined(separator: ", ")).foregroundStyle(.secondary) }
                Text("Which tees does the field play? The holes come from these; every set of tees is added for handicaps.").foregroundStyle(.secondary)
                List(k.tees.filter { !$0.holes.isEmpty }, id: \.self) { t in
                    Button { use(k, t) } label: {
                        HStack { Text(t.label).fontWeight(.medium); Spacer(); Text(teeLine(t)).foregroundStyle(.secondary).monospacedDigit() }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(minHeight: 180)
                Button("‹ Back to the results") { self.card = nil }.buttonStyle(.link)
            } else if !found.isEmpty {
                List(found) { c in
                    Button { pick(c) } label: { HStack { Text(c.name).fontWeight(.medium); Spacer(); Text(c.place).foregroundStyle(.secondary) }.contentShape(Rectangle()) }.buttonStyle(.plain)
                }
                .frame(minHeight: 220)
            }
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(20).frame(width: 560)
        .onAppear { q = doc.ev.course.name.isEmpty ? doc.ev.club : doc.ev.course.name.components(separatedBy: " · ").first ?? "" }
    }
    private func use(_ k: Net.CourseCard, _ t: Net.FoundTee) {
        doc.ev.fill(from: k, tee: t)
        let nine = t.holes.count <= 9 ? " (a 9-hole card: holes 1–9)" : ""
        doc.flash("Filled in from \(t.label) tees\(nine). Check against the club’s scorecard, then Save.")
        dismiss()
    }
    private func teeLine(_ t: Net.FoundTee) -> String {
        let rating = t.rating.map { String(format: "%.1f", $0) } ?? "–"
        let slope = t.slope.map { String(Int($0)) } ?? "–"
        var s = "\(rating) / \(slope)"
        if let p = t.par { s += " · par \(p)" }
        if let y = t.yards { s += " · \(y) yds" }
        return s
    }
    private func search() {
        busy = true; msg = nil; card = nil
        Task { defer { busy = false }
            do { found = try await Net.findCourses(q.trimmingCharacters(in: .whitespaces)); if found.isEmpty { msg = "No course by that name. Try the club’s name or the town." } }
            catch { msg = error.localizedDescription }
        }
    }
    private func pick(_ c: Net.FoundCourse) {
        busy = true; msg = nil
        Task { defer { busy = false }
            do { let k = try await Net.course(c.id); if k.tees.allSatisfy({ $0.holes.isEmpty }) { msg = "That course has no scorecard in the lookup. Type the numbers from the club’s card." } else { card = k } }
            catch { msg = error.localizedDescription }
        }
    }
}
