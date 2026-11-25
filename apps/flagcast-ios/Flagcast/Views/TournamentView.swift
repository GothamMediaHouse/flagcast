import SwiftUI
import UIKit

/// Inside a tournament: one tab bar for everything a golfer needs (Score, Leaders, Cameras, Games, Course).
/// Opened from a cart card (with the cart's code: every tab) or as a spectator (no code: Leaders and Cameras).
enum TourTab: Hashable { case score, leaders, cameras, games, course }

/// Which tab is showing, so any tab can send you to another (the scorecard's Done, a phone banner, Course map).
@MainActor @Observable
final class TourNav {
    var tab: TourTab
    init(_ tab: TourTab) { self.tab = tab }
}

struct TournamentScreen: View {
    let id: String
    @State private var model: ScorecardModel?
    @State private var feed: EventFeed
    @State private var nav: TourNav

    init(id: String, code: String?, start: TourTab) {
        self.id = id
        _feed = State(initialValue: Feeds.feed(id))
        _model = State(initialValue: code.map { ScorecardModel(id: id, code: $0) })
        _nav = State(initialValue: TourNav(code == nil && start == .score ? .leaders : start))
    }

    var body: some View {
        @Bindable var nav = nav
        let s = feed.state
        TabView(selection: $nav.tab) {
            if let model {
                ScorecardScreen(model: model)
                    .tabItem { Label("Score", systemImage: "square.and.pencil") }.tag(TourTab.score)
            }
            LeaderboardScreen(id: id, mode: .leaders, mine: Set(model?.teams ?? []))
                .tabItem { Label("Leaders", systemImage: "chart.bar.fill") }.tag(TourTab.leaders)
            if let s, s.course.holes.contains(where: { $0.par == 3 }) || !s.cams.isEmpty {
                LeaderboardScreen(id: id, mode: .cameras, mine: [])
                    .tabItem { Label(s.cams.isEmpty ? "Par 3s" : "Cameras", systemImage: s.cams.isEmpty ? "flag.fill" : "video.fill") }
                    .tag(TourTab.cameras)
            }
            if let model, let s, s.sideGamesAllowed {
                SideGamesHub(model: model)
                    .tabItem { Label("Games", systemImage: "trophy.fill") }.tag(TourTab.games)
            }
            if let model, let s, Geo.mapped(s) || Geo.trackingOn(s) {
                CourseTab(model: model, state: s)
                    .tabItem { Label("Course", systemImage: "map.fill") }.tag(TourTab.course)
            }
        }
        .tint(Color.fcPrimary)
        .environment(nav)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard let model else { return }
            model.start()
            UIApplication.shared.isIdleTimerDisabled = true   // keep the screen on while scoring
            Locator.shared.resume()
        }
        .onDisappear {
            guard let model else { return }
            model.stop()
            UIApplication.shared.isIdleTimerDisabled = false
            Locator.shared.pause()
        }
    }
}

/// The dark green band at the top of each tab: a way home, the club's logo (or the tournament's name), a line
/// under it, and whatever the tab puts on the right.
struct TourHeader<Trailing: View, Below: View>: View {
    var state: EventState?
    var title: String
    var subtitle: String = ""
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var below: Below
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button { router.path = [] } label: {
                    Image(systemName: "chevron.left").font(.headline.weight(.bold))
                        .frame(width: 40, height: 40).background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Home")
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    if let u = state?.brand.logoURL {
                        ClubLogo(url: u).frame(width: 170, height: 30).accessibilityLabel(state?.title ?? title)
                    } else {
                        HStack(spacing: 6) {
                            // a Demo tournament (Admin marked it, "Try a demo" opens it): a small pill, so nobody takes it for a real round
                            if state?.brand.marked == true {
                                Text("DEMO").font(.system(size: 10, weight: .heavy)).tracking(0.8).foregroundStyle(Color.fcOnFlag)
                                    .padding(.horizontal, 6).padding(.vertical, 2).background(Color.fcFlag, in: RoundedRectangle(cornerRadius: 5))
                                    .accessibilityLabel("Demo tournament")
                            }
                            Text(state?.title ?? title).font(.headline).lineLimit(1)
                        }
                    }
                    if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(Color.fcOnGreenMuted).lineLimit(1).minimumScaleFactor(0.8) }
                }
                Spacer(minLength: 0)
                trailing.frame(minWidth: 40, alignment: .trailing)
            }
            below
        }
        .foregroundStyle(Color.fcOnGreen)
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 12)
        .background(Color.fcGreen.ignoresSafeArea(edges: .top))
    }
}

/// Two or three choices in the green header ("This hole / Your round", "Teams / Contests / Skins").
struct HeaderSwitch<T: Hashable>: View {
    var options: [(T, String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { o in
                let on = o.0 == selection
                Button { withAnimation(.snappy(duration: 0.2)) { selection = o.0 } } label: {
                    Text(o.1).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(on ? Color.fcOnGreen : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .foregroundStyle(on ? Color(UIColor(hex: 0x123628)) : Color.fcOnGreenMuted)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// A big page title in the green header (Side games, Par 3 cameras).
struct TourTitle: View {
    var title: String
    var sub: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(FCType.display(38)).textCase(.uppercase).lineLimit(1).minimumScaleFactor(0.6)
            if !sub.isEmpty { Text(sub).font(.footnote).foregroundStyle(Color.fcOnGreenMuted) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The Course tab: the hole you're on, following the scorecard, with the scores at the bottom; or Everyone, where
/// every group is on the course right now (GroupsMapView). Everyone only, when the course isn't mapped yet.
enum CourseMode: Hashable { case hole, everyone }

struct CourseTab: View {
    @Bindable var model: ScorecardModel
    let state: EventState
    @State private var mode: CourseMode = .hole

    var body: some View {
        let mapped = Geo.mapped(state)
        VStack(spacing: 0) {
            if mapped {
                HeaderSwitch(options: [(CourseMode.hole, "Your hole"), (.everyone, "Everyone")], selection: $mode)
                    .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 8)
                    .background(Color(UIColor(hex: 0x0b1a12)).ignoresSafeArea(edges: .top))
            }
            if mapped && mode == .hole {
                let h = model.currentHole()
                CourseView(state: state, hole: h, onHole: { d in
                    guard let t = model.team else { return }
                    let ord = model.order(t), i = ord.firstIndex(of: model.currentHole()) ?? 0
                    model.hole = ord[(i + d + ord.count) % ord.count]
                }, embedded: true, scorer: model)
            } else {
                GroupsMapView(model: model, state: state)
            }
        }
    }
}
