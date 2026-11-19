import SwiftUI

/// The live leaderboard (matches public/golf/live/): flight filters, tap a team for its card, fundraising bar,
/// news flash, and tabs for the par 3 cameras, contests and skins.
struct LeaderboardScreen: View {
    let id: String
    @State private var feed: EventFeed
    @State private var tab: Tab = .board
    @State private var flight = ""
    @State private var open: String?
    @State private var web: URL?
    @State private var dismissed = 0.0          // bumped when the phone banner is closed, to redraw
    @State private var scrollTo: String?
    @Environment(Router.self) private var router
    enum Tab: String, CaseIterable { case board = "Leaderboard", par3 = "Par 3s", contests = "Contests", skins = "Skins" }

    init(id: String) { self.id = id; _feed = State(initialValue: Feeds.feed(id)) }

    var body: some View {
        VStack(spacing: 0) {
            if let s = feed.state {
                GreenHeader(title: s.title, subtitle: [s.club, s.course.name != s.club ? s.course.name : "", s.date].filter { !$0.isEmpty }.joined(separator: " · ")) {
                    LivePill(online: feed.online)
                }
                if let f = s.flash, Date().timeIntervalSince1970 * 1000 - f.at < 30 * 60_000 {
                    Label(f.text, systemImage: "megaphone.fill").font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color.fcFlag).foregroundStyle(Color.fcOnFlag)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                tabBar(s)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            switch tab {
                            case .board: board(s)
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
            } else if let m = feed.missing {
                ContentUnavailableView("Not found", systemImage: "questionmark.circle", description: Text(m))
            } else {
                ProgressView("Loading the leaderboard").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.fcPaper)
        .animation(.default, value: feed.state?.flash)
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.fcGreen, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if let code = Recents.all().first(where: { $0.id == id })?.code, !code.isEmpty,
               !router.path.contains(.score(id: id, code: code)) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { router.go(.score(id: id, code: code)) } label: { Label("Scorecard", systemImage: "square.and.pencil") }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: Server.page("g/\(id)")) { Label("Share", systemImage: "square.and.arrow.up") }
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
    }

    /// "See it" / "Watch" on a phone banner: the matching tab (a camera → Par 3s, scrolled to its hole).
    private func follow(_ r: PhoneRoute, _ s: EventState) {
        switch r.k {
        case "cam", "p3": tab = .par3; scrollTo = "p3-\(r.hole)"
        case "contests": tab = .contests
        case "skins": tab = tabs(s).contains(.skins) ? .skins : .board
        case "lb": tab = .board; flight = s.flights.contains(r.fl) ? r.fl : ""
        default: tab = .board
        }
    }

    private func tabs(_ s: EventState) -> [Tab] {
        Tab.allCases.filter { $0 != .skins || (s.screens.skins && !s.format.isScramble) }
    }

    private func tabBar(_ s: EventState) -> some View {
        Picker("View", selection: $tab) { ForEach(tabs(s), id: \.self) { Text($0.rawValue).tag($0) } }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color.fcGreen)
            .colorScheme(.dark)
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
            .background(Color.fcCard, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.fcLine))
            Text("\(s.format.name) · \(stab ? "points" : s.format.show == "gross" ? "gross" : "net")\(s.locked ? " · final results" : "") · tap a team for its card")
                .fcLabel()
        }
        sponsorStrip(s)
    }

    private func row(_ s: EventState, _ l: Line, _ stab: Bool) -> some View {
        let isOpen = open == l.key
        return VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.snappy) { open = isOpen ? nil : l.key } } label: {
                HStack(spacing: 8) {
                    Text(l.pos).font(.subheadline.monospaced()).foregroundStyle(Color.fcMuted).frame(width: 36, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(l.name).font(.body.weight(.semibold)).foregroundStyle(Color.fcInk).lineLimit(1)
                        if !l.sub.isEmpty && l.sub != l.name { Text(l.sub).font(.caption).foregroundStyle(Color.fcMuted).lineLimit(1) }
                    }
                    Spacer(minLength: 4)
                    Text(l.played > 0 ? Core.fmtPar(l.score, stab).replacingOccurrences(of: " pts", with: "") : "—")
                        .font(.title3.monospaced().weight(.semibold))
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
                CardGrid(holes: s.course.holes, rows: who.map { ($0.name, s.scores[l.teamId]?[$0.id] ?? []) })
                    .padding(.horizontal, 12).padding(.bottom, 12)
                    .background(Color.fcPaper2)
            }
        }
        .background(isOpen ? Color.fcPaper2 : .clear)
    }

    private func fundBox(_ f: Fund) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(f.label.isEmpty ? "Raised today" : f.label).font(.subheadline)
                Spacer()
                if let u = URL(string: f.give), !f.give.isEmpty { Button("Give now") { web = u }.font(.subheadline.weight(.semibold)) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.dollars(f.raised)).font(.system(.title, weight: .heavy)).fontWidth(.condensed).contentTransition(.numericText())
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

    // ---- par 3s ----
    @ViewBuilder private func par3s(_ s: EventState) -> some View {
        let holes = s.course.holes.filter { $0.par == 3 }
        if holes.isEmpty { ContentUnavailableView("No par 3s", systemImage: "flag", description: Text("No par 3s are set for this course.")) }
        ForEach(holes, id: \.n) { h in
            let st = Core.holeStats(s, s.scores, h.n)
            let sp = s.sponsors.first { $0.holes.contains(h.n) }
            VStack(alignment: .leading, spacing: 0) {
                camera(s, hole: h.n)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hole \(h.n)").fcHeading(.title)
                    Text(["Par 3", h.yds > 0 ? "\(h.yds) yds" : "", "SI \(h.hcp)", st.avg.map { String(format: "avg %.2f", $0) } ?? "", sp.map { "presented by \($0.name)" } ?? ""]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.footnote.monospaced()).foregroundStyle(Color.fcMuted)
                    if !st.aces.isEmpty {
                        Label("Hole in one: \(st.aces.map(\.name).joined(separator: ", "))", systemImage: "star.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Color.fcRed)
                    }
                    Divider()
                    HStack {
                        stat(st.aces.count, "Aces"); stat(st.birdie + st.eagle - st.aces.count, "Birdies"); stat(st.par0, "Pars"); stat(st.bogey + st.worse, "Over")
                    }
                    ForEach(s.contests.filter { $0.hole == h.n }) { c in contestBox(c) }
                }
                .padding(14)
            }
            .background(Color.fcCard, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.fcLine))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .id("p3-\(h.n)")
        }
    }

    @ViewBuilder private func camera(_ s: EventState, hole: Int) -> some View {
        let url = s.cams[hole].flatMap(URL.init(string:))
        let replays = s.replays.filter { $0.hole == hole }
        if let url, !CameraLink(hole: hole, url: url).isHLS {
            // a camera page that isn't HLS (YouTube, a camera maker's player): open it in Safari view
            Button { web = url } label: {
                ZStack {
                    LinearGradient(colors: [Color(UIColor(hex: 0x1d4a35)), Color(UIColor(hex: 0x123628))], startPoint: .top, endPoint: .bottom)
                    Label("Watch the hole \(hole) camera", systemImage: "play.circle.fill").font(.headline).foregroundStyle(.white)
                }
                .aspectRatio(16 / 9, contentMode: .fit)
            }
            .buttonStyle(.plain)
            if !replays.isEmpty { CameraBox(hole: hole, camURL: nil, replays: replays).padding([.horizontal, .top], 14) }
        } else {
            CameraBox(hole: hole, camURL: url, replays: replays).padding([.horizontal, .top], 14)
        }
    }

    private func stat(_ n: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(n)").font(.system(.title, weight: .heavy)).fontWidth(.condensed)
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
            if !c.sponsor.isEmpty { Text("Presented by \(c.sponsor)").font(.footnote).foregroundStyle(Color.fcMuted) }
            if l.isEmpty { Text("No one on the board yet.").font(.footnote).foregroundStyle(Color.fcMuted) }
            ForEach(Array(l.prefix(5).enumerated()), id: \.offset) { i, e in
                HStack {
                    Text("\(i + 1).").font(.subheadline.monospaced()).foregroundStyle(Color.fcMuted).frame(width: 24, alignment: .leading)
                    Text(e.name).font(.subheadline.weight(i == 0 ? .semibold : .regular))
                    Spacer()
                    Text(Core.fmtDist(c, e.dist)).font(.subheadline.monospaced())
                }
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
        .background(Color.fcCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.fcLine))
    }
}
