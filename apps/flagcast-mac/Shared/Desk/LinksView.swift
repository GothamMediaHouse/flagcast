import SwiftUI
import CoreImage.CIFilterBuiltins

/// Links and cards: the pages to share, the tournament code for staff, cart cards to print, and the hole-in-one log.
struct LinksView: View {
    @Bindable var doc: DeskDoc
    @State private var printing = false

    private var links: [(String, String, URL, Bool)] {
        let p3 = doc.ev.course.holes.first { $0.par == 3 }?.n ?? 1
        return [("Live leaderboard for phones", "Share with players, guests and anyone at home.", doc.liveURL, false),
                ("Big screens", "Open full screen on each TV, or add as a web page in Screens or OBS.", doc.boardURL, false),
                ("Course notice to print", "A sign for the first tee, the clubhouse door and each camera hole: cameras are on, and what the course map shares.", URL(string: "\(doc.liveURL.absoluteString)/notice")!, false),
                ("One par 3 only", "For a TV at that tee. Change the hole number at the end.", URL(string: "\(doc.boardURL.absoluteString)?hole=\(p3)")!, false),
                ("Leaderboard only", "Just the standings, no par 3 or sponsor pages.", URL(string: "\(doc.boardURL.absoluteString)?show=leaderboard")!, false),
                ("This desk", "Keep this private. Anyone with it can change the tournament.", doc.deskURL, true)]
    }

    var body: some View {
        DeskPage(doc: doc, section: .links) {
            Button { printing = true } label: { Label("Print cart cards", systemImage: "printer") }.buttonStyle(GlassButton())
        } title: {
            HeroTitle(title: "Links & cart cards", size: 52, sub: "Pages to share and cards to print", subBeside: true)
        } content: {
            CardForm {
            SwiftUI.Section("Links") {
                ForEach(links, id: \.0) { name, help, url, secret in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).fontWeight(.medium)
                            Text(help).font(.callout).foregroundStyle(.secondary)
                            Text(secret ? url.absoluteString.replacingOccurrences(of: doc.key, with: String(repeating: "•", count: 10)) : url.absoluteString)
                                .font(.callout.monospaced()).foregroundStyle(.tertiary).textSelection(.enabled).lineLimit(1)
                        }
                        Spacer()
                        Button("Copy") { copy(url.absoluteString); doc.flash("Copied.") }
                        if !secret { Button("Open") { NSWorkspace.shared.open(url) } }
                    }
                }
            }
            SwiftUI.Section {
                LabeledContent("Tournament code") { Text(doc.id.uppercased()).font(.title2.monospaced().weight(.semibold)).textSelection(.enabled) }
            } footer: { Help("Golf pros and marshals sign in to the Flagcast phone app with this code and their PIN. Add them and their PINs on the Staff page.") }
            SwiftUI.Section {
                HStack {
                    Text("One card per team with its QR code. Players scan it to open their scorecard: no app to download.").foregroundStyle(.secondary)
                    Spacer()
                    Button { printing = true } label: { Label("Print Cart Cards…", systemImage: "printer") }.buttonStyle(.borderedProminent)
                }
            } header: { Text("Cart cards") }
            SwiftUI.Section("Hole-in-one log") {
                if doc.live?.aces.isEmpty ?? doc.ev.aces.isEmpty { Text("None yet.").foregroundStyle(.secondary) }
                ForEach(doc.live?.aces ?? doc.ev.aces, id: \.self) { a in
                    HStack {
                        Text("Hole \(a.hole): ").foregroundStyle(.secondary) + Text(a.name).fontWeight(.semibold) + Text(" (\(a.team)), \(Date(timeIntervalSince1970: a.at / 1000).formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary)
                        Spacer()
                        Button("Remove (entered by mistake)") { Task { await doc.day("ace", ["remove": a.at], done: "Removed.") } }
                    }
                }
            }
            }
        }
        .sheet(isPresented: $printing) { CartCardsSheet(doc: doc) }
    }
}

// MARK: - cart cards

/// A QR code image for a link (Core Image, no network).
enum QR {
    static func image(_ s: String, scale: CGFloat = 8) -> NSImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(s.utf8); f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: out.extent.width, height: out.extent.height))
    }
}

struct CartCard: View {
    let team: DeskTeam, title: String, date: String, url: URL
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title + (date.isEmpty ? "" : " · \(date)")).font(.system(size: 10, weight: .semibold)).textCase(.uppercase).foregroundStyle(.gray)
                Text(team.displayName.isEmpty ? "Team" : team.displayName).font(.system(size: 22, weight: .heavy))
                Text("Start: hole \(team.start)" + (team.flight.isEmpty ? "" : " · Flight \(team.flight)")).font(.system(size: 12, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) { ForEach(team.players) { Text($0.name).font(.system(size: 12)) } }
                Spacer(minLength: 6)
                (Text("Keep score on your phone. ").bold() + Text("Point your camera at the code and tap the link. No app, no sign-in. One person per cart keeps score, and the leaderboard and big screens update as you play."))
                    .font(.system(size: 10)).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 6) {
                if let img = QR.image(url.absoluteString) { Image(nsImage: img).interpolation(.none).resizable().frame(width: 150, height: 150) }
                Text(team.code).font(.system(size: 18, weight: .bold, design: .monospaced))
            }
        }
        .foregroundStyle(.black)
        .padding(22)
        .frame(width: 520, height: 330, alignment: .topLeading)
        .background(.white)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4])).foregroundStyle(.gray.opacity(0.6)))
    }
}

/// Big print: one card a page, the cart number, team and start hole large enough to read from the seat of a cart.
struct BigCartCard: View {
    let team: DeskTeam, title: String, date: String, url: URL
    var body: some View {
        VStack(spacing: 18) {
            Text(title + (date.isEmpty ? "" : " · \(date)")).font(.system(size: 14, weight: .semibold)).textCase(.uppercase).foregroundStyle(.gray)
            Text("CART").font(.system(size: 18, weight: .bold, design: .monospaced)).tracking(6).foregroundStyle(.gray)
            Text(team.cart.isEmpty ? "–" : team.cart).font(.system(size: 150, weight: .heavy)).minimumScaleFactor(0.4).lineLimit(1)
            Text(team.displayName.isEmpty ? "Team" : team.displayName).font(.system(size: 40, weight: .heavy)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.5)
            Text("Start on hole \(team.start)" + (team.flight.isEmpty ? "" : " · Flight \(team.flight)")).font(.system(size: 30, weight: .bold))
            if let img = QR.image(url.absoluteString) { Image(nsImage: img).interpolation(.none).resizable().frame(width: 220, height: 220) }
            Text(team.code).font(.system(size: 28, weight: .bold, design: .monospaced))
            Text("Point your phone’s camera at the code to keep score. No app, no sign-in.").font(.system(size: 16)).multilineTextAlignment(.center)
        }
        .foregroundStyle(.black).padding(40).frame(width: 612, height: 792).background(.white)
    }
}

struct CartCardsSheet: View {
    @Bindable var doc: DeskDoc
    @Environment(\.dismiss) private var dismiss
    @State private var big = false
    private var teams: [DeskTeam] { doc.ev.teams.filter { !$0.code.isEmpty }.sorted { ($0.start, $0.displayName) < ($1.start, $1.displayName) } }
    private var title: String { doc.ev.screens.title.isEmpty ? doc.ev.name : doc.ev.screens.title }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Cart cards").font(.title2.bold())
                Text("\(teams.count) card\(teams.count == 1 ? "" : "s"), \(big ? "one" : "two") per page").foregroundStyle(.secondary)
                Spacer()
                Toggle("Big print", isOn: $big).toggleStyle(.checkbox).help("One card a page, with the cart number and start hole in large type")
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button { printCards() } label: { Label("Print…", systemImage: "printer") }.keyboardShortcut("p").buttonStyle(.borderedProminent).disabled(teams.isEmpty)
            }
            .padding(16)
            Divider()
            ScrollView {
                if teams.isEmpty {
                    ContentUnavailableView("No cards yet", systemImage: "qrcode", description: Text(doc.dirty ? "Save first (⌘S): new teams get their codes when you save." : "Add teams on the Teams page and save."))
                } else {
                    LazyVStack(spacing: 14) { ForEach(teams) { CartCard(team: $0, title: title, date: doc.ev.date, url: doc.cartURL($0.code)) } }.padding(20)
                }
            }
            .background(Color(nsColor: .underPageBackgroundColor))
        }
        .frame(width: 600, height: 640)
    }

    /// Print with the Mac's print dialog (or save as PDF from it): two cards to a US Letter page.
    private func printCards() {
        let per = big ? 1 : 2
        let pages = stride(from: 0, to: teams.count, by: per).map { Array(teams[$0..<min($0 + per, teams.count)]) }
        let page = CGSize(width: 612, height: 792)
        let big = self.big
        let content = VStack(spacing: 0) {
            ForEach(Array(pages.enumerated()), id: \.offset) { _, set in
                if big { ForEach(set) { BigCartCard(team: $0, title: title, date: doc.ev.date, url: doc.cartURL($0.code)) } }
                else {
                    VStack(spacing: 40) { ForEach(set) { CartCard(team: $0, title: title, date: doc.ev.date, url: doc.cartURL($0.code)) } }
                        .frame(width: page.width, height: page.height)
                }
            }
        }
        .background(.white).environment(\.colorScheme, .light)
        let v = NSHostingView(rootView: content)
        v.frame = NSRect(x: 0, y: 0, width: page.width, height: page.height * CGFloat(pages.count))
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize = NSSize(width: page.width, height: page.height)
        info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
        info.horizontalPagination = .fit; info.verticalPagination = .automatic; info.isHorizontallyCentered = true
        info.jobDisposition = .spool
        let op = NSPrintOperation(view: v, printInfo: info)
        op.jobTitle = "\(title) cart cards"
        op.showsPrintPanel = true; op.showsProgressPanel = true
        op.run()
    }
}
