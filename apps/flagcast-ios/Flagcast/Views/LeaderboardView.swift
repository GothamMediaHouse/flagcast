import SwiftUI

/// The live leaderboard (matches public/golf/live/): flight filters, tap a team for its card, fundraising bar,
/// news flash, and tabs for the par 3 cameras, contests and skins.
struct LeaderboardScreen: View {
    let id: String
    /// the Leaders tab (teams, contests, skins) or the Cameras tab (the par 3s)
    var mode: Mode = .leaders
    /// this cart's teams, marked YOU
    var mine: Set<String> = []
    enum Mode { case leaders, cameras }
    @State private var feed: EventFeed
    @State private var tab: Tab = .board
    @State private var flight = ""
    @State private var open: String?
    @State private var web: URL?
    @State private var dismissed = 0.0          // bumped when the phone banner is closed, to redraw
    @State private var scrollTo: String?
    @State private var allPar3s = false
    /// the Cameras tab's filter (nil: every camera)
    @State private var camKind: CamItem.Kind?
    /// a replay from the Latest replays strip, full screen
    @State private var replayOpen: Replay?
    @Environment(Router.self) private var router
    @Environment(TourNav.self) private var nav
    enum Tab: String, CaseIterable { case board = "Teams", indiv = "Individuals", par3 = "Par 3s", contests = "Contests", skins = "Skins" }
    /// Individuals: ranked by net or gross ("" = the event's own)
    @State private var imode = ""

    init(id: String, mode: Mode = .leaders, mine: Set<String> = []) {
        self.id = id; self.mode = mode; self.mine = mine
        _feed = State(initialValue: Feeds.feed(id))
        _tab = State(initialValue: mode == .cameras ? .par3 : .board)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let s = feed.state {
                VStack(spacing: 0) {
                if mode == .cameras {
                    TourHeader(state: s, title: s.title) { LivePill(online: feed.online) } below: {
                        let n = s.camList().count
                        TourTitle(title: n == 0 ? "Par 3s" : "Cameras",
                                  sub: n == 0 ? "Scoring on the short holes" : "\(n) camera\(n == 1 ? "" : "s") live · tap ⟲ 30s to rewind")
                    }
                } else {
                    VStack(spacing: 0) {
                        GreenHeader(title: s.title, subtitle: [s.club, s.course.name != s.club ? s.course.name : "", s.dayText].filter { !$0.isEmpty }.joined(separator: " · "), state: s, height: 250) {
                            HStack(spacing: 8) {
                                LivePill(online: feed.online)
                                ShareLink(item: Server.page("g/\(id)")) {
                                    Image(systemName: "square.and.arrow.up").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                                        .frame(width: 36, height: 36).background(Color.black.opacity(0.3), in: Circle())
                                }
                                .accessibilityLabel("Share the leaderboard")
                            }
                        }
                        if tabs(s).count > 1 {
                            HeaderSwitch(options: tabs(s).map { ($0, $0 == .board && s.format.isMatch ? "Matches" : $0.rawValue) }, selection: $tab)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(Color.fcGreen)
                        }
                    }
                    .ignoresSafeArea(edges: .top)
                }
                if let f = s.flash, Date().timeIntervalSince1970 * 1000 - f.at < 30 * 60_000 {
                    Label(f.text, systemImage: "megaphone.fill").font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color.fcFlag).foregroundStyle(Color.fcOnFlag)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            switch tab {
                            case .board: if s.format.isMatch { matchBoard(s) } else { board(s) }
                            case .indiv: individuals(s)
                            case .par3: par3s(s)
                            case .contests: contests(s)
                            case .skins: skins(s)
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 70)
                        .frame(maxWidth: 720)
                        .frame(maxWidth: .infinity)
                    }
                    .refreshable { await feed.refresh() }
                    .onChange(of: scrollTo) { _, t in
                        guard let t else { return }
                        Task { try? await Task.sleep(for: .milliseconds(250)); withAnimation { proxy.scrollTo(t, anchor: .top) }; scrollTo = nil }
                    }
                }
                .overlay(alignment: .bottom) {
                    if let r = PhoneCast.current(s, id: id), dismissed >= 0 {
                        PhoneBanner(state: s, route: r, go: { follow($0, s) }, close: { PhoneCast.dismiss(r, id: id); withAnimation { dismissed += 1 } })
                            .padding(.bottom, 8)
                    }
                }
                .animation(.spring(duration: 0.35), value: s.live.phone)
                }
            } else if let m = feed.missing {
                ContentUnavailableView("Not found", systemImage: "questionmark.circle", description: Text(m))
            } else {
                ProgressView("Loading the leaderboard").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.fcPaper)
        .animation(.default, value: feed.state?.flash)
        .overlay(alignment: .topLeading) {
            // the cover photo runs up behind the status bar: a way home on top of it
            if mode == .leaders, feed.state != nil {
                Button { router.path = [] } label: {
                    Image(systemName: "chevron.left").font(.headline.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(Color.black.opacity(0.3), in: Circle())
                }
                .accessibilityLabel("Home")
                .padding(.leading, 16).padding(.top, 6)
            }
        }
        .onAppear {
            feed.start()
            if let s = feed.state { Recents.remember(id: id, name: s.name) }
            // opened from the scorecard's phone banner: go straight to what it points at
            if let r = PhoneCast.pending.removeValue(forKey: id), let s = feed.state { follow(r, s) }
        }
        .onDisappear { feed.stop() }
        .onChange(of: feed.state?.name) { _, n in if let n { Recents.remember(id: id, name: n) } }
        .sheet(item: $web) { SafariView(url: $0).ignoresSafeArea() }
        .fullScreenCover(isPresented: $allPar3s) { if let s = feed.state { AllPar3s(state: s) } }
        .fullScreenCover(item: $replayOpen) { r in
            ReplayFullscreen(replay: r, camURL: feed.state?.camShown(r.hole).flatMap { CameraLink(hole: r.hole, url: $0).isHLS ? $0 : nil },
                             replays: feed.state?.replays.filter { $0.hole == r.hole } ?? [])
        }
    }

    /// "See it" / "Watch" on a phone banner: the matching tab (a camera → Par 3s, scrolled to its hole).
    private func follow(_ r: PhoneRoute, _ s: EventState) {
        let cam = r.k == "cam" || r.k == "p3"
        if cam != (mode == .cameras) { PhoneCast.pending[id] = r; nav.tab = cam ? .cameras : .leaders; return }
        switch r.k {
        case "cam", "p3": tab = .par3; scrollTo = "p3-\(r.hole)"
        case "contests": tab = s.contests.isEmpty ? .board : .contests
        case "skins": tab = tabs(s).contains(.skins) ? .skins : .board
        case "lb", "matches": tab = .board; flight = s.flights.contains(r.fl) ? r.fl : ""
        case "indiv": tab = tabs(s).contains(.indiv) ? .indiv : .board; flight = s.flights.contains(r.fl) ? r.fl : ""
        default: tab = .board
        }
    }

    private func tabs(_ s: EventState) -> [Tab] {
        if mode == .cameras { return [.par3] }
        return [Tab.board, .indiv, .contests, .skins].filter { ($0 != .skins || (s.screens.skins && !s.format.isScramble)) && ($0 != .contests || !s.contests.isEmpty)
            && ($0 != .indiv || (s.format.indiv && s.format.hasIndividuals)) }
    }

    // ---- leaderboard ----
    @ViewBuilder private func board(_ s: EventState) -> some View {
        let stab = s.format.isStableford
        let lb = Core.leaderboard(s, s.scores, flight: flight.isEmpty ? nil : flight)
        if s.fund.on { fundBox(s.fund) }
        if s.flights.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach([""] + s.flights, id: \.self) { f in Chip(title: f.isEmpty ? "All" : "Flight \(f)", on: f == flight) { flight = f } }
                }
            }
        }
        if lb.isEmpty {
            ContentUnavailableView("No teams yet", systemImage: "person.3")
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text("Pos").frame(width: 36, alignment: .leading)
                    Text(s.format.type == "stroke" ? "Player" : "Team")
                    Spacer()
                    Text(stab ? "Pts" : "To par").frame(width: 64, alignment: .trailing)
                    Text("Thru").frame(width: 56, alignment: .trailing)
                }
                .fcLabel().padding(.horizontal, 12).padding(.vertical, 8)
                ForEach(lb) { l in
                    Divider()
                    row(s, l, stab)
                }
            }
            .background(Color.fcCard)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.fcScrim.opacity(0.10), radius: 10, y: 4)
            Text("\(s.format.name) · \(stab ? "points" : s.format.show == "gross" ? "gross" : "net")\(s.locked ? " · final results" : "") · tap a team for its card")
                .fcLabel()
        }
        sponsorStrip(s)
    }

    // ---- match play: every match as it stands, the team cup on top ----
    private static let cupRed = Color(red: 0.79, green: 0.29, blue: 0.26), cupBlue = Color(red: 0.23, green: 0.45, blue: 0.82)
    private func teamName(_ s: EventState, _ id: String) -> String {
        guard let t = s.teams.first(where: { $0.id == id }) else { return "" }
        return t.name.isEmpty ? t.players.map { $0.name.split(separator: " ").last.map(String.init) ?? $0.name }.joined(separator: " / ") : t.name
    }
    @ViewBuilder private func matchBoard(_ s: EventState) -> some View {
        let list = Core.matches(s, s.scores), c = Core.cup(s, s.scores, list)
        if c.on && !list.isEmpty {
            HStack {
                VStack(alignment: .leading, spacing: 0) { Text(c.a.uppercased()).font(.caption.weight(.bold)).foregroundStyle(Self.cupRed); Text(Core.fmtPts(c.A)).font(FCType.display(36)) }
                Spacer()
                VStack(spacing: 2) {
                    Text(c.left > 0 ? "If it finished now" : "Final").fcLabel()
                    if c.left > 0 { Text("\(Core.fmtPts(c.nowA)) – \(Core.fmtPts(c.nowB))").font(.subheadline.monospaced()) }
                    Text("\(Core.fmtPts(c.toWin)) to win").fcLabel()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) { Text(c.b.uppercased()).font(.caption.weight(.bold)).foregroundStyle(Self.cupBlue); Text(Core.fmtPts(c.B)).font(FCType.display(36)) }
            }
            .padding(14).background(Color.fcCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        if list.isEmpty {
            ContentUnavailableView("No matches yet", systemImage: "person.2", description: Text("The matches show here once the desk pairs the teams."))
        } else {
            VStack(spacing: 6) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, r in matchRow(s, r, i + 1, c.on) }
            }
            Text("\(s.format.name) · \(s.format.show == "gross" ? "gross" : "net")\(s.locked ? " · final results" : "")").fcLabel()
        }
        sponsorStrip(s)
    }
    private func matchRow(_ s: EventState, _ r: Core.MatchResult, _ n: Int, _ cupOn: Bool) -> some View {
        let w = r.winner ?? r.leader
        let wid = w == "A" ? r.a : w == "B" ? r.b : nil
        let side = wid.flatMap { id in s.teams.first { $0.id == id }?.side } ?? ""
        let fill: Color = wid == nil ? Color.fcMuted.opacity(0.18) : !cupOn ? Color.fcFlag : (side == "B" || (side.isEmpty && w == "B")) ? Self.cupBlue : Self.cupRed
        let ink: Color = wid == nil ? Color.fcInk : !cupOn ? Color.fcOnFlag : .white
        let mineA = mine.contains(r.a), mineB = mine.contains(r.b)
        return HStack(spacing: 0) {
            Text(String(n)).font(.caption.monospaced()).foregroundStyle(Color.fcMuted).frame(width: 24)
            Text(teamName(s, r.a)).font(.subheadline.weight(w == "B" ? .regular : .semibold)).foregroundStyle(w == "B" ? Color.fcMuted : Color.fcInk)
                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
            VStack(spacing: 1) {
                Text(r.done ? (r.halved ? "Halved" : r.text) : r.started ? r.text : "—").font(FCType.display(20))
                Text(r.done ? "final" : r.started ? "thru \(r.thru)" : r.thru == "—" ? "not started" : r.thru.lowercased()).font(.caption2.monospaced())
            }
            .foregroundStyle(ink).frame(width: 84).frame(maxHeight: .infinity).background(fill)
            .overlay { if r.done { Rectangle().strokeBorder(Color.fcInk, lineWidth: 2.5) } }
            Text(teamName(s, r.b)).font(.subheadline.weight(w == "A" ? .regular : .semibold)).foregroundStyle(w == "A" ? Color.fcMuted : Color.fcInk)
                .lineLimit(2).multilineTextAlignment(.trailing).frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal, 8)
        }
        .frame(minHeight: 52)
        .background(Color.fcCard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { if mineA || mineB { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.fcFlag, lineWidth: 2) } }
        .accessibilityElement(children: .combine)
    }

    // ---- Individuals (club championships): every player on their own, net or gross, by flight ----
    @ViewBuilder private func individuals(_ s: EventState) -> some View {
        let stab = s.format.isStableford, mode = imode.isEmpty ? (s.format.show.isEmpty ? "net" : s.format.show) : imode
        let fl = flight.isEmpty ? nil : flight
        let lb = Core.individuals(s, s.scores, flight: fl, mode: mode)
        let other = stab ? [] : Core.individuals(s, s.scores, flight: fl, mode: mode == "gross" ? "net" : "gross")
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if !stab { ForEach(["net", "gross"], id: \.self) { m in Chip(title: m == "net" ? "Net" : "Gross", on: m == mode) { imode = m } } }
                if s.flights.count > 1 {
                    Divider().frame(height: 20)
                    ForEach([""] + s.flights, id: \.self) { f in Chip(title: f.isEmpty ? "All" : "Flight \(f)", on: f == flight) { flight = f } }
                }
            }
        }
        if lb.isEmpty {
            ContentUnavailableView("No players yet", systemImage: "person")
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text("Pos").frame(width: 36, alignment: .leading)
                    Text("Player")
                    Spacer()
                    Text(stab ? "Pts" : mode == "gross" ? "Gross" : "Net").frame(width: 56, alignment: .trailing)
                    if !stab { Text(mode == "gross" ? "Net" : "Gross").frame(width: 52, alignment: .trailing) }
                    Text("Thru").frame(width: 44, alignment: .trailing)
                }
                .fcLabel().padding(.horizontal, 12).padding(.vertical, 8)
                ForEach(lb) { l in
                    Divider()
                    HStack(spacing: 8) {
                        Text(l.pos).font(.subheadline.weight(.bold)).foregroundStyle(Color.fcMuted).frame(width: 36, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(l.name).font(.body.weight(mine.contains(l.teamId) ? .bold : .semibold)).lineLimit(1)
                                if mine.contains(l.teamId) { YouTag() }
                            }
                            let sub = [l.sub, s.flights.count > 1 && flight.isEmpty && !l.flight.isEmpty ? "Flight \(l.flight)" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
                            if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(Color.fcMuted).lineLimit(1) }
                        }
                        Spacer(minLength: 4)
                        Text(l.played > 0 ? Core.fmtPar(l.score, stab).replacingOccurrences(of: " pts", with: "") : "—")
                            .font(FCType.display(26)).foregroundStyle(!stab && l.played > 0 && l.score < 0 ? Color.fcRed : Color.fcInk)
                            .frame(width: 56, alignment: .trailing)
                        if !stab {
                            let o = other.first { $0.key == l.key }
                            Text(o.map { $0.played > 0 ? Core.fmtPar($0.score) : "—" } ?? "—").font(.subheadline.monospaced()).foregroundStyle(Color.fcMuted).frame(width: 52, alignment: .trailing)
                        }
                        Text(l.thru).font(.subheadline.monospaced()).frame(width: 44, alignment: .trailing).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, 12).frame(minHeight: 52)
                    .background(mine.contains(l.teamId) ? Color.fcFlag.opacity(0.22) : .clear)
                    .accessibilityElement(children: .combine)
                }
            }
            .background(Color.fcCard)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.fcScrim.opacity(0.10), radius: 10, y: 4)
            Text("Every player on their own · \(stab ? "points" : "ranked by \(mode)")\(s.locked ? " · final results" : "")").fcLabel()
        }
    }

    private func row(_ s: EventState, _ l: Line, _ stab: Bool) -> some View {
        let isOpen = open == l.key
        return VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.snappy) { open = isOpen ? nil : l.key } } label: {
                HStack(spacing: 8) {
                    Group {
                        if l.pos == "1" {
                            Text("1").font(FCType.display(20)).foregroundStyle(Color.fcOnFlag)
                                .frame(width: 28, height: 28).background(Color.fcFlag, in: Circle())
                        } else {
                            Text(l.pos).font(.subheadline.weight(.bold)).foregroundStyle(Color.fcMuted)
                        }
                    }
                    .frame(width: 36, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(l.name).font(.body.weight(mine.contains(l.teamId) ? .bold : .semibold)).foregroundStyle(Color.fcInk).lineLimit(1)
                            if mine.contains(l.teamId) { YouTag() }
                        }
                        if !l.sub.isEmpty && l.sub != l.name { Text(l.sub).font(.caption).foregroundStyle(Color.fcMuted).lineLimit(1) }
                    }
                    Spacer(minLength: 4)
                    Text(l.played > 0 ? Core.fmtPar(l.score, stab).replacingOccurrences(of: " pts", with: "") : "—")
                        .font(FCType.display(28))
                        .foregroundStyle(!stab && l.played > 0 && l.score < 0 ? Color.fcRed : Color.fcInk)
                        .frame(width: 64, alignment: .trailing)
                        .contentTransition(.numericText())
                    Text(l.thru).font(.subheadline.monospaced()).foregroundStyle(Color.fcInk).frame(width: 56, alignment: .trailing).lineLimit(1).minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 12).frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(isOpen ? "Hides the card" : "Shows the card")
            if isOpen {
                let who = s.format.isScramble ? [Player(id: "T", name: l.team.name.isEmpty ? "Team" : l.team.name)] : l.team.players
                CardGrid(holes: s.course.holes.filter { Core.playHoles(s).contains($0.n) }, rows: who.map { ($0.name, s.scores[l.teamId]?[$0.id] ?? []) })
                    .padding(.horizontal, 12).padding(.bottom, 12)
                    .background(Color.fcPaper2)
            }
        }
        .background(isOpen ? Color.fcPaper2 : mine.contains(l.teamId) ? Color.fcFlag.opacity(0.22) : .clear)
    }

    private func fundBox(_ f: Fund) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(f.label.isEmpty ? "Raised today" : f.label).font(.subheadline)
                Spacer()
                if let u = URL(string: f.give), !f.give.isEmpty { Button("Give now") { web = u }.font(.subheadline.weight(.semibold)) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.dollars(f.raised)).font(FCType.display(36)).contentTransition(.numericText())
                if f.goal > 0 { Text("of \(Fmt.dollars(f.goal))").fcLabel() }
            }
            if f.goal > 0 {
                ProgressView(value: min(1, f.raised / f.goal)).tint(Color.fcRed)
                    .accessibilityLabel("\(Int(min(100, f.raised / f.goal * 100))) percent of the goal")
            }
        }
        .fcCard(padding: 14)
    }

    @ViewBuilder private func sponsorStrip(_ s: EventState) -> some View {
        let list = s.sponsors.filter { $0.spot == "title" || $0.spot == "leaderboard" }
        if !list.isEmpty {
            Text("Thank you to our sponsors").fcLabel().padding(.top, 16)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                ForEach(list) { sp in
                    Button { if let u = URL(string: sp.url), !sp.url.isEmpty { web = u } } label: {
                        SponsorBadge(sponsor: sp, height: 40).frame(maxWidth: .infinity, minHeight: 64).padding(8)
                            .background(Color.fcCard, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.fcLine))
                    }
                    .buttonStyle(.plain)
                    .disabled(sp.url.isEmpty)
                }
            }
        }
    }

    // ---- the Cameras tab ----
    // The newest replays, then every camera staff show golfers: the pro's phone (Go live), contest holes, par 3s,
    // around the club (clubhouse, 18th green), then the par 3s with no camera. No cameras at all: the Par 3s tab, as before.
    @ViewBuilder private func par3s(_ s: EventState) -> some View {
        let cams = s.camList(), shown = Set(cams.map(\.n))
        let bare = s.course.holes.filter { h in h.par == 3 && !shown.contains(h.n) && !(s.cams[h.n] != nil && s.camsOff.contains(h.n)) }
        let kinds = CamItem.Kind.allCases.filter { k in cams.contains { $0.kind == k } }
        let pick = camKind.flatMap { kinds.contains($0) ? $0 : nil }
        if cams.isEmpty && bare.isEmpty { ContentUnavailableView("No cameras", systemImage: "video.slash", description: Text("No cameras or par 3s for this course.")) }
        if kinds.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Chip(title: "All", on: pick == nil) { camKind = nil }
                    ForEach(kinds, id: \.self) { k in Chip(title: k.chip, on: pick == k) { camKind = k } }
                }
            }
        }
        let reps = Array(s.replays.filter { shown.contains($0.hole) }.prefix(8))
        if pick == nil && !reps.isEmpty {
            Text("Latest replays").fcLabel()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(reps) { r in replayTile(r) } }
            }
        }
        if s.course.holes.filter({ $0.par == 3 && (s.camShown($0.n)?.absoluteString.lowercased().contains(".m3u8") ?? false) }).count >= 2 && (pick == nil || pick == .par3) {
            Button { allPar3s = true } label: { Label("Watch all par 3s", systemImage: "rectangle.split.2x2.fill") }
                .buttonStyle(.fcDark)
        }
        ForEach(kinds.filter { pick == nil || $0 == pick }, id: \.self) { k in
            Text(k.heading).fcLabel().padding(.top, 4)
            ForEach(cams.filter { $0.kind == k }) { c in camCard(s, c) }
        }
        if !bare.isEmpty && (pick == nil || pick == .par3) {
            if !cams.isEmpty { Text(kinds.contains(.par3) ? "More par 3s" : "Par 3s").fcLabel().padding(.top, 4) }
            ForEach(bare, id: \.n) { h in holeCard(s, h, nil) }
        }
    }

    /// a replay in the Latest replays strip: plays full screen
    private func replayTile(_ r: Replay) -> some View {
        Button { replayOpen = r } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("REPLAY").font(.caption2.monospaced().weight(.bold)).padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.fcFlag, in: RoundedRectangle(cornerRadius: 2)).foregroundStyle(Color.fcOnFlag)
                    Image(systemName: "play.fill").font(.caption2).foregroundStyle(Color.fcMuted)
                }
                Text(r.label.isEmpty ? "Replay" : r.label).font(.footnote.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                Text("\(EventState.camName(r.hole)) · \(Fmt.time(r.at))").font(.caption2).foregroundStyle(Color.fcMuted)
            }
            .frame(width: 150, alignment: .leading).frame(minHeight: 74, alignment: .topLeading)
            .padding(10).background(Color.fcCard, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.fcLine))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Replay, \(EventState.camName(r.hole)). \(r.label)")
    }

    @ViewBuilder private func camCard(_ s: EventState, _ c: CamItem) -> some View {
        holeCard(s, c.n > 0 ? s.course.holes[c.n - 1] : nil, c)
    }

    /// one camera (or a par 3 with no camera): the picture, who's sending, the par 3's numbers and the hole's contests
    @ViewBuilder private func holeCard(_ s: EventState, _ h: Hole?, _ c: CamItem?) -> some View {
        let n = c?.n ?? h?.n ?? 0
        let st: HoleStats? = h.map { Core.holeStats(s, s.scores, $0.n) }
        let sp = h.flatMap { h in s.sponsors.first { $0.holes.contains(h.n) } }
        VStack(alignment: .leading, spacing: 0) {
            camera(s, hole: n, url: c?.link, title: c?.title ?? "Hole \(n)", sub: c?.sub ?? h.map { ["Par \($0.par)", $0.yds > 0 ? "\($0.yds) yds" : ""].filter { !$0.isEmpty }.joined(separator: " · ") } ?? "")
            VStack(alignment: .leading, spacing: 8) {
                if let c, c.kind == .pro {
                    Label("Live from the pro\(c.by.isEmpty ? "" : " · \(c.by)")", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption.weight(.bold)).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.fcFlag, in: Capsule()).foregroundStyle(Color.fcOnFlag)
                }
                if let h, let st {
                    Text(["SI \(h.hcp)", st.avg.map { String(format: "avg %.2f", $0) } ?? "", sp.map { "presented by \($0.name)" } ?? ""]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.footnote.monospaced()).foregroundStyle(Color.fcMuted)
                    if h.par == 3 {
                        if !st.aces.isEmpty {
                            Label("Hole in one: \(st.aces.map(\.name).joined(separator: ", "))", systemImage: "star.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Color.fcRed)
                        }
                        Divider()
                        HStack {
                            stat(st.aces.count, "Aces"); stat(st.birdie + st.eagle - st.aces.count, "Birdies"); stat(st.par0, "Pars"); stat(st.bogey + st.worse, "Over")
                        }
                    }
                    ForEach(s.contests.filter { $0.hole == h.n }) { c in contestBox(c) }
                }
            }
            .padding(14)
        }
        .background(Color.fcCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.fcScrim.opacity(0.10), radius: 10, y: 4)
        .id("p3-\(n)")
    }

    @ViewBuilder private func camera(_ s: EventState, hole: Int, url: URL?, title: String, sub: String) -> some View {
        let replays = s.replays.filter { $0.hole == hole }
        if let url, !CameraLink(hole: hole, url: url).isHLS {
            // a camera page that isn't HLS (YouTube, a camera maker's player): open it in Safari view
            Button { web = url } label: {
                ZStack {
                    LinearGradient(colors: [Color(UIColor(hex: 0x1d4a35)), Color(UIColor(hex: 0x123628))], startPoint: .top, endPoint: .bottom)
                    Label("Watch the \(title.lowercased()) camera", systemImage: "play.circle.fill").font(.headline).foregroundStyle(.white)
                }
                .aspectRatio(16 / 9, contentMode: .fit)
            }
            .buttonStyle(.plain)
            if !replays.isEmpty { CameraBox(hole: hole, camURL: nil, replays: replays).padding([.horizontal, .top], 14) }
        } else {
            CameraBox(hole: hole, camURL: url, replays: replays, title: title, sub: sub).padding([.horizontal, .top], 14)
        }
    }

    private func stat(_ n: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(n)").font(FCType.display(36))
            Text(label).fcLabel()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // ---- contests ----
    @ViewBuilder private func contests(_ s: EventState) -> some View {
        if s.contests.isEmpty { ContentUnavailableView("No contests", systemImage: "flag.2.crossed", description: Text("This tournament has no contests.")) }
        ForEach(s.contests) { c in contestBox(c).fcCard(padding: 14) }
    }

    private func contestBox(_ c: Contest) -> some View {
        let l = Core.contestLeader(c)
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(c.title) · Hole \(c.hole)").fcHeading(.headline)
            if !c.sponsor.isEmpty || c.prize > 0 {
                Text([c.sponsor.isEmpty ? nil : "Presented by \(c.sponsor)", c.prize > 0 ? "Winner gets \(c.prize) points" : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(Color.fcMuted)
            }
            if l.isEmpty { Text("No one on the board yet.").font(.footnote).foregroundStyle(Color.fcMuted) }
            // the top 5, plus your own cart's entries further down; ✓ checked by the pro, ◷ waiting
            let rows: [(offset: Int, element: ContestEntry)] = l.enumerated().filter { $0.offset < 5 || mine.contains($0.element.team) }.map { (offset: $0.offset, element: $0.element) }
            ForEach(rows, id: \.offset) { i, e in
                HStack {
                    Text("\(i + 1).").font(.subheadline.monospaced()).foregroundStyle(Color.fcMuted).frame(width: 28, alignment: .leading)
                    Text(e.name).font(.subheadline.weight(i == 0 ? .semibold : .regular))
                    Spacer()
                    Text(Core.fmtDist(c, e.dist)).font(.subheadline.monospaced())
                    if e.byGolfer || e.waiting {
                        Image(systemName: e.ok ? "checkmark" : "clock").font(.caption.weight(.bold)).foregroundStyle(e.ok ? Color.fcOK : Color.fcWarn)
                            .frame(width: 16).accessibilityLabel(e.ok ? "Checked" : "Waiting for the pro")
                    } else { Color.clear.frame(width: 16, height: 1) }
                }
                .padding(.vertical, 2).padding(.horizontal, 6)
                .background(mine.contains(e.team) ? Color.fcFlag.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, -6)
            }
            if l.contains(where: \.waiting) {
                HStack(spacing: 12) { Label("checked by the pro", systemImage: "checkmark").foregroundStyle(Color.fcOK); Label("waiting", systemImage: "clock").foregroundStyle(Color.fcWarn) }
                    .font(.caption2).labelStyle(.titleAndIcon)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ---- skins ----
    private func skins(_ s: EventState) -> some View {
        VStack(spacing: 0) {
            HStack { Text("Hole").frame(width: 44, alignment: .leading); Text("Skin"); Spacer(); Text("Score") }.fcLabel().padding(.horizontal, 12).padding(.vertical, 8)
            ForEach(Core.skins(s, s.scores), id: \.hole) { r in
                Divider()
                HStack {
                    Text("\(r.hole)").font(.subheadline.monospaced()).foregroundStyle(Color.fcMuted).frame(width: 44, alignment: .leading)
                    switch r {
                    case let .won(_, w, sc, worth):
                        Text(w.name).font(.body.weight(.semibold)) + Text(worth > 1 ? " · \(worth) skins" : "").foregroundStyle(Color.fcMuted)
                        Spacer(); Text("\(sc)").font(.body.monospaced().weight(.semibold))
                    case let .tied(_, _, sc):
                        Text("Tied, carries over"); Spacer(); Text("\(sc)").font(.body.monospaced())
                    case .open:
                        Text("Still playing").fcLabel(); Spacer()
                    }
                }
                .padding(.horizontal, 12).frame(minHeight: 46)
            }
        }
        .background(Color.fcCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.fcScrim.opacity(0.10), radius: 10, y: 4)
    }
}
