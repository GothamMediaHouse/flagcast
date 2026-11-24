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
        .alert(model.nudge.map { n in n.team == "*" ? "A note for everyone" : n.player != nil && n.player == model.me ? "A note for you" : "A note for your cart" } ?? "", isPresented: Binding(get: { model.nudge != nil }, set: { if !$0 { model.nudge = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.nudge?.text ?? "") }
        .fullScreenCover(item: $replay) { r in
            ReplayFullscreen(replay: r, camURL: model.state?.cams[r.hole].flatMap(URL.init(string:)).flatMap { CameraLink(hole: r.hole, url: $0).isHLS ? $0 : nil },
                             replays: model.state?.replays.filter { $0.hole == r.hole } ?? [])
        }
        .sheet(item: $camera) { l in CameraSheet(link: l, replays: model.state?.replays.filter { $0.hole == l.hole } ?? []) }
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
            TourHeader(state: s, title: s.title, subtitle: s.scorers(t).map { Fmt.firstName($0.name) }.joined(separator: " & ")) {
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
                playerRow(s, p, H, tight: tight)
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
        let cs = s.contests.filter { $0.hole == h }
        if sp != nil || turn != nil || !cs.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
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

    // ---- your round ----
    @ViewBuilder private func roundPage(_ s: EventState, _ t: Team) -> some View {
        let l = model.line(), stab = s.format.isStableford
        let lb = Core.leaderboard(s, model.myScores())
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

    private func playerRow(_ s: EventState, _ p: Player, _ H: Hole, tight: Bool = false) -> some View {
        let v = model.value(p.id, H.n)
        let st = Core.strokesOn(Core.playing(p.hcp, s.format.allowance), H.hcp)
        let set = v != nil
        let shown = !set ? "\(H.par)" : v == 0 ? "PU" : "\(v!)"
        let m = Core.mark(v, H.par)
        let under = m == .birdie || m == .eagle
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(p.name).font(.title3.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: 12) {
                    if st > 0 { Text(String(repeating: "●", count: st)).foregroundStyle(Color.fcRed) + Text(" \(st) stroke\(st > 1 ? "s" : "")") }
                    else if st < 0 { Text("gives a stroke back") }
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
            Button { model.hole = ord[max(0, i - 1)] } label: { Label(i == 0 ? "Back" : "\(ord[max(0, i - 1)])", systemImage: "chevron.left").labelStyle(LeadingIcon()) }
                .buttonStyle(.fcPlain).disabled(i == 0)
                .frame(width: 76)
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
                        Button { full = true } label: { Label("Full screen GPS", systemImage: "arrow.up.left.and.arrow.down.right").lineLimit(1).minimumScaleFactor(0.8) }
                            .buttonStyle(.fc(.dark, full: true))
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
