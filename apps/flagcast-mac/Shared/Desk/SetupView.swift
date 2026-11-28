import SwiftUI

/// Setup (design/Setup.dc.html): the course over the aerial photo; Tournament and Tees cards on the left, the
/// scorecard (front and back nine) on the right. The nine not in play is dimmed.
struct SetupView: View {
    @Bindable var doc: DeskDoc
    @Environment(DeskNav.self) private var nav
    @State private var finding = false

    var body: some View {
        DeskPage(doc: doc, section: .setup, height: 300, titleHeight: 192) {
            Button("Find the course…") { finding = true }.buttonStyle(GlassButton())
            Button("Map the holes") { nav.section = .map }.buttonStyle(GlassButton())
        } title: {
            HeroTitle(kicker: "COURSE" + (doc.ev.club.isEmpty ? "" : " · \(doc.ev.club)"), title: doc.ev.course.name.isEmpty ? "Pick the course" : doc.ev.course.name, size: 56)
        } content: {
            HStack(alignment: .top, spacing: 16) {
                ScrollView {
                    VStack(spacing: 14) { tournamentCard; teesCard }.padding(.bottom, 18)
                }
                .scrollIndicators(.never)
                .frame(width: 320)
                ScrollView {
                    VStack(spacing: 14) { scorecard; photosCard; extras }.padding(.bottom, 18)
                }
                .scrollIndicators(.never)
            }
            .padding(.horizontal, 20)
        }
        .sheet(isPresented: $finding) { FindCourseSheet(doc: doc) }
    }

    // ---- left: tournament ----
    private var tournamentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle("Tournament")
            field("Name") { TextField("", text: $doc.ev.name).textFieldStyle(.roundedBorder) }
            field("Club") { TextField("", text: $doc.ev.club).textFieldStyle(.roundedBorder) }
            field("Logo") { TournamentLogoField(logo: $doc.ev.logo) }
            field(doc.ev.days > 1 ? "Round 1 date" : "Date") { DayPicker(text: $doc.ev.date, label: false) }
            // multi-day: a date for each round, and how the leaderboard adds them up
            field("Days") {
                Picker("", selection: Binding(get: { doc.ev.days }, set: { doc.ev.setDays($0) })) {
                    Text("One day").tag(1); Text("2 rounds").tag(2); Text("3 rounds").tag(3); Text("4 rounds").tag(4)
                }.pickerStyle(.segmented).labelsHidden()
            }
            if doc.ev.days > 1 {
                ForEach(Array(1..<doc.ev.days), id: \.self) { i in
                    field("Round \(i + 1) date") { DayPicker(text: Binding(get: { doc.ev.roundDate(i) }, set: { doc.ev.setRoundDate(i, $0) }), label: false) }
                }
                field("Leaderboard over the rounds") {
                    Picker("", selection: $doc.ev.boardBy) { Text("Total of all rounds").tag("total"); Text("Each round on its own").tag("round") }.pickerStyle(.segmented).labelsHidden()
                }
                Help("The same teams, cart codes and PINs play every round. Each morning the tournament moves on to that day’s round by itself; you can change the round on the Overview. The format and handicaps can change between rounds: change them here on the morning of the round.")
            }
            field("Format") {
                Picker("", selection: $doc.ev.format.type) {
                    Text("Best ball (teams)").tag("bestball"); Text("Shamble (best drive, then own ball)").tag("shamble")
                    Text("Scramble (one team score)").tag("scramble")
                    Text("Stroke play (each player)").tag("stroke"); Text("Stableford points").tag("stableford")
                    Text("Match play (head to head)").tag("match")
                }.labelsHidden()
            }
            if ["bestball", "shamble", "stableford"].contains(doc.ev.format.type) {
                field("Best balls that count on each hole") { Picker("", selection: $doc.ev.format.count) { ForEach(1...3, id: \.self) { Text("\($0)").tag($0) } }.pickerStyle(.segmented).labelsHidden() }
            }
            if doc.ev.format.isMatch {
                field("Match type") {
                    Picker("", selection: $doc.ev.format.match) { Text("Singles").tag("singles"); Text("Four-ball").tag("fourball"); Text("Scramble").tag("scramble") }
                        .pickerStyle(.segmented).labelsHidden()
                }
                Toggle("Team cup (two sides, 1 point a win, ½ a halve)", isOn: $doc.ev.format.cup.on).font(.system(size: 12))
                if doc.ev.format.cup.on {
                    field("Side names") {
                        HStack { TextField("Reds", text: $doc.ev.format.cup.a).textFieldStyle(.roundedBorder); TextField("Blues", text: $doc.ev.format.cup.b).textFieldStyle(.roundedBorder) }
                    }
                }
                Help("Strokes come off the lowest player in each match (90% is usual for four-ball). Pair the teams with Matches on the Teams page.")
            }
            if doc.ev.format.hasIndividuals {
                Toggle("Individuals leaderboard (every player’s net and gross, for a club championship)", isOn: $doc.ev.format.indiv).font(.system(size: 12))
            }
            field("Holes") {
                Picker("", selection: $doc.ev.format.nine) { Text("All 18").tag(""); Text("Front 9").tag("front"); Text("Back 9").tag("back") }.pickerStyle(.segmented).labelsHidden()
            }
        }
        .raisedCard(padding: 16)
    }
    private func field<C: View>(_ label: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(FC.muted); c() }
    }

    // ---- left: tees ----
    private var teesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { CardTitle("Tees"); Spacer()
                Button("+ Add tees") { doc.ev.course.tees.append(Tee(name: ["Blue", "White", "Gold", "Red"][min(doc.ev.course.tees.count, 3)], slope: 113, rating: 72)) }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(FC.link) }
            HStack { Text("Tees"); Spacer(); Text("Rating").frame(width: 56, alignment: .trailing); Text("Slope").frame(width: 48, alignment: .trailing); Color.clear.frame(width: 16) }
                .font(.system(size: 11, weight: .bold)).foregroundStyle(FC.muted)
            if doc.ev.course.tees.isEmpty { Text("No tees yet. Find the course, or add them to use Handicap Index.").font(.callout).foregroundStyle(FC.muted).padding(.vertical, 6) }
            ForEach($doc.ev.course.tees) { $t in
                Divider().overlay(FC.hairline)
                HStack(spacing: 8) {
                    Circle().fill(swatch(t.name)).frame(width: 12, height: 12).overlay(Circle().stroke(.black.opacity(0.25)))
                    TextField("", text: $t.name).textFieldStyle(.plain).font(.system(size: 13, weight: .medium))
                    TextField("", value: $t.rating, format: .number.precision(.fractionLength(1))).textFieldStyle(.plain).multilineTextAlignment(.trailing).frame(width: 56)
                    TextField("", value: $t.slope, format: .number).textFieldStyle(.plain).multilineTextAlignment(.trailing).frame(width: 48)
                    Button { doc.ev.course.tees.removeAll { $0.id == t.id } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(FC.muted.opacity(0.6)) }.buttonStyle(.plain).frame(width: 16)
                }
                .font(.system(size: 13)).padding(.vertical, 3)
            }
            Help("Course handicap = Index × Slope ÷ 113 + (Rating − Par).").padding(.top, 4)
        }
        .raisedCard(padding: 16)
    }
    private func swatch(_ name: String) -> Color {
        let n = name.lowercased()
        for (k, c) in [("black", Color.black), ("blue", Color(hex: 0x1f5aa6)), ("white", Color.white), ("gold", Color(hex: 0xd4a72c)), ("yellow", Color(hex: 0xe8c547)),
                       ("green", Color(hex: 0x2f8a57)), ("red", Color(hex: 0xc8312b)), ("orange", Color(hex: 0xe07b28)), ("silver", Color.gray), ("copper", Color(hex: 0xb06a3b))] where n.hasPrefix(k) { return c }
        return FC.paper2
    }

    // ---- right: the scorecard ----
    private var scorecard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { CardTitle("Scorecard"); Spacer()
                Button("Save to the Flagcast course list") { saveToList() }.buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(FC.link)
                    .help("Share this course’s holes, tees and map so any club can pick it in Find the course").disabled(doc.ev.course.name.isEmpty)
                Text("·").foregroundStyle(FC.muted)
                Button("Fill a standard par 72") { doc.ev.course.holes = Core.defaultHoles() }.buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(FC.link) }
            nine("FRONT 9", 0..<9, playing: doc.ev.format.nine != "back")
            nine("BACK 9", 9..<18, playing: doc.ev.format.nine != "front")
            Help("Stroke index (SI) 1 is the hardest hole. Check the numbers against the club’s scorecard.")
        }
        .raisedCard(padding: 18)
    }
    private func nine(_ title: String, _ r: Range<Int>, playing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) { Text(title).font(.system(size: 12, weight: .bold)).tracking(1).foregroundStyle(FC.muted)
                if !playing { Text("not in play").font(.system(size: 12)).foregroundStyle(FC.muted) } }
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    cellLabel("Hole", header: true)
                    ForEach(r, id: \.self) { i in Text("\(doc.ev.course.holes[i].n)").font(FC.display(16)).foregroundStyle(FC.onGreen).frame(maxWidth: .infinity, minHeight: 30).background(FC.green) }
                    Text(r.lowerBound == 0 ? "OUT" : "IN").font(FC.display(16)).foregroundStyle(FC.onGreen).frame(width: 56, height: 30).background(FC.green)
                }
                gridRow("Par", r, \.par, shade: true)
                gridRow("Yards", r, \.yds, shade: false)
                gridRow("SI", r, \.hcp, shade: false, total: false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(FC.line))
        }
        .opacity(playing ? 1 : 0.4)
    }
    private func cellLabel(_ t: String, header: Bool = false) -> some View {
        Text(t).font(.system(size: 12, weight: .semibold)).foregroundStyle(header ? FC.onGreen : FC.muted)
            .frame(width: 64, alignment: .leading).padding(.leading, 10).frame(minHeight: 30).background(header ? FC.green : FC.head)
    }
    private func gridRow(_ label: String, _ r: Range<Int>, _ k: WritableKeyPath<Hole, Int>, shade: Bool, total: Bool = true) -> some View {
        GridRow {
            cellLabel(label)
            ForEach(r, id: \.self) { i in
                TextField("", value: Binding(get: { doc.ev.course.holes[i][keyPath: k] }, set: { doc.ev.course.holes[i][keyPath: k] = $0 }), format: .number)
                    .textFieldStyle(.plain).multilineTextAlignment(.center).font(.system(size: 14, weight: label == "Par" ? .semibold : .regular).monospacedDigit())
                    .frame(maxWidth: .infinity, minHeight: 32).background(shade ? FC.paper2.opacity(0.6) : FC.card)
                    .overlay(alignment: .leading) { Rectangle().fill(FC.hairline).frame(width: 1) }
            }
            Text(total ? "\(r.reduce(0) { $0 + doc.ev.course.holes[$1][keyPath: k] })" : "").font(.system(size: 14, weight: .bold).monospacedDigit())
                .frame(width: 56, height: 32).background(FC.head)
        }
        .overlay(alignment: .top) { Rectangle().fill(FC.hairline).frame(height: 1) }
    }

    private func saveToList() {
        Task {
            if doc.dirty { await doc.save() }
            do { _ = try await Net.saveToLibrary(doc.id, doc.key); doc.flash("Saved to the Flagcast course list. Any club can pick \(doc.ev.course.name) in Find the course.") }
            catch { doc.flash(error.localizedDescription) }
        }
    }

    // ---- right, below: the rest of the format ----
    // ---- right: the photos golfers see (saved at once, not with Save) ----
    private var photosCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle("Photos golfers see")
            Help("A cover photo shows when golfers open the tournament on their phone. A hole photo shows on that hole’s page instead of the satellite view. Photos save as soon as you add them.")
            HStack(alignment: .top, spacing: 8) {
                PhotoSpot(doc: doc, slot: "cover", label: "Cover photo", url: doc.ev.photos.coverURL, height: 176).frame(width: 240)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                    ForEach(doc.ev.course.holes, id: \.n) { h in
                        PhotoSpot(doc: doc, slot: "h\(h.n)", label: "Hole \(h.n)", url: doc.ev.photos.hole(h.n), height: 54)
                    }
                }
            }
        }
        .raisedCard(padding: 18)
    }

    private var extras: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle("Scoring")
            HStack(spacing: 18) {
                field("Handicap allowance") {
                    HStack { TextField("", value: $doc.ev.format.allowance, format: .number).textFieldStyle(.roundedBorder).frame(width: 60); Text("%").foregroundStyle(FC.muted)
                        Stepper("", value: $doc.ev.format.allowance, in: 0...100, step: 5).labelsHidden() }
                }
                field("Leaderboard shows") { Picker("", selection: $doc.ev.format.show) { Text("Net").tag("net"); Text("Gross").tag("gross") }.pickerStyle(.segmented).labelsHidden().frame(width: 140) }
                field("Flights") {
                    TextField("", text: Binding(get: { doc.ev.flights.joined(separator: ", ") }, set: { doc.ev.flights = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }), prompt: Text("A, B, C"))
                        .textFieldStyle(.roundedBorder)
                }
            }
            Toggle("Side games on the scorecard (skins, Nassau, Wolf and more, for points)", isOn: $doc.ev.sideGames)
            Help("Handicaps are each player’s course handicap; the allowance is applied to it and strokes fall by stroke index. A picked-up ball counts as net double bogey. Ties are broken on the back 9, 6, 3 and last hole.")
        }
        .raisedCard(padding: 18)
    }
}

/// A yyyy-mm-dd date (or none).
struct DayPicker: View {
    @Binding var text: String
    var label = true
    var body: some View {
        if label { LabeledContent("Date") { picker } } else { picker }
    }
    private var picker: some View {
        let date = ISO8601DateFormatter.day.date(from: text)
        return HStack {
                if let date {
                    DatePicker("", selection: Binding(get: { date }, set: { text = ISO8601DateFormatter.day.string(from: $0) }), displayedComponents: .date).labelsHidden()
                    Button("Clear") { text = "" }.buttonStyle(.borderless)
                } else {
                    Button("Set Date") { text = ISO8601DateFormatter.day.string(from: Date()) }
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
                HStack { Text(k.name).font(.headline); if k.library { FlagcastTag() } }
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
                    Button { pick(c) } label: { HStack { Text(c.name).fontWeight(.medium); if c.library { FlagcastTag() }; Spacer(); Text(c.place).foregroundStyle(.secondary) }.contentShape(Rectangle()) }.buttonStyle(.plain)
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
        if let m = k.map, !m.holes.isEmpty, doc.ev.map.holes.isEmpty, let obj = try? Net.object(m) {
            doc.ev.map = m
            Task { await doc.day("map", ["map": obj]) }
        }
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

/// The "Flagcast" tag on a course from Flagcast's own course list.
struct FlagcastTag: View {
    var body: some View {
        Text("FLAGCAST").font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(FC.onGreen)
            .padding(.horizontal, 6).padding(.vertical, 2).background(FC.green, in: RoundedRectangle(cornerRadius: 4))
    }
}
