import SwiftUI

/// Flagcast Manager for iPhone and iPad: a club runs its tournament day from here (Today, Teams, Scores, Screens,
/// More). Signing in with a Flagcast admin email, or the admin passcode, adds the Admin tab (every club, tournament
/// and TV). Same account and tournaments as the Mac app.
@main
struct ManagerApp: App {
    @State private var model = AppModel()
    init() { FC.registerFonts() }
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
enum Tab: String, Hashable { case today, teams, scores, screens, more, admin }

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .today

    var body: some View {
        Group {
            if !model.signedIn && model.events.isEmpty && !model.isAdmin {
                NavigationStack { SignInView() }
            } else {
                tabs
            }
        }
        .alert("Flagcast", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .onAppear { if model.selection == nil { model.selection = model.shownEvents.first?.id } }
        .onChange(of: model.selection) { _, _ in if tab == .admin || tab == .more { tab = .today } }
        .onChange(of: model.events.count) { _, _ in if model.selection == nil { model.selection = model.shownEvents.first?.id } }
    }

    @ViewBuilder private var tabs: some View {
        let tv = TabView(selection: $tab) {
            NavigationStack { TodayView() }.tabItem { Label("Today", systemImage: "flag.fill") }.tag(Tab.today)
            NavigationStack { TeamsView() }.tabItem { Label("Teams", systemImage: "person.3.fill") }.tag(Tab.teams)
            NavigationStack { ScoresView() }.tabItem { Label("Scores", systemImage: "list.number") }.tag(Tab.scores)
            NavigationStack { ScreensView() }.tabItem { Label("Screens", systemImage: "tv.fill") }.tag(Tab.screens)
            if model.isAdmin {
                NavigationStack { AdminHome() }.tabItem { Label("Admin", systemImage: "building.columns.fill") }.tag(Tab.admin)
            } else {
                NavigationStack { MoreView() }.tabItem { Label("More", systemImage: "ellipsis.circle.fill") }.tag(Tab.more)
            }
        }
        if #available(iOS 18.0, *) { tv.tabViewStyle(.sidebarAdaptable) } else { tv }
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
