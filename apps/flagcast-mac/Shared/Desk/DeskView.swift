import SwiftUI

/// An open tournament: the section picked in the sidebar, with the toolbar (saved state, Lock, Save).
struct DeskView: View {
    @Environment(DeskNav.self) private var model
    @Bindable var doc: DeskDoc
    @State private var confirmLock = false

    var body: some View {
        Group {
            if !doc.loaded {
                if let e = doc.error {
                    ContentUnavailableView { Label("Can’t open this tournament", systemImage: "wifi.exclamationmark") } description: { Text(e) } actions: { Button("Try Again") { Task { await doc.load() } } }
                } else { ProgressView("Opening \(doc.ref.name)…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            } else {
                switch model.section {
                case .setup: SetupView(doc: doc)
                case .teams: TeamsView(doc: doc)
                case .scores: ScoresView(doc: doc)
                case .contests: ContestsView(doc: doc)
                case .screens: ScreensView(doc: doc)
                case .staff: StaffView(doc: doc)
                case .links: LinksView(doc: doc)
                case .report: ReportView(doc: doc)
                case .map: CourseMapView(doc: doc)
                case .groups: GroupsView(doc: doc)
                }
            }
        }
        .navigationTitle(doc.ev.name.isEmpty ? doc.ref.name : doc.ev.name)
        .navigationSubtitle(model.section.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if doc.loaded {
                    SaveState(doc: doc)
                    Button { if doc.ev.locked { Task { await doc.setLocked(false) } } else { confirmLock = true } } label: {
                        Label(doc.ev.locked ? "Unlock Results" : "Lock Results", systemImage: doc.ev.locked ? "lock.fill" : "lock.open")
                    }
                    .help(doc.ev.locked ? "Results are final. Unlock to let carts score again." : "Lock the results: scoring closes and the leaderboard is final (⇧⌘L)")
                    Button { Task { await doc.save() } } label: { Label("Save", systemImage: "square.and.arrow.down") }
                        .disabled(!doc.dirty || doc.saving).help("Save changes (⌘S)")
                }
            }
        }
        .confirmationDialog("Lock the results?", isPresented: $confirmLock) {
            Button("Lock Results") { Task { await doc.setLocked(true) } }
        } message: { Text("Scoring closes on every scorecard and the leaderboard becomes final. You can unlock again.") }
        .overlay(alignment: .bottom) {
            if let n = doc.notice {
                Text(n).font(.callout.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule()).shadow(radius: 4, y: 2).padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: doc.notice)
        .task { if !doc.loaded { await doc.load() } }
        .onChange(of: doc.ev.name) { _, n in if doc.loaded { model.onRename?(doc.id, n, doc.ev.date) } }
        .onChange(of: doc.ev.date) { _, d in if doc.loaded { model.onRename?(doc.id, doc.ev.name, d) } }
    }
}

struct SaveState: View {
    let doc: DeskDoc
    var body: some View {
        HStack(spacing: 5) {
            if doc.saving { ProgressView().controlSize(.small); Text("Saving…") }
            else if doc.dirty { Circle().fill(Color.orange).frame(width: 7, height: 7); Text("Unsaved changes") }
            else if doc.ev.locked { Image(systemName: "lock.fill").foregroundStyle(.red); Text("Results locked") }
            else { Image(systemName: "checkmark.circle").foregroundStyle(.secondary); Text("Saved") }
        }
        .font(.callout).foregroundStyle(.secondary).fixedSize()
    }
}

/// A help line under a form section.
struct Help: View {
    var text: String
    init(_ t: String) { text = t }
    var body: some View { Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}
