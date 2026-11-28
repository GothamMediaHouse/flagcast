import SwiftUI

/// Flagcast Manager for iPhone and iPad: a club runs its tournament day from here (Today, Teams, Scores, Screens,
/// More). Signing in with a Flagcast admin email, or the admin passcode, adds the Admin tab (every club, tournament
/// and TV). Same account and tournaments as the Mac app.
@main
struct ManagerApp: App {
    @State private var model = AppModel()
    init() { FC.registerFonts(); GreenBars.apply() }
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.nav)
                .environment(model.admin)
                .tint(FC.primary)
                .task { await model.refresh() }
        }
    }
}

/// Which tab shows.
enum Tab: String, Hashable {
    case today, teams, scores, screens, more, admin
    /// the iPad sidebar's other sections (the Mac's): on iPhone they live under More
    case setup, pace, contests, pins, staff, links, report, map, groups
    /// the tabs the iPhone's tab bar has
    var onTabBar: Bool { [.today, .teams, .scores, .screens, .more, .admin].contains(self) }
}

/// The tab bar's selection, so Home's buttons can jump to Scores, Screens or Teams.
@MainActor @Observable final class Tabs { var tab: Tab = .today }

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var size
    @State private var tabs = Tabs()
    private var tab: Tab { tabs.tab }

    var body: some View {
        Group {
            if !model.signedIn && model.events.isEmpty && !model.isAdmin {
                NavigationStack { SignInView() }
            } else if model.signedIn, model.me?.camera == true, model.me?.club == nil, !model.isAdmin, model.events.isEmpty {
                NavigationStack { CameraHomeView() }   // Can go live only: their tournaments and Go live, nothing else
            } else if model.signedIn, model.me != nil, model.me?.club == nil, !model.isAdmin, model.events.isEmpty {
                NavigationStack { WelcomeView() }
            } else if size == .regular {
                SidebarRoot()   // iPad: the Mac's green sidebar
            } else {
                tabView
            }
        }
        .environment(tabs)
        .alert("Flagcast", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .onAppear { if model.selection == nil { model.selection = model.shownEvents.first?.id } }
        .onChange(of: model.selection) { _, _ in if tab == .admin || tab == .more { tabs.tab = .today } }
        // iPad going narrow (Split View): a sidebar-only section isn't on the tab bar, so show More
        .onChange(of: size) { _, s in if s != .regular && !tab.onTabBar { tabs.tab = model.isAdmin ? .admin : .more } }
        .onChange(of: model.events.count) { _, _ in if model.selection == nil { model.selection = model.shownEvents.first?.id } }
    }

    @ViewBuilder private var tabView: some View {
        @Bindable var tabs = tabs
        let tv = TabView(selection: $tabs.tab) {
            NavigationStack { TodayView() }.tabItem { Label("Overview", systemImage: "square.grid.2x2.fill") }.tag(Tab.today)
            NavigationStack { TeamsView() }.tabItem { Label("Teams", systemImage: "person.3.fill") }.tag(Tab.teams)
            NavigationStack { ScoresView() }.tabItem { Label("Scores", systemImage: "list.number") }.tag(Tab.scores)
            NavigationStack { ScreensView() }.tabItem { Label("Screens", systemImage: "tv.fill") }.tag(Tab.screens)
            if model.isAdmin {
                NavigationStack { AdminHome() }.tabItem { Label("Admin", systemImage: "building.columns.fill") }.tag(Tab.admin)
            } else {
                NavigationStack { MoreView() }.tabItem { Label("More", systemImage: "ellipsis.circle.fill") }.tag(Tab.more)
            }
        }
        tv
    }
}

// MARK: - iPad

/// The iPad's layout (design/Sidebar.dc.html): the Mac's green sidebar (mark, FLAGCAST / MANAGER, the tournaments with
/// the open one's sections, the club and tournaments left at the bottom), the page beside it.
struct SidebarRoot: View {
    @Environment(AppModel.self) private var model
    @Environment(Tabs.self) private var tabs
    @State private var adding = false
    @State private var making = false
    @State private var signingOut = false

    /// the Mac's sections, in the Mac's order
    private static let sections: [(Tab, String, String)] = [(.today, "Overview", "square.grid.2x2"), (.setup, "Setup", "gearshape"), (.teams, "Teams", "person.2"),
        (.scores, "Scores", "list.number"), (.pace, "Pace of play", "stopwatch"), (.contests, "Contests", "trophy"), (.pins, "Pin sheet", "flag"), (.screens, "Screens & sponsors", "tv"), (.staff, "Staff", "person.crop.circle"),
        (.links, "Links & cart cards", "link"), (.report, "Report", "chart.bar"), (.map, "Course map", "map"), (.groups, "Where the groups are", "mappin.and.ellipse")]

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 260)
            NavigationStack { page }
                .id(tabs.tab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(FC.paper)
        .sheet(isPresented: $adding) { NavigationStack { AddByLinkView() } }
        .sheet(isPresented: $making) { NavigationStack { TournamentPicker(asSheet: true) } }
    }

    @ViewBuilder private var page: some View {
        switch tabs.tab {
        case .today: TodayView()
        case .teams: TeamsView()
        case .scores: ScoresView()
        case .screens: ScreensView()
        case .admin: AdminHome()
        case .more: MoreView()
        case .setup: WithTournament { DetailsView(doc: $0) }
        case .contests: ContestsView()
        case .pins: PinsScreen()
        case .pace: PaceScreen()
        case .staff: WithTournament { StaffView(doc: $0) }
        case .links: WithTournament { LinksView(doc: $0) }
        case .report: ReportView()
        case .map: CourseMapScreen()
        case .groups: GroupsScreen()
        }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    FlagcastMark(size: 32)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("FLAGCAST").font(FC.display(21)).tracking(1)
                        Text("MANAGER").font(.system(size: 10, weight: .bold)).tracking(1.6).opacity(0.7)
                    }
                }
                .padding(.horizontal, 6).padding(.top, 6)
                Text("TOURNAMENTS").font(.system(size: 11, weight: .bold)).tracking(1.3).opacity(0.6).padding(.horizontal, 8).padding(.top, 6)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.shownEvents) { e in
                        let open = model.selection == e.id
                        Button { model.selection = e.id; if tabs.tab == .admin || tabs.tab == .more { tabs.tab = .today } } label: {
                            HStack(spacing: 8) {
                                Text(e.name.isEmpty ? "Tournament" : e.name).font(.system(size: 14, weight: open ? .bold : .semibold)).lineLimit(1)
                                Spacer(minLength: 4)
                                if open && e.date == ISO8601DateFormatter.day.string(from: Date()) { LiveChip().scaleEffect(0.85) }
                            }
                            .padding(.horizontal, 10).frame(minHeight: 36).contentShape(Rectangle())
                            .opacity(open ? 1 : 0.8)
                        }
                        .buttonStyle(.plain)
                        if open {
                            ForEach(Self.sections, id: \.0) { t, title, icon in row(t, title, icon).padding(.leading, 8) }
                        }
                    }
                    if model.shownEvents.isEmpty { Text("No tournaments yet").font(.subheadline).opacity(0.7).padding(.horizontal, 10) }
                }
                Divider().overlay(Color.white.opacity(0.14)).padding(.vertical, 4)
                if model.isAdmin { row(.admin, "Admin", "building.columns") }
                row(.more, "More", "ellipsis.circle")
            }
            .padding(.horizontal, 12).padding(.vertical, 18)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Divider().overlay(Color.white.opacity(0.14))
                HStack(spacing: 14) {
                    if model.me?.club?.canMake == true { Button { making = true } label: { Label("New tournament", systemImage: "plus") } }
                    Button { adding = true } label: { Label("Add by link", systemImage: "link") }
                }
                .font(.system(size: 14, weight: .semibold)).buttonStyle(.plain)
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        if let c = model.me?.club { Text("\(c.name) · \(c.credits < 0 ? "Unlimited" : "\(c.credits) tournaments left")").font(.system(size: 12)).opacity(0.7).lineLimit(1) }
                        if let e = model.me?.email { Text(e).font(.system(size: 11)).opacity(0.6).lineLimit(1) }
                    }
                    Spacer(minLength: 4)
                    if model.canSignOut {
                        Button { signingOut = true } label: { Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right").font(.system(size: 13, weight: .semibold)) }
                            .buttonStyle(.plain).signOutDialog($signingOut)
                    }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 14)
            .background(FC.green)
        }
        .foregroundStyle(.white)
        .background(FC.green.ignoresSafeArea())
    }

    private func row(_ t: Tab, _ title: String, _ icon: String) -> some View {
        let on = tabs.tab == t
        return Button { tabs.tab = t } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).frame(width: 20)
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 10).frame(minHeight: 36)
            .foregroundStyle(on ? FC.green : .white.opacity(0.88))
            .background(on ? Color(uiColor: GreenBars.cream) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The open tournament's page, or a prompt to pick or make one.
struct WithTournament<Content: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder var content: (DeskDoc) -> Content
    var body: some View {
        if let d = model.current {
            DocHost(doc: d) { content(d) }
        } else {
            TournamentPicker()
        }
    }
}

/// Loads the tournament, its course picture, and shows Save and notices over any tournament page.
struct DocHost<Content: View>: View {
    @Environment(AppModel.self) private var model
    @Bindable var doc: DeskDoc
    @ViewBuilder var content: Content
    var body: some View {
        Group {
            if doc.loaded { content }
            else if let e = doc.error {
                ContentUnavailableView {
                    Label("Can’t open \(doc.ref.name)", systemImage: "wifi.exclamationmark")
                } description: { Text(e) } actions: { Button("Try Again") { Task { await doc.load() } }.buttonStyle(GreenButton()) }
                .background(FC.paper)
            } else {
                ZStack { CourseHeroImage(image: doc.picture.image).ignoresSafeArea(); ProgressView("Opening \(doc.ref.name)…").tint(.white).foregroundStyle(.white) }
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                NoticeBar(text: doc.notice)
                if doc.dirty { SaveBar(doc: doc) }
            }
            .padding(.bottom, 10)
            .animation(.snappy, value: doc.notice)
            .animation(.snappy, value: doc.dirty)
        }
        .task(id: doc.id) { if !doc.loaded { await doc.load() }; doc.picture.load(doc.ev, id: doc.id) }
        .onChange(of: doc.ev.course.at) { _, _ in doc.picture.load(doc.ev, id: doc.id) }
        .onChange(of: doc.ev.name) { _, n in if doc.loaded { model.noteName(doc.id, name: n, date: doc.ev.date) } }
    }
}

/// Unsaved changes: Save (or put them back).
struct SaveBar: View {
    let doc: DeskDoc
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(FC.flag).frame(width: 8, height: 8)
            Text("Unsaved changes").font(.subheadline.weight(.semibold)).foregroundStyle(FC.onGreen)
            Spacer()
            Button("Undo") { doc.revert() }.foregroundStyle(FC.onGreenMuted)
            Button { Task { await doc.save() } } label: { if doc.saving { ProgressView().tint(FC.green) } else { Text("Save") } }
                .buttonStyle(WhiteButton()).disabled(doc.saving)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(FC.green, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        .padding(.horizontal, 12).frame(maxWidth: 560)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// The tournament switcher for the navigation bar.
struct TournamentMenu: View {
    @Environment(AppModel.self) private var model
    @State private var picking = false
    var body: some View {
        Button { picking = true } label: { Label("Tournaments", systemImage: "rectangle.stack") }
            .sheet(isPresented: $picking) { NavigationStack { TournamentPicker(asSheet: true) } }
    }
}
