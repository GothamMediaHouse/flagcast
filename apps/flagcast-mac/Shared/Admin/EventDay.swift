import SwiftUI

/// Admin → Event day: every club's tournament that's on today (or scoring now) on one screen. TVs on, par 3
/// cameras, carts scoring in the last 20 minutes and the last score, worst first, so Flagcast staff see where help
/// is needed. Tap one to open its desk. Shared by the Mac and iPhone Manager's Admin.
struct EventDayList: View {
    @Environment(AdminModel.self) private var admin
    @State private var now = Date()

    /// on today: its date is today, or carts or TVs are active
    static func today(_ events: [AdminEvent], now: Date = Date()) -> [AdminEvent] {
        let day = ISO8601DateFormatter.day.string(from: now), recent = (now.timeIntervalSince1970 - 3 * 3600) * 1000
        return events.filter { !$0.gone && !$0.archived && ($0.date == day || $0.lastScore > recent || $0.online > 0) }
            .sorted { trouble($0) > trouble($1) }
    }
    /// how much needs a look: TVs off, and carts not scoring
    static func trouble(_ e: AdminEvent) -> Int {
        let tvsOff = max(0, e.screens - e.online), quiet = e.lastScore > 0 ? max(0, e.teams - e.scoringNow) : 0
        return tvsOff * 3 + quiet
    }

    var body: some View {
        let list = Self.today(admin.events, now: now)
        VStack(alignment: .leading, spacing: 12) {
            if list.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "sun.max").font(.system(size: 30)).foregroundStyle(.secondary)
                    Text("Nothing on today").font(.headline)
                    Text("Tournaments show here on their day, or as soon as their carts start scoring.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(30)
            }
            ForEach(list) { e in
                Button { admin.open(e.id) } label: { EventDayRow(e: e, now: now) }.buttonStyle(.plain)
            }
        }
        .task { await admin.refreshEvents() }
        .task { while !Task.isCancelled { try? await Task.sleep(for: .seconds(60)); now = Date(); await admin.refreshEvents() } }
    }
}

struct EventDayRow: View {
    let e: AdminEvent, now: Date
    var body: some View {
        let tvOK = e.screens == 0 || e.online == e.screens
        let started = e.lastScore > 0
        let cartsOK = !started || e.scoringNow >= e.teams * 3 / 4
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.name).font(.headline).lineLimit(1)
                    Text([e.clubName, e.locked ? "Results locked" : nil].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: tvOK && cartsOK ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(tvOK && cartsOK ? Color.green : Color.orange)
            }
            HStack(spacing: 16) {
                stat(e.screens == 0 ? "No TVs" : "\(e.online)/\(e.screens) TVs on", ok: tvOK)
                stat(e.cams.isEmpty ? "No cameras" : "\(e.cams.count) camera\(e.cams.count == 1 ? "" : "s")", ok: true)
                stat(started ? "\(e.scoringNow)/\(e.teams) carts scoring" : "\(e.teams) teams, not started", ok: cartsOK)
                if started { stat("last score \(Date(timeIntervalSince1970: e.lastScore / 1000).formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))", ok: now.timeIntervalSince1970 * 1000 - e.lastScore < 20 * 60000) }
            }
            .font(.caption)
        }
        .padding(14)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }
    private func stat(_ s: String, ok: Bool) -> some View { Text(s).foregroundStyle(ok ? Color.secondary : Color.orange).fontWeight(ok ? .regular : .semibold) }
}
