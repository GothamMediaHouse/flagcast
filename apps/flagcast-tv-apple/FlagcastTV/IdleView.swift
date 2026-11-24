import SwiftUI

/// Between tournaments: the club's logo (Flagcast's only when the club has none), the next tournament and a clock.
struct IdleView: View {
    let now: Now

    private var nextLine: String? {
        guard let n = now.next else { return nil }
        return n.date.isEmpty ? n.name : "\(n.name) · \(Self.long(n.date))"
    }
    static func long(_ s: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: s) else { return s }
        let o = DateFormatter(); o.locale = Locale(identifier: "en_US"); o.dateFormat = "EEE MMM d"; return o.string(from: d)
    }

    var body: some View {
        VStack(spacing: 34) {
            HStack { Spacer(); TimelineView(.everyMinute) { c in Text(c.date, style: .time).font(Theme.mono(28)).foregroundStyle(Theme.dim) } }
            Spacer()
            ClubLogo(url: now.club.flagcast ? nil : Server.url(now.club.logo), height: 280)
            Text(now.club.name.isEmpty ? "WELCOME" : "WELCOME TO \(now.club.name.uppercased())").font(Theme.display(84)).foregroundStyle(Theme.txt)
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.6)
            if let line = nextLine {
                (Text("Next tournament: ").foregroundStyle(Color(hex: "c9d6cc")) + Text(line).bold().foregroundStyle(Color.accent(now.club.accent)))
                    .font(.system(size: 38))
                Text("Live scores show here on the day").font(Theme.mono(24)).foregroundStyle(Theme.dim)
            }
            Spacer(); Spacer()
        }
        .padding(60)
    }
}

/// a club or tournament logo from flagcast.app; the Flagcast wordmark when there's none
struct ClubLogo: View {
    let url: URL?
    var height: CGFloat
    var body: some View {
        if let url {
            AsyncImage(url: url) { img in img.resizable().scaledToFit() } placeholder: { Color.clear }
                .frame(maxWidth: height * 2.4, maxHeight: height)
                .accessibilityHidden(true)
        } else {
            Image("Wordmark").resizable().scaledToFit().frame(maxWidth: height * 2.4, maxHeight: height * 0.7).accessibilityLabel("Flagcast")
        }
    }
}
