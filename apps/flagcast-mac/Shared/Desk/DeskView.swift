import SwiftUI

/// An open tournament: the section picked in the sidebar. Every section opens on the course photo
/// (design/Main.dc.html and friends).
struct DeskView: View {
    @Environment(DeskNav.self) private var nav
    @Bindable var doc: DeskDoc

    var body: some View {
        Group {
            if !doc.loaded {
                ZStack {
                    CourseHeroImage(image: doc.picture.image).overlay(FC.scrim.opacity(0.45))
                    if let e = doc.error {
                        VStack(spacing: 10) {
                            Image(systemName: "wifi.exclamationmark").font(.system(size: 34))
                            Text("Can’t open \(doc.ref.name)").font(FC.display(34))
                            Text(e).opacity(0.85)
                            Button("Try Again") { Task { await doc.load() } }.buttonStyle(WhiteButton())
                        }
                        .foregroundStyle(.white)
                    } else {
                        VStack(spacing: 12) { ProgressView().controlSize(.large).tint(.white); Text("Opening \(doc.ref.name)…").font(FC.display(30)).foregroundStyle(.white) }
                    }
                }
                .ignoresSafeArea()
            } else {
                switch nav.section {
                case .overview: OverviewView(doc: doc)
                case .setup: SetupView(doc: doc)
                case .teams: TeamsView(doc: doc)
                case .scores: ScoresView(doc: doc)
                case .contests: ContestsView(doc: doc)
                case .pins: PinsView(doc: doc)
                case .screens: ScreensView(doc: doc)
                case .staff: StaffView(doc: doc)
                case .links: LinksView(doc: doc)
                case .report: ReportView(doc: doc)
                case .map: CourseMapView(doc: doc)
                case .groups: GroupsView(doc: doc)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let n = doc.notice {
                Text(n).font(.callout.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule()).shadow(radius: 4, y: 2).padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: doc.notice)
        .task { if !doc.loaded { await doc.load() }; doc.picture.load(doc.ev, id: doc.id) }
        .onChange(of: doc.ev.name) { _, n in if doc.loaded { nav.onRename?(doc.id, n, doc.ev.date) } }
        .onChange(of: doc.ev.date) { _, d in if doc.loaded { nav.onRename?(doc.id, doc.ev.name, d) } }
        .onChange(of: doc.ev.course.at) { _, _ in doc.picture.load(doc.ev, id: doc.id) }
        .onChange(of: doc.ev.map.holes.count) { _, _ in doc.picture.load(doc.ev, id: doc.id) }
        .onChange(of: doc.loaded) { _, _ in doc.picture.load(doc.ev, id: doc.id) }
    }
}

/// A section page: the course photo, the header (saved state, the section's own buttons, Save), the big title and the content.
struct DeskPage<Extra: View, Title: View, Content: View>: View {
    let doc: DeskDoc
    var section: Section
    var height: CGFloat = 230
    var titleHeight: CGFloat = 128
    var save = true
    @ViewBuilder var extra: Extra
    @ViewBuilder var title: Title
    @ViewBuilder var content: Content
    var body: some View {
        PhotoPage(image: doc.picture.image, height: height, section: section.title, titleHeight: titleHeight) {
            SaveState(doc: doc)
            extra
            if save { Button("Save") { Task { await doc.save() } }.buttonStyle(WhiteButton()).disabled(!doc.dirty || doc.saving).help("Save changes (⌘S)") }
        } title: { title } content: { content }
    }
}

/// Saved / Unsaved changes, in white over the photo.
struct SaveState: View {
    let doc: DeskDoc
    var body: some View {
        HStack(spacing: 6) {
            if doc.saving { ProgressView().controlSize(.mini).tint(.white); Text("Saving…") }
            else if doc.dirty { Circle().fill(FC.flag).frame(width: 7, height: 7); Text("Unsaved changes") }
            else if doc.ev.locked { Image(systemName: "lock.fill").font(.system(size: 10)); Text("Results locked") }
            else { Circle().fill(Color(hex: 0x7be0a4)).frame(width: 7, height: 7); Text("Saved") }
        }
        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).fixedSize()
    }
}

/// Lock or unlock the results (asks first).
struct LockButton: View {
    let doc: DeskDoc
    var white = false
    @State private var confirm = false
    var body: some View {
        Group {
            if white { Button(doc.ev.locked ? "Unlock scores" : "Lock scores") { tap() }.buttonStyle(WhiteButton()) }
            else { Button(doc.ev.locked ? "Unlock scores" : "Lock scores") { tap() }.buttonStyle(GlassButton()) }
        }
        .help(doc.ev.locked ? "Results are final. Unlock to let carts score again." : "Lock the results: scoring closes and the leaderboard is final (⇧⌘L)")
        .confirmationDialog("Lock the results?", isPresented: $confirm) { Button("Lock Results") { Task { await doc.setLocked(true) } } } message: { Text("Scoring closes on every scorecard and the leaderboard becomes final. You can unlock again.") }
    }
    private func tap() { if doc.ev.locked { Task { await doc.setLocked(false) } } else { confirm = true } }
}

/// A Form (grouped) laid out as raised cards on the page, under the photo's edge.
struct CardForm<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(FC.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: FC.scrim.opacity(0.18), radius: 15, y: 8)
            .padding(.horizontal, 20).padding(.bottom, 18)
    }
}

/// A help line under a form section.
struct Help: View {
    var text: String
    init(_ t: String) { text = t }
    var body: some View { Text(text).font(.callout).foregroundStyle(FC.muted).fixedSize(horizontal: false, vertical: true) }
}

/// "Sat Nov 21" for a yyyy-mm-dd date.
func dayLine(_ s: String) -> String? {
    guard let d = ISO8601DateFormatter.day.date(from: s) else { return nil }
    return d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased()
}
