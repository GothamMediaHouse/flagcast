import ActivityKit
import SwiftUI
import WidgetKit

/// The Flagcast widget extension: the golfer's live view on the lock screen and in the Dynamic Island.
/// The app starts it (Flagcast/Model/LiveView.swift); the server keeps it up to date by Apple push (liveact.js).
@main
struct FlagcastLiveBundle: WidgetBundle {
    var body: some Widget { FlagcastLiveActivity() }
}

private extension Color {
    init(hex: String) {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0x123628
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
    static let liveUnder = Color(red: 1, green: 0.49, blue: 0.44)     // under par: red, as on the boards
    static let liveFlag = Color(red: 0.91, green: 0.77, blue: 0.28)   // Flagcast's flag yellow
    static let liveRed = Color(red: 1, green: 0.42, blue: 0.37)
}

private func display(_ size: CGFloat, _ bold: Bool = true) -> Font {
    .custom(bold ? "BarlowCondensed-Bold" : "BarlowCondensed-SemiBold", size: size)
}

private extension LiveCard {
    var scoreColor: Color { tone < 0 ? .liveUnder : .white }
    var holeLine: String { yds > 0 ? "Par \(par) · \(yds)" : "Par \(par)" }
    var thruLine: String { thru == "F" ? "Finished" : thru == "—" || thru.hasPrefix("Starts") ? thru : "Thru \(thru)" }
}

struct FlagcastLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlagcastLiveAttributes.self) { ctx in
            LockScreenCard(at: ctx.attributes, c: ctx.state, stale: ctx.isStale)
                .activityBackgroundTint(Color(red: 0.08, green: 0.09, blue: 0.09).opacity(0.78))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(link(ctx.attributes))
        } dynamicIsland: { ctx in
            let c = ctx.state, at = ctx.attributes
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Crest(at: at, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.team).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Text("Hole \(c.hole) · \(c.holeLine)").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(c.score).font(display(34)).foregroundStyle(c.scoreColor).monospacedDigit()
                        Text(c.thruLine).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !c.msg.isEmpty {
                        MessageBox(c: c)
                    } else {
                        HStack {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(c.pos).font(display(20))
                                Text("of \(c.of)").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(c.leader).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .padding(.horizontal, 4)
                    }
                }
            } compactLeading: {
                Crest(at: at, size: 20)
            } compactTrailing: {
                HStack(spacing: 6) {
                    Text(c.score).font(display(17)).foregroundStyle(c.scoreColor).monospacedDigit()
                    Text(c.pos).font(display(17)).monospacedDigit()
                }
            } minimal: {
                Text(c.score).font(display(15)).foregroundStyle(c.scoreColor).minimumScaleFactor(0.6)
            }
            .widgetURL(link(at))
            .keylineTint(at.accent.isEmpty ? Color.liveFlag : Color(hex: at.accent))
        }
    }

    private func link(_ at: FlagcastLiveAttributes) -> URL? { URL(string: "flagcast://g/\(at.event)/s/\(at.code)") }
}

/// The club's logo (left in the app group by the app), on its accent colour. The Flagcast logo only when the club
/// has none, or the tournament is a demo.
private struct Crest: View {
    let at: FlagcastLiveAttributes
    let size: CGFloat
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        if at.logo, let f = LiveShared.logoFile(at.event), let img = UIImage(contentsOfFile: f.path) {
            Image(uiImage: img).resizable().scaledToFit().padding(size * 0.1)
                .frame(width: size, height: size)
                .background(at.accent.isEmpty ? Color.white.opacity(0.12) : Color(hex: at.accent), in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.18), lineWidth: 1))
                .accessibilityLabel("Club logo")
        } else if size < 26 {
            Image(systemName: "flag.fill").font(.system(size: size * 0.6, weight: .bold)).foregroundStyle(Color.liveFlag)
                .frame(width: size, height: size).accessibilityLabel("Flagcast")
        } else {
            Image("Logo").resizable().scaledToFit().frame(width: size * 2.6, height: size * 0.55, alignment: .leading)
                .frame(height: size).accessibilityLabel("Flagcast")
        }
    }
}

private struct MessageBox: View {
    let c: LiveCard
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(c.from.isEmpty ? "Pro shop" : c.from).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.liveFlag).lineLimit(1)
            Text(c.msg).font(.system(size: 12)).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(Color.liveFlag.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.liveFlag.opacity(0.45), lineWidth: 1))
    }
}

private struct LockScreenCard: View {
    let at: FlagcastLiveAttributes
    let c: LiveCard
    let stale: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Crest(at: at, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(at.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(c.team).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
                Spacer(minLength: 4)
                if c.final {
                    Text("FINAL").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(Color.liveFlag)
                } else {
                    HStack(spacing: 4) {
                        Circle().fill(Color.liveRed).frame(width: 6, height: 6)
                        Text("LIVE").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(Color.liveRed)
                    }
                }
            }
            HStack(spacing: 6) {
                Stat(value: c.score, label: c.thruLine, color: c.scoreColor)
                Stat(value: c.pos, label: "of \(c.of)")
                Stat(value: c.final ? "F" : "\(c.hole)", label: c.final ? "Results final" : c.holeLine)
            }
            if !c.msg.isEmpty {
                MessageBox(c: c)
            } else {
                HStack(spacing: 2) {
                    ForEach(0..<max(c.holes, 1), id: \.self) { i in
                        Capsule().fill(i < c.played ? (at.accent.isEmpty ? Color.liveFlag : Color(hex: at.accent)) : i == c.played ? Color.white : Color.white.opacity(0.18))
                            .frame(height: 4)
                    }
                }
                .accessibilityLabel("\(c.played) of \(c.holes) holes played")
            }
            HStack {
                Text(c.leader.isEmpty ? " " : (c.leader == "You lead" ? c.leader : "Leader \(c.leader)")).lineLimit(1)
                Spacer()
                Text(stale ? "Open Flagcast to refresh" : "Updated \(c.updated.formatted(date: .omitted, time: .shortened))")
            }
            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 13)
    }
}

private struct Stat: View {
    let value: String
    let label: String
    var color: Color = .white
    var body: some View {
        VStack(spacing: 3) {
            Text(value).font(display(30)).foregroundStyle(color).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 10.5, weight: .medium)).tracking(0.6).textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.65)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}
