import SwiftUI
import UIKit

/// The cart scorecard: "This hole" (the hole strip in playing order, the hole, its yards and sponsor, and each
/// player's score with − / +) and "Your round" (where the team stands, the teams around it, and the card).
/// Works with no signal: scores wait on the phone and send when the connection comes back.
/// The tournament screen starts and stops the model, so scores keep sending from any tab.
struct ScorecardScreen: View {
    @Bindable var model: ScorecardModel
    @State private var camera: CameraLink?
    @State private var dismissed = 0.0
    @State private var replay: Replay?
    @State private var replaySeen = 0.0
    @State private var page = Page.hole
    @State private var coverSeen = Set<String>()
    @State private var entering: Contest?
    @Environment(Router.self) private var router
    @Environment(TourNav.self) private var nav
    enum Page: Hashable { case hole, round }

    var body: some View {
        Group {
            if let s = model.state, let t = model.team {
                card(s, t)
            } else if let err = model.codeError {
                message("Code not found", err, icon: "exclamationmark.triangle")
            } else if model.state != nil, !model.teams.isEmpty {
                message("Not found", "This scorecard isn’t part of the tournament any more. Ask the tournament desk for your cart card.", icon: "questionmark.circle")
            } else if let m = model.feed.missing {
                message("Not found", m, icon: "questionmark.circle")
            } else {
                ProgressView("Getting your scorecard").frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.fcPaper)
            }
        }
        .toast($model.toast)
        .sensoryFeedback(.selection, trigger: model.changes)
        .sensoryFeedback(.success, trigger: model.aces)
        .sensoryFeedback(.warning, trigger: model.nudge)
        .overlay { if model.celebrating { AceCelebration { model.celebrating = false } } }
        .alert(model.nudge.map { n in n.from.map { "From \($0)" } ?? (n.team == "*" ? "A note for everyone" : n.player != nil && n.player == model.me ? "A note for you" : "A note for your cart") } ?? "", isPresented: Binding(get: { model.nudge != nil }, set: { if !$0 { model.nudge = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.nudge?.text ?? "") }
        .fullScreenCover(item: $replay) { r in
            ReplayFullscreen(replay: r, camURL: model.state?.cams[r.hole].flatMap(URL.init(string:)).flatMap { CameraLink(hole: r.hole, url: $0).isHLS ? $0 : nil },
                             replays: model.state?.replays.filter { $0.hole == r.hole } ?? [])
        }
        .sheet(item: $camera) { l in CameraSheet(link: l, replays: model.state?.replays.filter { $0.hole == l.hole } ?? []) }
        .sheet(item: $entering) { c in ContestEntrySheet(model: model, contest: c).presentationDetents([.medium, .large]) }
    }

    @ViewBuilder private var syncPill: some View {
        if model.synced {
            Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy))
                .frame(width: 26, height: 26)
                .background(Color(UIColor(hex: 0x5cc48a)).opacity(0.2), in: Circle())
                .foregroundStyle(Color(UIColor(hex: 0x8fe0b0)))
                .accessibilityLabel("All scores saved")
        } else {
            syncWaiting
        }
    }

    private var syncWaiting: some View {
        HStack(spacing: 5) {
            Circle().fill(model.synced ? Color(UIColor(hex: 0x5cc48a)) : Color.fcFlag).frame(width: 7, height: 7)
            Text(model.synced ? "Saved" : model.syncText).lineLimit(1)
        }
        .font(.caption2.weight(.bold)).tracking(0.8).textCase(.uppercase)
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background((model.synced ? Color(UIColor(hex: 0x5cc48a)) : Color.fcFlag).opacity(0.18), in: Capsule())
        .foregroundStyle(model.synced ? Color(UIColor(hex: 0x8fe0b0)) : Color.fcFlag)
        .accessibilityLabel(model.synced ? "All scores saved" : model.syncText)
    }

    private func message(_ title: String, _ text: String, icon: String) -> some View {
        ContentUnavailableView { Label(title, systemImage: icon) } description: { Text(text) } actions: {
            Button("Back to home") { router.path = [] }.buttonStyle(.fc(.dark, full: false))
        }
        .background(Color.fcPaper)
    }

    // ---- the card ----
    private func card(_ s: EventState, _ t: Team) -> some View {
        let h = model.currentHole()
        let H = s.course.holes[h - 1]
        return VStack(spacing: 0) {
            TourHeader(state: s, title: s.title, subtitle: teamLine(s, t)) {
                syncPill
            } below: {
                VStack(spacing: 10) {
                    if model.teams.count > 1 { teamTabs(s) }
                    HeaderSwitch(options: [(Page.hole, "This hole"), (Page.round, "Your round")], selection: $page)
                    if page == .hole { strip(s, t, h) }
                }
            }
            if s.locked {
                Text("Scoring is closed. The results are final.").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(8).background(Color.fcRed)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if page == .hole { holePage(s, t, h, H).id("top") } else { roundPage(s, t) }
                    }
                    .padding(16)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await model.feed.refresh(); model.send() }
                .onChange(of: h) { _, _ in withAnimation { proxy.scrollTo("top", anchor: .top) } }
            }
            .overlay(alignment: .bottom) {
                if let r = PhoneCast.current(s, id: model.id), dismissed >= 0 {
                    PhoneBanner(state: s, route: r, go: { r in
                        PhoneCast.pending[model.id] = r
                        nav.tab = r.k == "cam" || r.k == "p3" ? .cameras : .leaders
                    }, close: { PhoneCast.dismiss(r, id: model.id); withAnimation { dismissed += 1 } })
                    .padding(.bottom, 8)
                }
            }
            .animation(.spring(duration: 0.35), value: s.live.phone)
            .overlay(alignment: .top) {
                // a new par 3 replay: once, one tap plays it full screen
                if let r = ReplayCast.current(s, id: model.id), replaySeen >= 0 {
                    ReplayBanner(replay: r, watch: { ReplayCast.seen(r, id: model.id); replay = r; replaySeen += 1 },
                                 close: { ReplayCast.seen(r, id: model.id); withAnimation { replaySeen += 1 } })
                        .padding(.top, 8)
                }
            }
            .animation(.spring(duration: 0.35), value: s.replays.first?.id)
            if page == .hole { bottomBar(t, h) }
        }
        .background(Color.fcPaper)
        .overlay { coverPopup(s, t) }
        // once, for a cart of two or more: which golfer holds this phone, so the pro shop can send a note to just them
        .confirmationDialog("Which one are you?", isPresented: Binding(get: { model.me == nil && t.players.count > 1 && !coverShowing(s, t) && model.nudge == nil },
                                                                       set: { if !$0 && model.me == nil { model.me = "-" } }), titleVisibility: .visible) {
            ForEach(t.players, id: \.id) { p in Button(p.name) { model.me = p.id } }
            Button("Skip", role: .cancel) { model.me = "-" }
        } message: { Text("So the pro shop can send a note to you, not the whole cart.") }
    }

    private func coverShowing(_ s: EventState, _ t: Team) -> Bool {
        let key = "flagcast.cover.\(s.id)"
        let scored = s.scorers(t).contains { p in (model.myScores()[t.id]?[p.id] ?? []).contains { $0 != nil } }
        return s.photos.coverURL != nil && !scored && !coverSeen.contains(key) && !UserDefaults.standard.bool(forKey: key)
    }

    /// The club's welcome photo, once per tournament on this phone, before the cart's first score.
    @ViewBuilder private func coverPopup(_ s: EventState, _ t: Team) -> some View {
        let key = "flagcast.cover.\(s.id)"
        let scored = s.scorers(t).contains { p in (model.myScores()[t.id]?[p.id] ?? []).contains { $0 != nil } }
        if s.photos.coverURL != nil, !scored, !coverSeen.contains(key), !UserDefaults.standard.bool(forKey: key) {
            let close = { UserDefaults.standard.set(true, forKey: key); withAnimation { _ = coverSeen.insert(key) } }
            ZStack {
                Color.black.opacity(0.5).ignoresSafeArea().onTapGesture(perform: close)
                VStack(spacing: 12) {
                    CoverCard(state: s)
                    Button("Let’s play", action: close).buttonStyle(.fc(.primary, full: true))
                }
                .padding(14)
                .background(Color.fcCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(24)
            }
            .transition(.opacity)
        }
    }

    // ---- this hole ----
    @ViewBuilder private func holePage(_ s: EventState, _ t: Team, _ h: Int, _ H: Hole) -> some View {
        // one screen, no scrolling: the hole with its yards on the green, the scores, then small tiles for the
        // hole's sponsor and contests. The club's welcome photo shows once, as a pop-up (coverPopup).
        HoleCard(state: s, hole: H, onHole: { d in
            let ord = model.order(t), i = ord.firstIndex(of: model.currentHole()) ?? 0
            model.hole = ord[max(0, min(ord.count - 1, i + d))]
        }, scorer: model, camera: s.cams[h].flatMap(URL.init(string:)).map { u in { camera = CameraLink(hole: h, url: u) } })
        if let r = myMatch(s, t) { matchPill(s, t, r) }
        VStack(spacing: 0) {
            let ps = s.scorers(t), tight = ps.count > 2
            HStack {
                Text("Scores")
                Spacer()
                if !s.locked { Text("Tap the number for par") }
            }
            .font(.caption2.weight(.semibold)).tracking(0.8).textCase(.uppercase).foregroundStyle(Color.fcMuted)
            .padding(.top, 10)
            ForEach(Array(ps.enumerated()), id: \.element.id) { i, p in
                playerRow(s, p, H, tight: tight, team: t)
                if i < ps.count - 1 { Divider().overlay(Color.fcLine) }
            }
        }
        .padding(.horizontal, 14)
        .fcCard(padding: 0)
        extras(s, h)
    }

    /// The hole's sponsor, the turn sponsor on 10 and the hole's contests, as small tiles two to a row.
    @ViewBuilder private func extras(_ s: EventState, _ h: Int) -> some View {
        let sp = s.sponsors.first { $0.spot == "hole" && $0.holes.contains(h) } ?? s.sponsors.first { $0.holes.contains(h) }
        let turn = h == 10 ? s.sponsors.first { $0.spot == "turn" } : nil
        // contests golfers enter themselves get a full-width card with Enter my drive / Enter my shot
        let mine = s.contests.filter { $0.hole == h && $0.golfersEnter && !s.locked }
        let cs = s.contests.filter { $0.hole == h && !($0.golfersEnter && !s.locked) }
        let tiles = (sp == nil ? 0 : 1) + (turn == nil ? 0 : 1) + cs.count
        ForEach(mine) { c in contestCard(c) }
        if tiles > 0 {
            // one tile gets the whole width, so a sponsor's name fits on one line
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: tiles == 1 ? 1 : 2), spacing: 8) {
                if let sp {
                    SponsorTile(sponsor: sp, lead: "Presented by", banner: s.photos.sponsor(sp.id)) { model.hits.tap(sp.id) }
                        .onAppear { model.hits.view(sp.id, once: "\(sp.id):\(h)") }
                }
                if let turn {
                    SponsorTile(sponsor: turn, lead: "At the turn", banner: s.photos.sponsor(turn.id)) { model.hits.tap(turn.id) }
                        .onAppear { model.hits.view(turn.id, once: "\(turn.id):turn") }
                }
                ForEach(cs) { c in contestTile(c) }
            }
        }
    }

    /// A contest golfers enter themselves: the leader, this cart's entries (✓ on the board, ◷ waiting for the pro), and the button.
    private func contestCard(_ c: Contest) -> some View {
        let top = Core.contestLeader(c).first
        let ours = c.entries.filter { $0.team == model.teamId }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: c.isLongDrive ? "arrow.up.right" : "scope").font(.footnote.weight(.bold)).foregroundStyle(Color.fcFlag)
                    .frame(width: 28, height: 28).background(Color.fcFlag.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(c.isLongDrive ? "Long drive" : "Closest to the pin") · this hole").font(.subheadline.weight(.semibold))
                    if !c.sponsor.isEmpty || c.prize > 0 {
                        Text([c.sponsor.isEmpty ? nil : "Presented by \(c.sponsor)", c.prize > 0 ? "Winner gets \(c.prize) points" : nil].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(Color.fcMuted).lineLimit(1)
                    }
                }
            }
            HStack { Text(top.map { "Leader: \($0.name)" } ?? "No one on the board yet").font(.footnote).foregroundStyle(Color.fcMuted); Spacer()
                if let top { Text(Core.fmtDist(c, top.dist)).font(.footnote.monospaced()) } }
            ForEach(ours, id: \.self) { e in
                HStack(spacing: 6) {
                    Text(e.name).font(.footnote); Spacer(); Text(Core.fmtDist(c, e.dist)).font(.footnote.monospaced())
                    Image(systemName: e.ok ? "checkmark.circle.fill" : "clock").font(.footnote).foregroundStyle(e.ok ? Color.fcOK : Color.fcWarn)
                        .accessibilityLabel(e.ok ? "On the board" : "Waiting for the pro to check it")
                }
            }
            Button { entering = c } label: {
                Text(c.isLongDrive ? "Enter my drive" : "Enter my shot").font(.subheadline.weight(.bold)).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent).tint(Color.fcFlag).foregroundStyle(Color.fcOnFlag)
        }
        .padding(12)
        .background(Color.fcCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.fcFlag, lineWidth: 1.5))
    }

    private func contestTile(_ c: Contest) -> some View {
        let top = Core.contestLeader(c).first
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: c.isLongDrive ? "arrow.up.right" : "scope").font(.footnote.weight(.bold))
                .frame(width: 26, height: 26).background(Color.fcFlag.opacity(0.25), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text((c.isLongDrive ? "Long drive" : "Closest to pin") + (c.sponsor.isEmpty ? "" : " · \(c.sponsor)"))
                    .font(.caption).foregroundStyle(Color.fcMuted).lineLimit(1)
                Text(top.map { "\($0.name), \(Core.fmtDist(c, $0.dist))" } ?? "No one yet").font(.footnote.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(10)
        .background(Color.fcCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("A marshal measures at the green.")
    }

    // ---- match play ----
    /// this team's match, with what this phone has entered
    private func myMatch(_ s: EventState, _ t: Team) -> Core.MatchResult? {
        guard s.format.isMatch, let m = s.matches.first(where: { $0.a == t.id || $0.b == t.id }) else { return nil }
        return Core.matchPlay(s, model.myScores(), m)
    }
    private func opponent(_ s: EventState, _ t: Team, _ r: Core.MatchResult) -> String {
        guard let o = s.team(r.a == t.id ? r.b : r.a) else { return "" }
        return o.name.isEmpty ? o.players.map { $0.name.split(separator: " ").last.map(String.init) ?? $0.name }.joined(separator: " / ") : o.name
    }
    private func stateColor(_ state: String) -> Color { ["up", "won"].contains(state) ? Color(red: 0.18, green: 0.62, blue: 0.38) : ["down", "lost"].contains(state) ? Color.fcRed : Color.fcInk }
    /// one line on the hole page: "2 UP · thru 7 · v Park / Ortiz"
    private func matchPill(_ s: EventState, _ t: Team, _ r: Core.MatchResult) -> some View {
        let f = Core.matchFor(r, t.id)
        return HStack(spacing: 8) {
            Text(f.text).font(FCType.display(22)).foregroundStyle(stateColor(f.state))
            Text(r.done ? "final" : r.started ? "thru \(r.thru)\(r.dormie ? " · dormie" : "")" : "").font(.caption.monospaced()).foregroundStyle(Color.fcMuted)
            Spacer(minLength: 4)
            Text("v \(opponent(s, t, r))").font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.fcCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.fcFlag, lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }
    /// the round page's match card: the state, a square a hole (won, lost, halved, a dot for a stroke) and the cup
    private func matchCard(_ s: EventState, _ t: Team, _ r: Core.MatchResult) -> some View {
        let f = Core.matchFor(r, t.id), me = r.a == t.id ? "A" : "B"
        let c = s.format.cup.on ? Core.cup(s, model.myScores()) : nil
        let green = Color(red: 0.18, green: 0.62, blue: 0.38)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("You v \(opponent(s, t, r))").fcLabel().lineLimit(1)
                    Text(f.text).font(FCType.display(44)).foregroundStyle(stateColor(f.state)).contentTransition(.numericText())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(r.done ? (r.toPlay > 0 ? "after \(r.played)" : "final") : r.started ? "thru \(r.thru)" : "").fcLabel()
                    Text(r.done ? (r.toPlay > 0 ? "Match over" : "") : r.started ? "\(r.toPlay) to play\(r.dormie ? " · dormie" : "")" : "Not started").font(.subheadline)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 9), spacing: 4) {
                ForEach(r.holes, id: \.hole) { h in
                    let res = h.r == me ? "w" : h.r == "H" ? "h" : h.r == nil ? "" : "l"
                    let stroke = (me == "A" ? h.sa : h.sb).values.contains { $0 > 0 }
                    Text(String(h.hole)).font(.caption2.monospaced())
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .foregroundStyle(res == "w" || res == "l" ? .white : Color.fcInk)
                        .background(res == "w" ? green : res == "l" ? Color.fcRed : res == "h" ? Color.fcMuted.opacity(0.4) : Color.fcMuted.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(alignment: .topTrailing) { if stroke { Circle().fill(Color.fcFlag).frame(width: 5, height: 5).padding(3) } }
                        .opacity(h.after ? 0.35 : 1)
                }
            }
            Text(r.done && r.toPlay > 0 ? "Holes after the match is over don’t count for it." : "Gold dot: you get a stroke there. Strokes are off the lowest handicap in your match.").font(.caption).foregroundStyle(Color.fcMuted)
            if let c {
                HStack {
                    Text("\(c.a) \(Core.fmtPts(c.A))").font(FCType.display(22)).foregroundStyle(Color(red: 0.79, green: 0.29, blue: 0.26))
                    Spacer()
                    Text(c.left > 0 ? "\(c.left) still playing" : "Final").fcLabel()
                    Spacer()
                    Text("\(c.b) \(Core.fmtPts(c.B))").font(FCType.display(22)).foregroundStyle(Color(red: 0.23, green: 0.45, blue: 0.82))
                }
            }
            Button("Every match") { nav.tab = .leaders }.font(.subheadline.weight(.semibold)).tint(Color.fcPrimary)
        }
        .fcCard(padding: 14)
    }

    // ---- your round ----
    @ViewBuilder private func roundPage(_ s: EventState, _ t: Team) -> some View {
        let l = model.line(), stab = s.format.isStableford
        let lb = Core.leaderboard(s, model.myScores())
        if let r = myMatch(s, t) {
            matchCard(s, t, r)
        } else {
        HStack(alignment: .top, spacing: 0) {
            summary(stab ? "Points" : s.format.show == "gross" ? "Gross to par" : "Net to par",
                    l.map { $0.played > 0 ? Core.fmtPar($0.score, stab).replacingOccurrences(of: " pts", with: "") : "—" } ?? "—",
                    red: (l?.score ?? 0) < 0 && !stab && (l?.played ?? 0) > 0)
            Rectangle().fill(Color.fcLine).frame(width: 1).padding(.vertical, 4)
            summary("Position", l.map { $0.pos.isEmpty ? "—" : $0.pos } ?? "—", sub: lb.isEmpty ? "" : "of \(lb.count)")
            Rectangle().fill(Color.fcLine).frame(width: 1).padding(.vertical, 4)
            summary("Thru", l.map { $0.played > 0 ? $0.thru : "—" } ?? "—")
        }
        .fcCard(padding: 14)
        .accessibilityElement(children: .combine)

        if let k = lb.firstIndex(where: { $0.teamId == t.id }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Around you").fcLabel()
                    Spacer()
                    Button("Full leaderboard") { nav.tab = .leaders }.font(.subheadline.weight(.semibold)).tint(Color.fcPrimary)
                }
                .padding(.bottom, 6)
                ForEach(Array(lb[max(0, k - 1)...min(lb.count - 1, k + 1)].enumerated()), id: \.element.key) { _, x in
                    let me = x.teamId == t.id
                    HStack(spacing: 10) {
                        Text(x.pos.isEmpty ? "—" : x.pos).font(.subheadline.weight(.bold)).foregroundStyle(me ? Color.fcInk : Color.fcMuted).frame(width: 32, alignment: .leading)
                        Text(x.name).font(.body.weight(me ? .bold : .semibold)).lineLimit(1)
                        if me { YouTag() }
                        Spacer(minLength: 4)
                        Text(x.played > 0 ? Core.fmtPar(x.score, stab).replacingOccurrences(of: " pts", with: "") : "—")
                            .font(.body.weight(.bold)).foregroundStyle(!stab && x.played > 0 && x.score < 0 ? Color.fcRed : Color.fcInk)
                        Text(x.thru).font(.footnote.monospacedDigit()).foregroundStyle(Color.fcMuted).frame(width: 30, alignment: .trailing)
                    }
                    .padding(.vertical, 10).padding(.horizontal, me ? 14 : 0)
                    .background(me ? Color.fcFlag.opacity(0.22) : .clear)
                    .padding(.horizontal, me ? -14 : 0)
                }
            }
            .fcCard(padding: 14)
        }
        }

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your card").fcLabel()
                Spacer()
                Text("Cart \(model.code)").font(.caption.monospaced()).foregroundStyle(Color.fcMuted)
            }
            CardGrid(holes: s.course.holes.filter { Core.playHoles(s).contains($0.n) },
                     rows: s.scorers(t).map { p in (Fmt.firstName(p.name), (model.myScores()[t.id]?[p.id]) ?? []) },
                     showTotal: true)
        }
        .fcCard(padding: 14)
    }

    private func summary(_ label: String, _ value: String, sub: String = "", red: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(label).fcLabel().lineLimit(1).minimumScaleFactor(0.7)
            Text(value).font(FCType.display(48)).foregroundStyle(red ? Color.fcRed : Color.fcInk).lineLimit(1).minimumScaleFactor(0.5)
                .contentTransition(.numericText())
            if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(Color.fcMuted) }
        }
        .frame(maxWidth: .infinity)
    }

    private func teamTabs(_ s: EventState) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.teams, id: \.self) { id in
                    if let x = s.team(id) {
                        let on = id == model.teamId
                        Button { model.switchTeam(id) } label: {
                            Text(x.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                                .padding(.horizontal, 14).frame(minHeight: 34)
                                .background(on ? Color.fcFlag : .clear, in: Capsule())
                                .overlay(Capsule().stroke(on ? Color.fcFlag : Color.fcOnGreenMuted, lineWidth: 1))
                                .foregroundStyle(on ? Color.fcOnFlag : Color.fcOnGreen)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func strip(_ s: EventState, _ t: Team, _ cur: Int) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.order(t), id: \.self) { n in
                        let par = s.course.holes[n - 1].par, on = n == cur, done = model.holeDone(n)
                        Button { model.hole = n } label: {
                            VStack(spacing: 2) {
                                Text("\(n)").font(FCType.display(24))
                                Text(on ? "PAR \(par)" : "P\(par)").font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(on ? Color.fcOnFlag.opacity(0.8) : done ? Color.white.opacity(0.85) : par == 3 ? Color.fcFlag : Color.fcOnGreenMuted)
                            }
                            .frame(width: on ? 52 : 44, height: 52)
                            .foregroundStyle(on ? Color.fcOnFlag : Color.fcOnGreen)
                            .background(on ? Color.fcFlag : done ? Color(UIColor(hex: 0x2f8a57)) : Color.white.opacity(0.1),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .id(n)
                        .accessibilityLabel("Hole \(n), par \(par)\(done ? ", done" : "")")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            .padding(.horizontal, -16).contentMargins(.horizontal, 16, for: .scrollContent)
            .onAppear { proxy.scrollTo(cur, anchor: .center) }
            .onChange(of: cur) { _, n in withAnimation { proxy.scrollTo(n, anchor: .center) } }
        }
    }

    /// "Team name · Drew & Riley" under the tournament name, so the cart always sees its team.
    private func teamLine(_ s: EventState, _ t: Team) -> String {
        let names = t.players.map { Fmt.firstName($0.name) }.joined(separator: " & ")
        return t.name.isEmpty ? names : "\(t.name) · \(names)"
    }

    private func playerRow(_ s: EventState, _ p: Player, _ H: Hole, tight: Bool = false, team: Team? = nil) -> some View {
        let v = model.value(p.id, H.n)
        // match play: strokes off the lowest player in the match, not the player's full handicap
        let rel = team.flatMap { t in myMatch(s, t)?.strokes["\(t.id):\(p.id)"] }
        let st = Core.strokesOn(rel ?? Core.playing(p.hcp, s.format.allowance), H.hcp)
        let set = v != nil
        let shown = !set ? "\(H.par)" : v == 0 ? "PU" : "\(v!)"
        let m = Core.mark(v, H.par)
        let under = m == .birdie || m == .eagle
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(p.name).font(.title3.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
                    // strokes on this hole sit beside the name, where they can't be cut off
                    if st > 0 {
                        Text("\(String(repeating: "●", count: st)) \(st)").font(.footnote.weight(.bold)).foregroundStyle(Color.fcRed).fixedSize()
                            .accessibilityLabel("Gets \(st) stroke\(st > 1 ? "s" : "") here")
                    } else if st < 0 {
                        Text("+\(-st)").font(.footnote.weight(.bold)).foregroundStyle(Color.fcMuted).fixedSize()
                            .accessibilityLabel("Gives \(-st) stroke\(st < -1 ? "s" : "") back here")
                    }
                }
                HStack(spacing: 12) {
                    Group {
                        Button("Picked up") { withAnimation { model.pickedUp(p.id) } }
                        if set { Button("Clear") { withAnimation { model.clear(p.id) } } }
                    }
                    .fontWeight(.semibold).tint(Color.fcPrimary).buttonStyle(.borderless)
                }
                .font(.footnote).foregroundStyle(Color.fcMuted).lineLimit(1).minimumScaleFactor(0.8)
                if let ix = p.index {
                    // GHIN: Handicap Index, tee and the course handicap the server worked out from them
                    let tee = s.course.tees.first { $0.id == p.tee }?.name ?? ""
                    Text("Index \(Core.fmtIndex(ix))\(tee.isEmpty ? "" : " · \(tee)") · CH \(Core.fmtIndex(p.hcp))")
                        .font(.caption2.monospaced()).foregroundStyle(Color.fcMuted).lineLimit(1).minimumScaleFactor(0.75)
                }
            }
            Spacer(minLength: 2)
            stepButton("minus", "One fewer for \(p.name)", tight: tight) { model.step(p.id, -1) }
            Button { model.step(p.id, 0) } label: {
                Text(shown)
                    .font(FCType.display(v == 0 ? 26 : tight ? 34 : 38))
                    .frame(width: tight ? 50 : 56, height: tight ? 50 : 56)
                    .foregroundStyle(!set ? Color.fcMuted : under ? Color.fcRed : Color.fcInk)
                    .background {
                        if under { Circle().stroke(Color.fcRed, lineWidth: 3) }
                        else if m == .bogey || m == .double { RoundedRectangle(cornerRadius: 12).stroke(Color.fcInk, lineWidth: m == .double ? 3 : 2) }
                        else if set { Circle().fill(Color.fcPaper2) }
                        else { RoundedRectangle(cornerRadius: 14).stroke(Color.fcLine, style: StrokeStyle(lineWidth: 2, dash: [5, 4])) }
                    }
                    .contentTransition(.numericText())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(set ? "\(p.name) score \(shown)" : "Tap to enter par for \(p.name)")
            stepButton("plus", "One more for \(p.name)", tight: tight) { model.step(p.id, 1) }
        }
        .padding(.vertical, tight ? 6 : 10)
        .animation(.snappy(duration: 0.2), value: v)
    }

    private func stepButton(_ icon: String, _ label: String, tight: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title2.weight(.semibold)).frame(width: tight ? 42 : 46, height: tight ? 42 : 46)
                .background(Color.fcPaper2, in: Circle())
                .foregroundStyle(Color.fcInk)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func bottomBar(_ t: Team, _ h: Int) -> some View {
        let ord = model.order(t), i = ord.firstIndex(of: h) ?? 0, last = ord.count - 1
        return HStack(spacing: 10) {
            // on your first hole there's nothing to go back to, so it's just the arrow (greyed out)
            Button { model.hole = ord[max(0, i - 1)] } label: {
                Group {
                    if i == 0 { Image(systemName: "chevron.left").font(.body.weight(.bold)) }
                    else { Label("\(ord[max(0, i - 1)])", systemImage: "chevron.left").labelStyle(LeadingIcon()) }
                }
                .lineLimit(1).fixedSize().frame(minWidth: 40)
            }
                .buttonStyle(FCButton(kind: .plain, full: false)).disabled(i == 0)
                .accessibilityLabel(i == 0 ? "Back" : "Back to hole \(ord[max(0, i - 1)])")
            Button {
                if i == last { page = .round; return }
                if let s = model.state {
                    let missing = s.scorers(t).filter { model.value($0.id, h) == nil }
                    if !missing.isEmpty { model.toast = "No score yet for \(missing.map { Fmt.firstName($0.name) }.joined(separator: " and ")) on hole \(h)." }
                }
                model.hole = ord[min(last, i + 1)]
            } label: {
                Label(i == last ? "See your round" : "Next: hole \(ord[min(last, i + 1)])", systemImage: i == last ? "flag.checkered" : "chevron.right")
                    .labelStyle(TrailingIcon())
            }
            .buttonStyle(.fcDark)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.fcPaper)
        // a soft fade above the bar, so a card cut off at the bottom reads as "more below"
        .overlay(alignment: .top) {
            LinearGradient(colors: [Color.fcPaper.opacity(0), Color.fcPaper], startPoint: .top, endPoint: .bottom)
                .frame(height: 18).offset(y: -18).allowsHitTesting(false)
        }
    }
}

/// The YOU tag on your own team.
struct YouTag: View {
    var body: some View {
        Text("YOU").font(.system(size: 10, weight: .heavy)).tracking(0.6)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color.fcFlag, in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(Color.fcOnFlag)
            .accessibilityLabel("Your team")
    }
}

struct LeadingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View { HStack(spacing: 3) { configuration.icon.font(.footnote.weight(.bold)); configuration.title } }
}

struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View { HStack(spacing: 6) { configuration.title; configuration.icon } }
}

/// A big HOLE IN ONE banner with confetti. Tap to close; it closes itself after a few seconds.
struct AceCelebration: View {
    var done: () -> Void
    @State private var show = false
    var body: some View {
        ZStack {
            Color.black.opacity(show ? 0.45 : 0).ignoresSafeArea()
            Confetti().ignoresSafeArea()
            VStack(spacing: 8) {
                Image(systemName: "flag.fill").font(.system(size: 44)).foregroundStyle(Color.fcFlag)
                Text("Hole in one!").font(FCType.display(46)).textCase(.uppercase).foregroundStyle(.white)
                Text("It’s on the big screens now.").font(.headline).foregroundStyle(Color.fcOnGreenMuted)
            }
            .padding(28)
            .background(Color.fcGreen, in: RoundedRectangle(cornerRadius: 22))
            .scaleEffect(show ? 1 : 0.6).opacity(show ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { done() }
        .onAppear { withAnimation(.spring(duration: 0.5, bounce: 0.4)) { show = true } }
        .task { try? await Task.sleep(for: .seconds(4.5)); done() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// The hole at the top of the scorecard: its picture from the course map (tee at the bottom, green at the top) with
/// HOLE 7 in big white letters, par, yards and stroke index; a green card when the course isn't mapped.
/// "Welcome to <tournament>" on the club's cover photo
struct CoverCard: View {
    let state: EventState
    @State private var photo: UIImage?
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.fcGreen.overlay { if let photo { Image(uiImage: photo).resizable().aspectRatio(contentMode: .fill) } }.clipped()
            LinearGradient(colors: [Color.fcScrim.opacity(0.8), Color.fcScrim.opacity(0)], startPoint: .bottom, endPoint: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text("WELCOME TO").font(.caption2.monospaced()).tracking(1.5).opacity(0.85)
                Text(state.title).font(FCType.display(30)).textCase(.uppercase).lineLimit(2).minimumScaleFactor(0.6)
            }
            .foregroundStyle(.white).shadow(color: .black.opacity(0.4), radius: 6, y: 1)
            .padding(.horizontal, 16).padding(.bottom, 12)
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: state.photos.cover) { photo = await ClubPhoto.load(state.photos.coverURL) }
        .accessibilityElement(children: .combine)
    }
}

/// The hole at the top of the scorecard: its picture (the club's photo, else the course map's satellite picture)
/// with HOLE 7, par, yards and index, the yards on a drawn green (and today's pin when the desk set one), then
/// Full screen GPS, Use my GPS and the hole's camera.
struct HoleCard: View {
    let state: EventState
    let hole: Hole
    var onHole: (Int) -> Void
    var scorer: ScorecardModel? = nil
    var camera: (() -> Void)? = nil
    @State private var photo: UIImage?
    @State private var loc = Locator.shared
    @State private var full = false
    @State private var askGPS = false

    var body: some View {
        let hm = state.map.holes[hole.n], pin = state.pinsheet[hole.n]
        let o = hm.flatMap { Geo.middle($0) != nil ? Geo.origin($0, loc.fix?.at) : nil }
        let y = hm.flatMap { h in o.map { Geo.yardages(h, from: $0.at) } }
        let mapped = Geo.mapped(state)
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(colors: [Color(UIColor(hex: 0x2c5a3d)), Color(UIColor(hex: 0x123628))], startPoint: .topTrailing, endPoint: .bottomLeading)
                    .overlay { if let photo { Image(uiImage: photo).resizable().aspectRatio(contentMode: .fill).transition(.opacity) } }
                    .clipped()
                LinearGradient(colors: [Color.fcScrim.opacity(0.88), Color.fcScrim.opacity(0.4), Color.fcScrim.opacity(0.65)], startPoint: .leading, endPoint: .trailing)
                HStack(alignment: .center, spacing: 6) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hole \(hole.n)").font(FCType.display(46)).textCase(.uppercase).lineLimit(1).minimumScaleFactor(0.6)
                        Spacer(minLength: 0)
                        if let pin {
                            Label("Pin \(pin.label.lowercased())", systemImage: "flag.fill")
                                .font(.caption.weight(.bold)).foregroundStyle(Color(UIColor(hex: 0xf0cf55))).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        (stat("Par", "\(hole.par)") + (hole.yds > 0 ? Text("  ·  ") + Text("\(hole.yds)").font(FCType.display(19)).foregroundColor(.white) + Text(" Yds") : Text("")) + Text("  ·  ") + stat("Index", "\(hole.hcp)"))
                            .font(.caption.weight(.semibold)).tracking(0.6).textCase(.uppercase).foregroundStyle(Color(UIColor(hex: 0xd4e1d8)))
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .foregroundStyle(.white).shadow(color: .black.opacity(0.35), radius: 6, y: 1)
                    Spacer(minLength: 0)
                    if y != nil || pin != nil {
                        GreenYards(y: y, pin: pin, fromMe: o?.me == true).frame(width: 140, height: 132)
                    }
                }
                .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 10)
            }
            .frame(height: 150)
            .clipped()
            if mapped || camera != nil {
                HStack(spacing: 8) {
                    if hm.flatMap({ Geo.middle($0) }) != nil {
                        Button { full = true } label: { Label(camera == nil ? "Full screen GPS" : "Full screen", systemImage: "arrow.up.left.and.arrow.down.right").lineLimit(1).minimumScaleFactor(0.8) }
                            .buttonStyle(.fc(.dark, full: true)).layoutPriority(1)
                    }
                    if mapped { gpsButton }
                    if let camera {
                        Button(action: camera) { Image(systemName: "video.fill") }
                            .buttonStyle(.fc(.plain, full: false))
                            .accessibilityLabel("Watch the hole \(hole.n) camera")
                    }
                }
                .padding(8)
                if let e = loc.error, mapped {
                    Text(e).font(.caption).foregroundStyle(Color.fcMuted).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.bottom, 8)
                }
            }
        }
        .background(Color.fcCard)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.fcScrim.opacity(0.10), radius: 10, y: 4)
        .animation(.easeOut(duration: 0.35), value: photo != nil)
        // the club's own photo of the hole when it added one, else the satellite picture
        .task(id: "\(state.id)-\(hole.n)-\(state.photos.holes[String(hole.n)] ?? "")") {
            if let p = await ClubPhoto.load(state.photos.hole(hole.n)) { photo = p } else { photo = await CoursePhoto.hole(state, hole.n) }
        }
        .fullScreenCover(isPresented: $full) { CourseView(state: state, hole: hole.n, onHole: onHole, scorer: scorer) }
        // what turning GPS on means, once, when they tap it (it used to sit under the yards all the time)
        .alert("Yards from where you are", isPresented: $askGPS) {
            Button("Turn on GPS") { loc.start() }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("The yards count from your phone once you’re on the hole, and from the tee until then.\(Geo.trackingOn(state) ? " During the tournament the desk and the other groups can see where your group is, until the results are final." : "")")
        }
    }

    @ViewBuilder private var gpsButton: some View {
        if loc.on {
            Menu {
                if let f = loc.fix { Text("GPS to within \(f.acc) yds") }
                if Geo.trackingOn(state) { Text("The desk and the other groups can see where your group is.") }
                Button("Turn off GPS", role: .destructive) { loc.stop() }
            } label: {
                Label(loc.fix.map { "±\($0.acc) yds" } ?? "Finding you…", systemImage: "location.fill").lineLimit(1).minimumScaleFactor(0.8)
            }
            .buttonStyle(.fc(.plain, full: true))
        } else {
            Button { askGPS = true } label: { Label("Use my GPS", systemImage: "location.fill").lineLimit(1).minimumScaleFactor(0.8) }
                .buttonStyle(.fc(.plain, full: true))
        }
    }

    private func stat(_ label: String, _ v: String) -> Text {
        Text("\(label) ") + Text(v).font(FCType.display(19)).foregroundColor(.white)
    }
}

/// A putting green drawn in a 150 × 140 box, back at the top (public/golf/gps.js GREEN_PATH).
struct GreenShape: Shape {
    func path(in r: CGRect) -> Path {
        let sx = r.width / 150, sy = r.height / 140
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + x * sx, y: r.minY + y * sy) }
        var path = Path()
        path.move(to: p(40, 20))
        path.addCurve(to: p(114, 14), control1: p(58, 6), control2: p(92, 4))
        path.addCurve(to: p(140, 70), control1: p(136, 24), control2: p(146, 46))
        path.addCurve(to: p(104, 104), control1: p(134, 92), control2: p(118, 100))
        path.addCurve(to: p(74, 128), control1: p(92, 108), control2: p(86, 118))
        path.addCurve(to: p(18, 118), control1: p(58, 140), control2: p(30, 136))
        path.addCurve(to: p(20, 70), control1: p(6, 100), control2: p(10, 82))
        path.addCurve(to: p(40, 20), control1: p(28, 60), control2: p(24, 40))
        path.closeSubpath()
        return path
    }
}

/// The yards on a drawn green: back at the top, front at the bottom, the middle (or, with today's pin, the yards
/// to the pin) big in the middle, with a fringe, mowing stripes, two bunkers and the flag where the pin is.
struct GreenYards: View {
    var y: Geo.Yardages?
    var pin: PinSpot?
    var fromMe: Bool
    var body: some View {
        let toPin = pin.flatMap { p in y.flatMap { p.yards(f: $0.f, m: $0.m, b: $0.b) } }
        GeometryReader { g in
            // the green sits in 150 × 140 inside a frame with room for the fringe and the bunkers
            let box = CGRect(x: g.size.width * 0.06, y: g.size.height * 0.04, width: g.size.width * 0.84, height: g.size.height * 0.9)
            let sx = box.width / 150, sy = box.height / 140
            ZStack(alignment: .topLeading) {
                Ellipse().fill(Color(UIColor(hex: 0xe7d9b0))).overlay(Ellipse().stroke(Color(UIColor(hex: 0xf6efd9)), lineWidth: 1.5))
                    .frame(width: 22 * sx, height: 30 * sy).position(x: box.minX + 2 * sx, y: box.minY + 48 * sy)
                Ellipse().fill(Color(UIColor(hex: 0xe7d9b0))).overlay(Ellipse().stroke(Color(UIColor(hex: 0xf6efd9)), lineWidth: 1.5))
                    .frame(width: 36 * sx, height: 26 * sy).position(x: box.minX + 132 * sx, y: box.minY + 122 * sy)
                GreenShape().path(in: box).stroke(Color(UIColor(hex: 0x2a6e3e)), style: StrokeStyle(lineWidth: 12 * sx, lineJoin: .round))
                GreenShape().path(in: box).fill(RadialGradient(colors: [Color(UIColor(hex: 0x5fbf78)), Color(UIColor(hex: 0x2f8a4c))],
                                                               center: UnitPoint(x: 0.55, y: 0.35), startRadius: 4, endRadius: box.width * 0.75))
                HStack(spacing: 14 * sx) { ForEach(0..<8, id: \.self) { _ in Rectangle().fill(.black.opacity(0.07)).frame(width: 14 * sx) } }
                    .frame(width: box.width * 1.6, height: box.height * 1.6)
                    .rotationEffect(.degrees(-25))
                    .position(x: box.midX, y: box.midY)
                    .mask(GreenShape().path(in: box))
                if let pin {
                    let px = box.minX + pin.spot.x * sx
                    let py = box.minY + pin.spot.y * sy
                    Ellipse().fill(Color(UIColor(hex: 0x0d2a18))).frame(width: 6, height: 3).position(x: px, y: py)
                    Rectangle().fill(.white).frame(width: 1.6, height: 26).position(x: px, y: py - 13)
                    Path { p in p.move(to: CGPoint(x: px, y: py - 26)); p.addLine(to: CGPoint(x: px + 13, y: py - 22)); p.addLine(to: CGPoint(x: px, y: py - 18)); p.closeSubpath() }
                        .fill(Color(UIColor(hex: 0xe0453a)))
                }
                if let y {
                    VStack(spacing: 0) {
                        Text(y.b.map { "Back \($0)" } ?? " ").font(FCType.display(14)).textCase(.uppercase)
                        Spacer(minLength: 0)
                        if toPin != nil { Text(fromMe ? "To pin" : "Pin · tee").font(.system(size: 9, weight: .bold)).tracking(1.2).textCase(.uppercase).foregroundStyle(Color(UIColor(hex: 0xf0cf55))) }
                        else if !fromMe { Text("From tee").font(.system(size: 9, weight: .bold)).tracking(1.2).textCase(.uppercase).foregroundStyle(Color(UIColor(hex: 0xf0cf55))) }
                        Text((toPin ?? y.m).map(String.init) ?? "—").font(FCType.display(40)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                            .contentTransition(.numericText())
                        Spacer(minLength: 0)
                        Text(y.f.map { "Front \($0)" } ?? " ").font(FCType.display(14)).textCase(.uppercase)
                    }
                    .foregroundStyle(.white).shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                    .frame(width: box.width * 0.8, height: box.height * 0.84)
                    .position(x: box.minX + 74 * sx, y: box.minY + 70 * sy)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(axLabel)
    }
    private var axLabel: String {
        var parts: [String] = []
        if let pin { parts.append("Pin \(pin.label.lowercased())") }
        if let y {
            if let p = pin?.yards(f: y.f, m: y.m, b: y.b) { parts.append("\(p) yards to the pin") } else if let m = y.m { parts.append("\(m) yards to the middle") }
            if let f = y.f { parts.append("front \(f)") }
            if let b = y.b { parts.append("back \(b)") }
            if !fromMe { parts.append("from the tee") }
        }
        return parts.joined(separator: ", ")
    }
}

/// A sponsor in a small tile on the scorecard (its banner behind, when the club added one). Tap to visit.
struct SponsorTile: View {
    var sponsor: Sponsor
    var lead: String
    var banner: URL? = nil
    var onTap: () -> Void = {}
    @Environment(\.openURL) private var openURL
    @State private var bannerImage: UIImage?
    var body: some View {
        let link = URL(string: sponsor.url).flatMap { sponsor.url.isEmpty ? nil : $0 }
        Button { if let link { onTap(); openURL(link) } } label: {
            ZStack(alignment: .bottomLeading) {
                if let bannerImage {
                    Image(uiImage: bannerImage).resizable().aspectRatio(contentMode: .fill).frame(maxWidth: .infinity, minHeight: 64, maxHeight: 64).clipped()
                    LinearGradient(colors: [Color.fcScrim.opacity(0.75), .clear], startPoint: .bottom, endPoint: .top)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(lead).font(.caption).foregroundStyle(bannerImage == nil ? Color.fcMuted : .white.opacity(0.85))
                    if bannerImage == nil { SponsorBadge(sponsor: sponsor, height: 20) }
                    else { Text(sponsor.name).font(.footnote.weight(.bold)).foregroundStyle(.white).lineLimit(1) }
                    if !sponsor.offer.isEmpty, bannerImage == nil { Text(sponsor.offer).font(.caption.weight(.semibold)).foregroundStyle(Color.fcPrimary).lineLimit(1) }
                }
                .padding(10)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(Color.fcCard)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(link == nil)
        .accessibilityLabel("\(lead) \(sponsor.name)\(sponsor.offer.isEmpty ? "" : ", \(sponsor.offer)")")
        .task(id: banner) { bannerImage = await ClubPhoto.load(banner) }
    }
}


/// A golfer enters their own long drive or closest to the pin. Long drive: stand at the ball (the phone's GPS, from
/// the tee on the course map) or type the yards. Closest: feet and inches wheels. The server decides whether it waits
/// for the pro's OK (golf.js enter).
struct ContestEntrySheet: View {
    var model: ScorecardModel
    let contest: Contest
    @State private var player = ""
    @State private var useGPS = true
    @State private var yards = ""
    @State private var feet = 6
    @State private var inches = 0
    @State private var saving = false
    @State private var error: String?
    @State private var loc = Locator.shared
    @Environment(\.dismiss) private var dismiss

    private var tee: GeoPoint? { model.state?.map.holes[contest.hole]?.tee }
    private var gpsYards: Int? {
        guard let tee, let f = loc.fix, Date().timeIntervalSince(f.t) < 60 else { return nil }
        return Geo.yds(tee, f.at).map { Int(jsRound($0)) }
    }
    private var gpsMode: Bool { contest.isLongDrive && tee != nil && useGPS }

    var body: some View {
        let players = model.team?.players ?? []
        NavigationStack {
            Form {
                Section("Who hit it?") {
                    Picker("Player", selection: $player) { ForEach(players, id: \.id) { p in Text(p.name.split(separator: " ").first.map(String.init) ?? p.name).tag(p.id) } }
                        .pickerStyle(.segmented)
                }
                if contest.isLongDrive {
                    if tee != nil {
                        Section {
                            Picker("How", selection: $useGPS) { Text("Stand at my ball").tag(true); Text("Type it").tag(false) }.pickerStyle(.segmented)
                        }
                    }
                    Section {
                        if gpsMode {
                            VStack(spacing: 4) {
                                Text(gpsYards.map(String.init) ?? "–").font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit()
                                Text("yds from the tee").font(.footnote).foregroundStyle(Color.fcMuted)
                            }.frame(maxWidth: .infinity)
                            Text(loc.error ?? (loc.fix.map { "GPS good to about \($0.acc) yds. Walk to the ball, then Save." } ?? "Finding your spot…"))
                                .font(.footnote).foregroundStyle(Color.fcMuted)
                        } else {
                            HStack { TextField("Yards", text: $yards).keyboardType(.numberPad).font(.system(size: 34, weight: .bold, design: .rounded)); Text("yds").foregroundStyle(Color.fcMuted) }
                        }
                    } footer: { Text("Must be in the fairway.\(contest.check == "none" ? "" : " The pro can check it.")") }
                } else {
                    Section {
                        HStack(spacing: 0) {
                            Picker("Feet", selection: $feet) { ForEach(0..<100, id: \.self) { Text("\($0) ft").tag($0) } }.pickerStyle(.wheel)
                            Picker("Inches", selection: $inches) { ForEach(0..<12, id: \.self) { Text("\($0) in").tag($0) } }.pickerStyle(.wheel)
                        }
                        .frame(height: 130)
                    } footer: { Text("On the green only.\(contest.check == "none" ? "" : " The pro can check it.")") }
                }
                if let error { Section { Text(error).foregroundStyle(Color.fcRed) } }
            }
            .navigationTitle(contest.isLongDrive ? "Your drive on \(contest.hole)" : "Closest to the pin on \(contest.hole)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveLabel) { Task { await save() } }.disabled(saving || !ready).fontWeight(.bold)
                }
            }
        }
        .onAppear {
            player = players.first { $0.id == model.me }?.id ?? players.first?.id ?? ""
            useGPS = tee != nil
            if contest.isLongDrive && tee != nil { loc.start() } // a typed drive sends the GPS number too, for the pro
        }
    }

    private var ready: Bool {
        guard !player.isEmpty else { return false }
        if contest.isLongDrive { return gpsMode ? gpsYards != nil : (Int(yards).map { $0 >= 50 && $0 <= 450 } ?? false) }
        return feet > 0 || inches > 0
    }
    private var saveLabel: String { gpsMode ? (gpsYards.map { "Save \($0) yds" } ?? "Save") : "Save" }

    private func save() async {
        guard let t = model.teamId else { return }
        saving = true; error = nil
        var body: [String: Any?] = ["code": model.code, "team": t, "contest": contest.id, "player": player]
        if contest.isLongDrive {
            if let f = loc.fix, Date().timeIntervalSince(f.t) < 60 { body["at"] = [f.at.lat, f.at.lng] }
            if !gpsMode { body["dist"] = Double(yards) ?? 0 }
        } else { body["dist"] = Double(feet) + Double(inches) / 12 }
        do {
            let r = try await API.post(model.id, "enter", body)
            let ok = ((r["entry"] as? [String: Any])?["ok"] as? Bool) ?? false
            model.toast = ok ? "Saved. It’s on the board." : "Saved. It shows once the pro checks it."
            dismiss()
        } catch { self.error = error.localizedDescription }
        saving = false
    }
}
