import SwiftUI
import UIKit

/// The cart scorecard: a hole strip in playing order, the hole's facts and sponsor, each player's score with
/// − / + buttons, the team's standing and full card. Works with no signal: scores wait on the phone and send
/// when the connection comes back.
struct ScorecardScreen: View {
    @State private var model: ScorecardModel
    @State private var sideGames = false
    @State private var camera: CameraLink?
    @State private var dismissed = 0.0
    @State private var replay: Replay?
    @State private var replaySeen = 0.0
    @Environment(Router.self) private var router
    @Environment(\.dynamicTypeSize) private var typeSize

    init(id: String, code: String) { _model = State(initialValue: ScorecardModel(id: id, code: code)) }

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
        .navigationTitle(model.state?.title ?? "Scorecard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.fcGreen, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { syncPill }
            // the club's logo in the bar when it has one; the tournament's name otherwise
            ToolbarItem(placement: .principal) {
                if let u = model.state?.brand.logoURL {
                    ClubLogo(url: u).frame(width: 180, height: 30).accessibilityLabel(model.state?.title ?? "Scorecard")
                } else {
                    Text(model.state?.title ?? "Scorecard").font(.headline).foregroundStyle(.white).lineLimit(1)
                }
            }
        }
        .onAppear {
            model.start()
            UIApplication.shared.isIdleTimerDisabled = true   // keep the screen on while scoring
            Locator.shared.resume()
        }
        .onDisappear {
            model.stop()
            UIApplication.shared.isIdleTimerDisabled = false
            Locator.shared.pause()
        }
        .toast($model.toast)
        .sensoryFeedback(.selection, trigger: model.changes)
        .sensoryFeedback(.success, trigger: model.aces)
        .sensoryFeedback(.warning, trigger: model.nudge)
        .overlay { if model.celebrating { AceCelebration { model.celebrating = false } } }
        .alert(model.nudge.map { _ in "A note for your cart" } ?? "", isPresented: Binding(get: { model.nudge != nil }, set: { if !$0 { model.nudge = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.nudge?.text ?? "") }
        .sheet(isPresented: $sideGames) { SideGamesSheet(model: model) }
        .fullScreenCover(item: $replay) { r in
            ReplayFullscreen(replay: r, camURL: model.state?.cams[r.hole].flatMap(URL.init(string:)).flatMap { CameraLink(hole: r.hole, url: $0).isHLS ? $0 : nil },
                             replays: model.state?.replays.filter { $0.hole == r.hole } ?? [])
        }
        .sheet(item: $camera) { l in CameraSheet(link: l, replays: model.state?.replays.filter { $0.hole == l.hole } ?? []) }
    }

    private var syncPill: some View {
        Text(model.syncText)
            .font(.caption2.monospaced().weight(.semibold)).textCase(.uppercase)
            .foregroundStyle(model.synced ? Color.fcOnGreenMuted : Color.fcFlag)
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
            if model.teams.count > 1 { teamTabs(s) }
            if s.locked {
                Text("Scoring is closed. The results are final.").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(8).background(Color.fcRed)
            }
            strip(s, t, h)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // the club's cover photo welcomes the cart until its first score
                        if s.photos.coverURL != nil, !s.scorers(t).contains(where: { p in (model.myScores()[t.id]?[p.id] ?? []).contains { $0 != nil } }) {
                            CoverCard(state: s)
                        }
                        holeHeader(s, H).id("top")
                        if Geo.mapped(s) {
                            GPSCard(state: s, hole: h) { d in
                                let ord = model.order(t), i = ord.firstIndex(of: model.currentHole()) ?? 0
                                model.hole = ord[max(0, min(ord.count - 1, i + d))]
                            }
                        }
                        // no course map: nothing here (golfers can't map it; the desk sees that in Setup)
                        sponsors(s, h)
                        ForEach(s.contests.filter { $0.hole == h }) { c in contestNote(c) }
                        if let cam = s.cams[h], let u = URL(string: cam) {
                            Button { camera = CameraLink(hole: h, url: u) } label: { Label("Watch the hole \(h) camera", systemImage: "video.fill") }
                                .buttonStyle(.fcPlain)
                        }
                        VStack(spacing: 10) { ForEach(s.scorers(t)) { p in playerRow(s, p, H) } }
                        standing(s)
                        Button { router.go(.live(id: model.id)) } label: { Label("Full leaderboard", systemImage: "list.number") }.buttonStyle(.fcPlain)
                        if s.sideGamesAllowed {
                            Button { sideGames = true } label: {
                                Label("Side games" + (model.side.anyOn ? " · playing" : ""), systemImage: "dollarsign.circle")
                            }.buttonStyle(.fcPlain)
                        }
                        CardGrid(holes: s.course.holes.filter { Core.playHoles(s).contains($0.n) },
                                 rows: s.scorers(t).map { p in (Fmt.firstName(p.name), (model.myScores()[t.id]?[p.id]) ?? []) },
                                 showTotal: true)
                            .padding(.top, 8)
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
                        router.go(.live(id: model.id))
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
            bottomBar(t, h)
        }
        .background(Color.fcPaper)
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
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .background(Color.fcGreen)
    }

    private func strip(_ s: EventState, _ t: Team, _ cur: Int) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.order(t), id: \.self) { n in
                        let par = s.course.holes[n - 1].par, on = n == cur, done = model.holeDone(n)
                        Button { model.hole = n } label: {
                            VStack(spacing: 0) {
                                Text("\(n)").font(FCType.display(24))
                                Text("P\(par)").font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(on ? Color.fcOnFlag : par == 3 ? Color.fcFlag : Color.fcOnGreenMuted)
                            }
                            .frame(width: 44, height: 48)
                            .foregroundStyle(on ? Color.fcOnFlag : Color.fcOnGreen)
                            .background(on ? Color.fcFlag : done ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Color.fcFlag : Color.white.opacity(0.25)))
                            .overlay(alignment: .topTrailing) {
                                if done && !on { Circle().fill(Color.fcFlag).frame(width: 6, height: 6).padding(4) }
                            }
                        }
                        .buttonStyle(.plain)
                        .id(n)
                        .accessibilityLabel("Hole \(n), par \(par)\(done ? ", done" : "")")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
            .background(Color.fcGreen2)
            .onAppear { proxy.scrollTo(cur, anchor: .center) }
            .onChange(of: cur) { _, n in withAnimation { proxy.scrollTo(n, anchor: .center) } }
        }
    }

    private func holeHeader(_ s: EventState, _ H: Hole) -> some View {
        HolePhotoHeader(state: s, hole: H)
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
            .padding(12).background(Color.fcPaper2, in: RoundedRectangle(cornerRadius: 10))
            .onAppear { model.hits.view(turn.id, once: "\(turn.id):turn") }
        }
    }

    private func contestNote(_ c: Contest) -> some View {
        let top = Core.contestLeader(c).first
        return VStack(alignment: .leading, spacing: 4) {
            Text((c.isLongDrive ? "Long drive" : "Closest to the pin") + (c.sponsor.isEmpty ? "" : " · \(c.sponsor)")).fcHeading(.subheadline)
            Text(top.map { "Leader: \($0.name), \(Core.fmtDist(c, $0.dist))." } ?? "No one on the board yet.")
                + Text(" A marshal measures at the green.").foregroundStyle(Color.fcMuted)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12).background(Color.fcPaper2, in: RoundedRectangle(cornerRadius: 10))
    }

    private func playerRow(_ s: EventState, _ p: Player, _ H: Hole) -> some View {
        let v = model.value(p.id, H.n)
        let st = Core.strokesOn(Core.playing(p.hcp, s.format.allowance), H.hcp)
        let set = v != nil
        let shown = !set ? "\(H.par)" : v == 0 ? "PU" : "\(v!)"
        let m = Core.mark(v, H.par)
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.body.weight(.semibold)).lineLimit(1)
                    Group {
                        if st > 0 { Text(String(repeating: "●", count: st)).foregroundStyle(Color.fcRed) + Text(" gets \(st) stroke\(st > 1 ? "s" : "")") }
                        else if st < 0 { Text("gives a stroke back") }
                        else { Text("no strokes here") }
                    }
                    .font(.caption).foregroundStyle(Color.fcMuted)
                    if let ix = p.index {
                        // GHIN: Handicap Index, tee and the course handicap the server worked out from them
                        let tee = s.course.tees.first { $0.id == p.tee }?.name ?? ""
                        Text("Index \(Core.fmtIndex(ix))\(tee.isEmpty ? "" : " · \(tee)") · CH \(Core.fmtIndex(p.hcp))")
                            .font(.caption2.monospaced()).foregroundStyle(Color.fcMuted).lineLimit(1).minimumScaleFactor(0.75)
                    }
                }
                Spacer(minLength: 4)
                stepButton("minus", "One fewer for \(p.name)") { model.step(p.id, -1) }
                Button { model.step(p.id, 0) } label: {
                    Text(shown)
                        .font(.system(size: 26, weight: .semibold, design: .monospaced))
                        .frame(width: 58, height: 58)
                        .foregroundStyle(!set ? Color.fcMuted : (m == .birdie || m == .eagle) ? Color.fcRed : Color.fcInk)
                        .background {
                            if m == .birdie || m == .eagle { Circle().stroke(Color.fcRed, lineWidth: 2) }
                            else if set { RoundedRectangle(cornerRadius: 10).stroke(m == .none ? Color.fcLine : Color.fcInk, lineWidth: m == .none ? 1.5 : 2) }
                            else { RoundedRectangle(cornerRadius: 10).stroke(Color.fcLine, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])) }
                        }
                        .contentTransition(.numericText())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(set ? "\(p.name) score \(shown)" : "Tap to enter par for \(p.name)")
                stepButton("plus", "One more for \(p.name)") { model.step(p.id, 1) }
            }
            HStack {
                Text(set ? "" : "Tap the number for par")
                Spacer()
                if set { Button("Clear") { withAnimation { model.clear(p.id) } } ; Text("·") }
                Button("Picked up") { withAnimation { model.pickedUp(p.id) } }
            }
            .font(.footnote).foregroundStyle(Color.fcMuted).tint(Color.fcMuted)
        }
        .padding(12)
        .background(Color.fcCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.fcLine))
        .animation(.snappy(duration: 0.2), value: v)
    }

    private func stepButton(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title2.weight(.semibold)).frame(width: 50, height: 50)
                .background(Color.fcPaper, in: Circle()).overlay(Circle().stroke(Color.fcLine, lineWidth: 1.5))
                .foregroundStyle(Color.fcInk)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func standing(_ s: EventState) -> some View {
        let l = model.line(), stab = s.format.isStableford
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stab ? "Points" : s.format.show == "gross" ? "Gross to par" : "Net to par").fcLabel()
                Text(l.map { $0.played > 0 ? Core.fmtPar($0.score, stab) : "—" } ?? "—")
                    .font(FCType.display(44))
                    .foregroundStyle((l?.score ?? 0) < 0 && !stab && (l?.played ?? 0) > 0 ? Color.fcRed : Color.fcInk)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Position").fcLabel()
                Text(l.map { $0.pos.isEmpty ? "—" : $0.pos } ?? "—").font(FCType.display(44))
            }
        }
        .accessibilityElement(children: .combine)
        .padding(.top, 4)
    }

    private func bottomBar(_ t: Team, _ h: Int) -> some View {
        let ord = model.order(t), i = ord.firstIndex(of: h) ?? 0, last = ord.count - 1
        return HStack(spacing: 10) {
            Button { model.hole = ord[max(0, i - 1)] } label: { Label("Back", systemImage: "chevron.left") }
                .buttonStyle(.fcPlain).disabled(i == 0)
            Button {
                if i == last { router.go(.live(id: model.id)); return }
                if let s = model.state {
                    let missing = s.scorers(t).filter { model.value($0.id, h) == nil }
                    if !missing.isEmpty { model.toast = "No score yet for \(missing.map { Fmt.firstName($0.name) }.joined(separator: " and ")) on hole \(h)." }
                }
                model.hole = ord[min(last, i + 1)]
            } label: {
                Label(i == last ? "Done" : "Hole \(ord[min(last, i + 1)])", systemImage: i == last ? "flag.checkered" : "chevron.right")
                    .labelStyle(TrailingIcon())
            }
            .buttonStyle(.fcPrimary)
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)
        .background(Rectangle().fill(Color.fcCard.shadow(.drop(color: .black.opacity(0.08), radius: 6, y: -2))).ignoresSafeArea(edges: .bottom))
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
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color.fcGreen2, Color.fcGreen], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay { if let photo { Image(uiImage: photo).resizable().aspectRatio(contentMode: .fill).transition(.opacity) } }
                .clipped()
            LinearGradient(colors: [Color.fcScrim.opacity(0.85), Color.fcScrim.opacity(0)], startPoint: .bottom, endPoint: .center)
            HStack(alignment: .lastTextBaseline) {
                Text("Hole \(hole.n)").font(FCType.display(48)).textCase(.uppercase)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Par \(hole.par)").font(FCType.display(26))
                    Text((hole.yds > 0 ? "\(hole.yds) yds · " : "") + "SI \(hole.hcp)").font(.footnote.weight(.semibold)).opacity(0.85)
                }
            }
            .foregroundStyle(.white).shadow(color: .black.opacity(0.4), radius: 6, y: 1)
            .padding(.horizontal, 16).padding(.bottom, 12)
        }
        .frame(height: photo == nil ? 96 : 170)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.easeOut(duration: 0.35), value: photo != nil)
        // the club's own photo of the hole when it added one, else the satellite picture
        .task(id: "\(state.id)-\(hole.n)-\(state.photos.holes[String(hole.n)] ?? "")") {
            if let p = await ClubPhoto.load(state.photos.hole(hole.n)) { photo = p } else { photo = await CoursePhoto.hole(state, hole.n) }
        }
        .accessibilityElement(children: .combine)
    }
}
