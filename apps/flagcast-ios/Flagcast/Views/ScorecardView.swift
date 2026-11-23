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
        .alert(model.nudge.map { _ in "A note for your cart" } ?? "", isPresented: Binding(get: { model.nudge != nil }, set: { if !$0 { model.nudge = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.nudge?.text ?? "") }
        .fullScreenCover(item: $replay) { r in
            ReplayFullscreen(replay: r, camURL: model.state?.cams[r.hole].flatMap(URL.init(string:)).flatMap { CameraLink(hole: r.hole, url: $0).isHLS ? $0 : nil },
                             replays: model.state?.replays.filter { $0.hole == r.hole } ?? [])
        }
        .sheet(item: $camera) { l in CameraSheet(link: l, replays: model.state?.replays.filter { $0.hole == l.hole } ?? []) }
    }

    private var syncPill: some View {
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
            TourHeader(state: s, title: s.title, subtitle: "Cart \(model.code) · " + s.scorers(t).map { Fmt.firstName($0.name) }.joined(separator: " & ")) {
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
                    VStack(alignment: .leading, spacing: 12) {
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
    }

    // ---- this hole ----
    @ViewBuilder private func holePage(_ s: EventState, _ t: Team, _ h: Int, _ H: Hole) -> some View {
        // the club's cover photo welcomes the cart until its first score
        if s.photos.coverURL != nil, !s.scorers(t).contains(where: { p in (model.myScores()[t.id]?[p.id] ?? []).contains { $0 != nil } }) {
            CoverCard(state: s)
        }
        HolePhotoHeader(state: s, hole: H)
        VStack(spacing: 0) {
            let ps = s.scorers(t)
            ForEach(Array(ps.enumerated()), id: \.element.id) { i, p in
                playerRow(s, p, H)
                if i < ps.count - 1 { Divider().overlay(Color.fcLine) }
            }
        }
        .padding(.horizontal, 14)
        .fcCard(padding: 0)
        if Geo.mapped(s) {
            GPSCard(state: s, hole: h, onHole: { d in
                let ord = model.order(t), i = ord.firstIndex(of: model.currentHole()) ?? 0
                model.hole = ord[max(0, min(ord.count - 1, i + d))]
            }, openMap: { nav.tab = .course })
        }
        // no course map: nothing here (golfers can't map it; the desk sees that in Setup)
        sponsors(s, h)
        ForEach(s.contests.filter { $0.hole == h }) { c in contestNote(c) }
        if let cam = s.cams[h], let u = URL(string: cam) {
            Button { camera = CameraLink(hole: h, url: u) } label: { Label("Watch the hole \(h) camera", systemImage: "video.fill") }
                .buttonStyle(.fcPlain)
        }
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
            Text("Your card").fcLabel()
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

    @ViewBuilder private func sponsors(_ s: EventState, _ h: Int) -> some View {
        let sp = s.sponsors.first { $0.spot == "hole" && $0.holes.contains(h) } ?? s.sponsors.first { $0.holes.contains(h) }
        let turn = h == 10 ? s.sponsors.first { $0.spot == "turn" } : nil
        if let sp {
            SponsorLine(sponsor: sp, lead: "Presented by", banner: s.photos.sponsor(sp.id)) { model.hits.tap(sp.id) }
                .onAppear { model.hits.view(sp.id, once: "\(sp.id):\(h)") }
        }
        if let turn {
            VStack(alignment: .leading, spacing: 6) {
                Text("At the turn").fcHeading(.subheadline)
                SponsorLine(sponsor: turn, banner: s.photos.sponsor(turn.id)) { model.hits.tap(turn.id) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fcCard(padding: 12)
            .onAppear { model.hits.view(turn.id, once: "\(turn.id):turn") }
        }
    }

    private func contestNote(_ c: Contest) -> some View {
        let top = Core.contestLeader(c).first
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: c.isLongDrive ? "arrow.up.right" : "scope").font(.headline)
                .frame(width: 40, height: 40).background(Color.fcFlag.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text((c.isLongDrive ? "Long drive" : "Closest to the pin") + (c.sponsor.isEmpty ? "" : " · \(c.sponsor)")).fcLabel()
                Text(top.map { "\($0.name), \(Core.fmtDist(c, $0.dist))" } ?? "No one on the board yet").font(.body.weight(.semibold))
                Text("A marshal measures at the green.").font(.footnote).foregroundStyle(Color.fcMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fcCard(padding: 12)
    }

    private func playerRow(_ s: EventState, _ p: Player, _ H: Hole) -> some View {
        let v = model.value(p.id, H.n)
        let st = Core.strokesOn(Core.playing(p.hcp, s.format.allowance), H.hcp)
        let set = v != nil
        let shown = !set ? "\(H.par)" : v == 0 ? "PU" : "\(v!)"
        let m = Core.mark(v, H.par)
        let under = m == .birdie || m == .eagle
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.name).font(.title3.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
                    Group {
                        if st > 0 { Text(String(repeating: "●", count: st)).foregroundStyle(Color.fcRed) + Text(" gets \(st) stroke\(st > 1 ? "s" : "") here") }
                        else if st < 0 { Text("gives a stroke back") }
                        else if !set { Text("Tap the number for par") }
                        else { Text("no strokes here") }
                    }
                    .font(.footnote).foregroundStyle(Color.fcMuted)
                    if let ix = p.index {
                        // GHIN: Handicap Index, tee and the course handicap the server worked out from them
                        let tee = s.course.tees.first { $0.id == p.tee }?.name ?? ""
                        Text("Index \(Core.fmtIndex(ix))\(tee.isEmpty ? "" : " · \(tee)") · CH \(Core.fmtIndex(p.hcp))")
                            .font(.caption2.monospaced()).foregroundStyle(Color.fcMuted).lineLimit(1).minimumScaleFactor(0.75)
                    }
                }
                Spacer(minLength: 2)
                stepButton("minus", "One fewer for \(p.name)") { model.step(p.id, -1) }
                Button { model.step(p.id, 0) } label: {
                    Text(shown)
                        .font(FCType.display(v == 0 ? 30 : 42))
                        .frame(width: 62, height: 62)
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
                stepButton("plus", "One more for \(p.name)") { model.step(p.id, 1) }
            }
            HStack(spacing: 14) {
                Spacer()
                if set { Button("Clear") { withAnimation { model.clear(p.id) } } }
                Button("Picked up") { withAnimation { model.pickedUp(p.id) } }
            }
            .font(.footnote.weight(.semibold)).tint(Color.fcPrimary)
        }
        .padding(.vertical, 14)
        .animation(.snappy(duration: 0.2), value: v)
    }

    private func stepButton(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title2.weight(.semibold)).frame(width: 52, height: 52)
                .background(Color.fcPaper2, in: Circle())
                .foregroundStyle(Color.fcInk)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func bottomBar(_ t: Team, _ h: Int) -> some View {
        let ord = model.order(t), i = ord.firstIndex(of: h) ?? 0, last = ord.count - 1
        return HStack(spacing: 10) {
            Button { model.hole = ord[max(0, i - 1)] } label: { Text(i == 0 ? "Back" : "Hole \(ord[max(0, i - 1)])") }
                .buttonStyle(.fcPlain).disabled(i == 0)
                .frame(maxWidth: 130)
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
        .padding(.horizontal, 16).padding(.vertical, 10)
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

struct HolePhotoHeader: View {
    let state: EventState
    let hole: Hole
    @State private var photo: UIImage?
    var body: some View {
        ZStack(alignment: .leading) {
            LinearGradient(colors: [Color(UIColor(hex: 0x2c5a3d)), Color(UIColor(hex: 0x123628))], startPoint: .topTrailing, endPoint: .bottomLeading)
                .overlay { if let photo { Image(uiImage: photo).resizable().aspectRatio(contentMode: .fill).transition(.opacity) } }
                .clipped()
            LinearGradient(colors: [Color.fcScrim.opacity(0.85), Color.fcScrim.opacity(0.25), Color.fcScrim.opacity(0)], startPoint: .leading, endPoint: .trailing)
            VStack(alignment: .leading, spacing: 0) {
                Text("Hole \(hole.n)").font(FCType.display(56)).textCase(.uppercase).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 8)
                HStack(spacing: 18) {
                    stat("Par", "\(hole.par)")
                    if hole.yds > 0 { stat("Yards", "\(hole.yds)") }
                    stat("Index", "\(hole.hcp)")
                }
            }
            .foregroundStyle(.white).shadow(color: .black.opacity(0.35), radius: 6, y: 1)
            .padding(16)
        }
        .frame(height: 178)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.fcScrim.opacity(0.10), radius: 10, y: 4)
        .animation(.easeOut(duration: 0.35), value: photo != nil)
        // the club's own photo of the hole when it added one, else the satellite picture
        .task(id: "\(state.id)-\(hole.n)-\(state.photos.holes[String(hole.n)] ?? "")") {
            if let p = await ClubPhoto.load(state.photos.hole(hole.n)) { photo = p } else { photo = await CoursePhoto.hole(state, hole.n) }
        }
        .accessibilityElement(children: .combine)
    }
    private func stat(_ label: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2.weight(.semibold)).tracking(1).textCase(.uppercase).foregroundStyle(Color(UIColor(hex: 0xa9bdb0)))
            Text(v).font(FCType.display(30))
        }
    }
}
