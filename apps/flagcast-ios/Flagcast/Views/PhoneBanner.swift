import SwiftUI

/// "Routed to phones": when Admin, the desk or a pro points every player's phone at something
/// (state.live.phone), the leaderboard and scorecard show this banner (matches public/golf/phonecast.js).
/// It shows while the route is under 20 minutes old and until the player closes it (remembered per route).
enum PhoneCast {
    private static func key(_ id: String) -> String { "flagcast:phone:\(id)" }

    static func current(_ s: EventState, id: String) -> PhoneRoute? {
        guard let r = s.live.phone else { return nil }
        let seen = UserDefaults.standard.double(forKey: key(id))
        guard r.at > seen, Date().timeIntervalSince1970 * 1000 - r.at < 20 * 60_000 else { return nil }
        return r
    }
    static func dismiss(_ r: PhoneRoute, id: String) { UserDefaults.standard.set(r.at, forKey: key(id)) }

    static func title(_ s: EventState, _ r: PhoneRoute) -> String {
        if r.isCamera { return "Live now: hole \(r.hole) camera" }
        if r.k == "sponsor" { return s.sponsors.first { $0.id == r.sponsor }?.name ?? "Our sponsor" }
        if r.k == "lb" && !r.fl.isEmpty { return "Leaderboard · Flight \(r.fl)" }
        return ["lb": "Leaderboard", "contests": "Contests", "skins": "Skins", "fund": "Fundraising", "sponsors": "Our sponsors", "schedule": "Schedule"][r.k] ?? "Have a look"
    }

    /// A route waiting for the leaderboard to open on it (when "See it" is tapped on the scorecard).
    @MainActor static var pending: [String: PhoneRoute] = [:]
}

struct PhoneBanner: View {
    var state: EventState
    var route: PhoneRoute
    var go: (PhoneRoute) -> Void
    var close: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        let sp = route.k == "sponsor" ? state.sponsors.first { $0.id == route.sponsor } : nil
        let button = sp != nil ? (sp!.url.isEmpty ? "" : "Open") : route.isCamera ? "Watch" : "See it"
        let sub = route.text.isEmpty ? (sp.map { $0.offer.isEmpty ? $0.line : $0.offer } ?? "") : route.text
        HStack(spacing: 12) {
            if let sp, let img = SponsorBadge.image(sp.logo) {
                Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: 70, maxHeight: 34)
                    .padding(3).background(.white, in: RoundedRectangle(cornerRadius: 6))
            } else {
                Text(route.isCamera ? "LIVE" : "NOW").font(.caption2.monospaced().weight(.bold)).tracking(1.2)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(route.isCamera ? Color(UIColor(hex: 0xc8312b)) : Color(UIColor(hex: 0xe8c547)), in: RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(route.isCamera ? .white : Color.fcOnFlag)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(PhoneCast.title(state, route)).font(.subheadline.weight(.bold)).foregroundStyle(Color.fcOnGreen).lineLimit(2)
                if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(Color.fcOnGreenMuted).lineLimit(2) }
            }
            Spacer(minLength: 4)
            if !button.isEmpty {
                Button(button) {
                    close()
                    if let sp, let u = URL(string: sp.url) { openURL(u) } else { go(route) }
                }
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 14).frame(minHeight: 40)
                .background(Color(UIColor(hex: 0xe8c547)), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(Color.fcOnFlag)
            }
            Button { close() } label: { Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundStyle(Color.fcOnGreenMuted).frame(width: 32, height: 40) }
                .accessibilityLabel("Close")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color(UIColor(hex: 0x123628)), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18)))
        .shadow(color: .black.opacity(0.35), radius: 15, y: 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: 560)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
    }
}
