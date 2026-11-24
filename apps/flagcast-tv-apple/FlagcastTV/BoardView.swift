import SwiftUI
import AVKit
import CoreImage.CIFilterBuiltins

/// Tournament day: the board. Header with the tournament's logo and title, the pages in turn (each for its seconds),
/// the ticker along the bottom, an announcement banner, and takeovers (hole in one, a message, a sponsor moment).
struct BoardView: View {
    let feed: Feed
    let eventName: String
    @State private var index = 0
    @State private var shownAt = Date()

    private var pages: [Page] { feed.pages.isEmpty ? [Page(k: "empty", text: "Scores will show here once the first group is out.")] : feed.pages }
    private var current: Page { pages[min(index, pages.count - 1)] }
    private var accent: Color { Color.accent(feed.accent) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                PageView(page: current, accent: accent).id(current.id).transition(.opacity)
                if !feed.flash.isEmpty { flashBanner }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            footer
        }
        .overlay { if let t = feed.take, Date().timeIntervalSince1970 * 1000 < t.until { TakeView(take: t, accent: accent) } }
        .animation(.easeInOut(duration: 0.6), value: current.id)
        .task(id: feed.pages.map(\.id).joined(separator: ",")) {
            // the pages changed (a new playlist, a forced page): keep going from the same kind of page if it's still there
            if index >= pages.count { index = 0 }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Date().timeIntervalSince(shownAt) >= max(4, current.secs ?? 12) { index = (index + 1) % max(1, pages.count); shownAt = Date() }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 28) {
            ClubLogo(url: feed.flagcast ? nil : Server.url(feed.logo), height: 70)
            Text(feed.title.uppercased()).font(Theme.display(58)).foregroundStyle(Theme.txt).lineLimit(1).minimumScaleFactor(0.6)
            Spacer()
            TimelineView(.everyMinute) { c in
                HStack(spacing: 16) {
                    Text(feed.locked ? "FINAL" : "LIVE").font(Theme.mono(22, .semibold)).padding(.horizontal, 12).padding(.vertical, 4)
                        .background(feed.locked ? Theme.dim : accent, in: .rect(cornerRadius: 6)).foregroundStyle(Theme.bg)
                    Text(c.date, style: .time).font(Theme.mono(26)).foregroundStyle(Color(hex: "a9bdb0"))
                }
            }
        }
        .padding(.horizontal, 60).frame(height: 116).background(Theme.green)
    }

    @ViewBuilder private var footer: some View {
        if !feed.ticker.isEmpty {
            Ticker(text: feed.ticker).frame(height: 64).background(Theme.panel).overlay(alignment: .top) { Theme.rule.frame(height: 2) }
        }
    }

    private var flashBanner: some View {
        VStack {
            Spacer()
            Text(feed.flash).font(.system(size: 44, weight: .bold)).foregroundStyle(Theme.bg).multilineTextAlignment(.center)
                .padding(.horizontal, 40).padding(.vertical, 22).frame(maxWidth: .infinity).background(accent)
        }
    }
}

/// one page of the board
struct PageView: View {
    let page: Page
    let accent: Color
    var body: some View {
        switch page.k {
        case "lb": LeaderboardPage(page: page, accent: accent)
        case "cam": CameraPage(page: page)
        case "sponsor": SponsorPage(sponsor: Sponsor(name: page.name ?? "", line: page.line, logo: page.logo ?? ""))
        case "sponsors": SponsorsPage(list: page.list ?? [])
        case "phone": PhonePage(url: page.url ?? "", text: page.text ?? "Live scores on your phone")
        default: Text(page.text ?? "").font(.system(size: 40)).foregroundStyle(Theme.dim).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct LeaderboardPage: View {
    let page: Page
    let accent: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text((page.sub ?? "").uppercased()).font(Theme.mono(22)).tracking(3).foregroundStyle(Theme.dim)
                    Text("LEADERBOARD").font(Theme.display(74)).foregroundStyle(Theme.txt)
                }
                Spacer()
                if let s = page.sponsor { HStack(spacing: 14) { Text("Presented by").font(.system(size: 24)).foregroundStyle(Theme.dim); SponsorMark(sponsor: s, height: 60) } }
                else if (page.pages ?? 1) > 1 { Text("Page \(page.page ?? 1) of \(page.pages ?? 1)").font(Theme.mono(24)).foregroundStyle(Theme.dim) }
            }
            .padding(.bottom, 18)
            HStack {
                Text("POS").frame(width: 120, alignment: .leading)
                Text("TEAM").frame(maxWidth: .infinity, alignment: .leading)
                Text(page.points == true ? "POINTS" : "TO PAR").frame(width: 200, alignment: .trailing)
                Text("THRU").frame(width: 160, alignment: .trailing)
            }
            .font(Theme.mono(22)).tracking(2).foregroundStyle(Theme.dim).padding(.horizontal, 20).padding(.bottom, 10)
            Theme.rule.frame(height: 3)
            ForEach(Array((page.rows ?? []).enumerated()), id: \.offset) { i, r in
                HStack {
                    Text(r.pos).font(Theme.mono(34)).foregroundStyle(Theme.dim).frame(width: 120, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(r.name).font(.system(size: 40, weight: .bold)).foregroundStyle(Theme.txt).lineLimit(1)
                        if !r.sub.isEmpty { Text(r.sub).font(.system(size: 22)).foregroundStyle(Theme.dim).lineLimit(1) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(r.score).font(Theme.mono(46, .semibold)).foregroundStyle(r.under ? Theme.red : Theme.txt).frame(width: 200, alignment: .trailing)
                    Text(r.thru).font(Theme.mono(34, .semibold)).foregroundStyle(Color(hex: "c9d6cc")).frame(width: 160, alignment: .trailing)
                }
                .padding(.horizontal, 20).frame(maxHeight: 92)
                .background(i % 2 == 1 ? Theme.row : .clear)
                .overlay(alignment: .bottom) { Theme.rule.frame(height: 1) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 60).padding(.top, 30)
    }
}

/// a par 3 camera: Flagcast's HLS from Cloudflare Stream, muted
struct CameraPage: View {
    let page: Page
    @State private var player = AVPlayer()
    var body: some View {
        ZStack(alignment: .topLeading) {
            VideoPlayer(player: player).disabled(true).allowsHitTesting(false)
            HStack(spacing: 14) {
                Text("LIVE · HOLE \(page.hole ?? 0)").font(Theme.mono(28, .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8).background(Color(hex: "c6362b"), in: .rect(cornerRadius: 8))
                if let p = page.par { Text("PAR \(p)\((page.yards ?? 0) > 0 ? " · \(page.yards!) YDS" : "")").font(Theme.mono(26)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8).background(.black.opacity(0.55), in: .rect(cornerRadius: 8)) }
            }
            .padding(30)
            if let s = page.sponsor {
                VStack { Spacer(); HStack { Spacer(); HStack(spacing: 12) { Text("CAM BY").font(Theme.mono(20)).foregroundStyle(.white); SponsorMark(sponsor: s, height: 44) }
                    .padding(14).background(.black.opacity(0.55), in: .rect(cornerRadius: 10)) } }.padding(30)
            }
        }
        .background(.black)
        .onAppear {
            guard let u = URL(string: page.url ?? "") else { return }
            player.isMuted = true
            player.replaceCurrentItem(with: AVPlayerItem(url: u))
            player.play()
        }
        .onDisappear { player.pause(); player.replaceCurrentItem(with: nil) }
    }
}

struct SponsorMark: View {
    let sponsor: Sponsor
    var height: CGFloat
    var body: some View {
        if let u = URL(string: sponsor.logo), !sponsor.logo.isEmpty {
            AsyncImage(url: u) { $0.resizable().scaledToFit() } placeholder: { Text(sponsor.name).font(.system(size: height * 0.5, weight: .bold)) }
                .frame(maxWidth: height * 3.2, maxHeight: height).accessibilityLabel(sponsor.name)
        } else {
            Text(sponsor.name).font(.system(size: height * 0.55, weight: .bold)).foregroundStyle(Theme.txt).lineLimit(1)
        }
    }
}

struct SponsorPage: View {
    let sponsor: Sponsor
    var body: some View {
        VStack(spacing: 40) {
            Text("THANK YOU TO").font(Theme.mono(26)).tracking(4).foregroundStyle(Theme.dim)
            SponsorMark(sponsor: sponsor, height: 300)
            if let l = sponsor.line, !l.isEmpty { Text(l).font(.system(size: 40)).foregroundStyle(Color(hex: "c9d6cc")).multilineTextAlignment(.center) }
        }
        .padding(80).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SponsorsPage: View {
    let list: [Sponsor]
    var body: some View {
        VStack(spacing: 40) {
            Text("THANKS TO OUR SPONSORS").font(Theme.display(64)).foregroundStyle(Theme.txt)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 40), count: min(4, max(1, list.count))), spacing: 40) {
                ForEach(list, id: \.self) { s in SponsorMark(sponsor: s, height: 130).frame(height: 160) }
            }
        }
        .padding(80).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// "Live scores on your phone": a QR code to the tournament's live page
struct PhonePage: View {
    let url: String
    let text: String
    var body: some View {
        HStack(spacing: 90) {
            if let img = QR.image(url) {
                Image(uiImage: img).interpolation(.none).resizable().frame(width: 520, height: 520)
                    .padding(28).background(.white, in: .rect(cornerRadius: 24)).accessibilityLabel("QR code for \(url)")
            }
            VStack(alignment: .leading, spacing: 30) {
                Text(text.uppercased()).font(Theme.display(90)).foregroundStyle(Theme.txt)
                Text("Point your phone’s camera at the code. No app needed: the leaderboard, par 3 cameras and replays.")
                    .font(.system(size: 36)).foregroundStyle(Color(hex: "c9d6cc"))
                Text(url.replacingOccurrences(of: "https://", with: "")).font(Theme.mono(34, .semibold)).foregroundStyle(Theme.flag)
            }
        }
        .padding(100).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum QR {
    static func image(_ s: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator(); f.message = Data(s.utf8); f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)), let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// hole in one, a message or a sponsor moment, over everything until it times out
struct TakeView: View {
    let take: Take
    let accent: Color
    var body: some View {
        ZStack {
            Theme.bg.opacity(0.94)
            VStack(spacing: 30) {
                if take.kind == "ace" { Text("HOLE IN ONE!").font(Theme.display(170)).foregroundStyle(accent) }
                if !take.text.isEmpty { Text(take.text).font(.system(size: take.kind == "ace" ? 60 : 80, weight: .bold)).foregroundStyle(Theme.txt).multilineTextAlignment(.center) }
            }
            .padding(100)
        }
        .ignoresSafeArea()
    }
}

/// the ticker along the bottom: scrolls when it doesn't fit
struct Ticker: View {
    let text: String
    @State private var width: CGFloat = 0
    var body: some View {
        GeometryReader { g in
            TimelineView(.animation) { t in
                let speed = 90.0, span = Double(width + g.size.width)
                let x = width <= g.size.width - 120 ? 60 : g.size.width - CGFloat(t.date.timeIntervalSinceReferenceDate * speed).truncatingRemainder(dividingBy: CGFloat(span))
                Text(text).font(.system(size: 30, weight: .medium)).foregroundStyle(Color(hex: "c9d6cc")).fixedSize()
                    .background(GeometryReader { tg in Color.clear.onAppear { width = tg.size.width } })
                    .offset(x: x).frame(maxHeight: .infinity)
            }
        }
        .clipped()
    }
}
