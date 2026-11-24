import SwiftUI
import MapKit

/// "Everyone" in the Course tab: a satellite map with you (the phone's GPS), your group and every other group
/// sharing its spot (POST …/where → groups, public/golf/groupsmap.js on the web). Only while the tournament is on:
/// the server leaves out groups that hide and spots older than 15 minutes, and never sends anyone's cart code.
struct GroupSpot: Identifiable, Equatable {
    var id: String { team }
    var team: String, name: String, hole: Int, at: GeoPoint, t: Date, me: Bool

    init?(_ d: [String: Any]) {
        guard let team = d["team"] as? String, let at = d["at"] as? [Double], at.count == 2 else { return nil }
        self.team = team
        name = d["name"] as? String ?? ""
        hole = (d["hole"] as? NSNumber)?.intValue ?? 0
        self.at = GeoPoint(lat: at[0], lng: at[1])
        t = Date(timeIntervalSince1970: ((d["t"] as? NSNumber)?.doubleValue ?? 0) / 1000)
        me = d["me"] as? Bool ?? false
    }
}

/// A group's choice to hide its spot from the other golfers (the desk still sees it for pace of play). Kept per
/// cart code on this phone, and sent with every spot.
enum GroupPrivacy {
    static func key(_ code: String) -> String { "flagcast.hide.\(code)" }
    static func hidden(_ code: String) -> Bool { UserDefaults.standard.bool(forKey: key(code)) }
    static func set(_ code: String, _ on: Bool) { UserDefaults.standard.set(on, forKey: key(code)) }
}

struct GroupsMapView: View {
    @Bindable var model: ScorecardModel
    let state: EventState
    @State private var loc = Locator.shared
    @State private var groups: [GroupSpot] = []
    @State private var off = false
    @State private var problem: String?
    @State private var serverNow = Date()
    @State private var camera: MapCameraPosition = .automatic
    @State private var fitted = false
    @State private var hide = false
    @State private var listOpen = false

    private var others: [GroupSpot] { groups.filter { !$0.me }.sorted { ($0.hole == 0 ? 99 : $0.hole) < ($1.hole == 0 ? 99 : $1.hole) } }
    private var on: Bool { Geo.trackingOn(state) && !off }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $camera, interactionModes: [.zoom, .pan, .rotate]) {
                // the holes: tee to green round the doglegs, faint, with the hole number on the green
                ForEach(state.map.holes.keys.sorted(), id: \.self) { n in
                    if let h = state.map.holes[n], let g = Geo.middle(h) {
                        if let tee = h.tee {
                            MapPolyline(coordinates: ([tee] + h.line + [g]).map(\.coordinate)).stroke(.white.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [4, 5]))
                        }
                        Annotation("", coordinate: g.coordinate) {
                            Text("\(n)").font(.caption2.weight(.heavy)).monospacedDigit().foregroundStyle(Color.fcOnFlag)
                                .frame(width: 20, height: 20).background(.white.opacity(0.85), in: Circle())
                        }
                    }
                }
                ForEach(groups) { g in
                    // your phone's own dot is newer than your group's last spot
                    if !(g.me && loc.fix != nil) {
                        Annotation(g.me ? "Your group" : shortName(g.name), coordinate: g.at.coordinate) { pin(g) }
                    }
                }
                if let me = loc.fix?.at {
                    Annotation("You", coordinate: me.coordinate) {
                        Circle().fill(Color(UIColor(hex: 0x2f7bff))).frame(width: 16, height: 16)
                            .overlay(Circle().stroke(.white, lineWidth: 3)).background(Circle().fill(Color.blue.opacity(0.22)).frame(width: 34, height: 34))
                    }
                }
            }
            .mapStyle(.imagery(elevation: .flat))
            .mapControlVisibility(.hidden)
            .ignoresSafeArea(edges: .bottom)
            .onChange(of: loc.fix?.at) { _, _ in if !fitted { fit() } }

            status.padding(.horizontal, 12).padding(.top, 10)
        }
        .safeAreaInset(edge: .bottom) { bottomPanel }
        .environment(\.colorScheme, .dark)
        .task(id: model.teamId) {
            hide = GroupPrivacy.hidden(model.code)
            fitted = false
            fit()
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(20))
            }
        }
        .onAppear { if loc.on { loc.resume() } }
    }

    // ---- data ----
    private func load() async {
        guard let t = model.teamId else { return }
        do {
            let r = try await API.post(model.id, "where", ["code": model.code, "team": t, "hide": GroupPrivacy.hidden(model.code)])
            groups = ((r["groups"] as? [[String: Any]]) ?? []).compactMap(GroupSpot.init)
            serverNow = ((r["now"] as? NSNumber)?.doubleValue).map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
            off = false; problem = nil
            if !fitted { fit() }
        } catch let e as APIError where e.status == 409 {
            groups = []; off = true; problem = nil
        } catch let e as APIError {
            problem = e.isOffline ? "No signal. The map shows the last spots it had." : e.message
        } catch {}
    }

    /// Everyone and you on screen; the whole course before anyone has a spot.
    private func fit() {
        var pts = groups.map(\.at)
        if let me = loc.fix?.at { pts.append(me) }
        if pts.isEmpty { pts = state.map.holes.values.flatMap { [$0.tee, Geo.middle($0)].compactMap { $0 } } }
        guard !pts.isEmpty else { return }
        if !groups.isEmpty || loc.fix != nil { fitted = true }
        let lats = pts.map(\.lat), lngs = pts.map(\.lng)
        let c = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lngs.min()! + lngs.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.003, (lats.max()! - lats.min()!) * 1.5), longitudeDelta: max(0.003, (lngs.max()! - lngs.min()!) * 1.5))
        withAnimation(.easeInOut(duration: 0.4)) { camera = .region(MKCoordinateRegion(center: c, span: span)) }
    }

    private func zoom(to p: GeoPoint) {
        withAnimation(.easeInOut(duration: 0.4)) { camera = .camera(MapCamera(centerCoordinate: p.coordinate, distance: 450)) }
    }

    // ---- pieces ----
    private func shortName(_ n: String) -> String { n.components(separatedBy: " / ").first ?? n }

    private func pin(_ g: GroupSpot) -> some View {
        Text(g.hole > 0 ? "\(g.hole)" : "?").font(.caption.weight(.bold)).monospacedDigit()
            .frame(minWidth: 26, minHeight: 26).padding(.horizontal, 3)
            .background(g.me ? Color.fcFlag : Color(UIColor(hex: 0x3a8bff)), in: Capsule())
            .foregroundStyle(g.me ? Color.fcOnFlag : .white)
            .overlay(Capsule().stroke(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
            .accessibilityLabel(g.me ? "Your group, hole \(g.hole)" : "\(g.name), hole \(g.hole)")
    }

    @ViewBuilder private var status: some View {
        let text: String? =
            !on ? (state.locked ? "The results are final, so group spots are off." : "Groups show here on the day of the tournament\(state.date.isEmpty ? "" : " (\(state.date))"), until the results are final.")
            : problem ?? (others.isEmpty ? "No other groups on the map yet. A group shows up when someone in it has GPS on in Flagcast." : nil)
        if let text {
            Text(text).font(.footnote).foregroundStyle(.white).multilineTextAlignment(.center)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color(UIColor(hex: 0x0b1a12)).opacity(0.88), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if loc.on {
                    Button { fitted = false; fit() } label: { Label("Everyone", systemImage: "person.3.fill") }.buttonStyle(.fc(.plain, full: true))
                    Button { if let me = loc.fix?.at { zoom(to: me) } } label: { Label("Find me", systemImage: "location.fill") }
                        .buttonStyle(.fc(.plain, full: true)).disabled(loc.fix == nil)
                } else {
                    Button { loc.start() } label: { Label("Use my GPS to show where I am", systemImage: "location.fill") }.buttonStyle(.fc(.primary, full: true))
                }
            }
            if let e = loc.error { Text(e).font(.footnote).foregroundStyle(Color.fcMuted) }
            if on {
                Toggle("Hide my group from other golfers", isOn: $hide)
                    .font(.subheadline).tint(Color.fcPrimary)
                    .onChange(of: hide) { _, v in GroupPrivacy.set(model.code, v); Task { await load() } }
                if !others.isEmpty {
                    DisclosureGroup(isExpanded: $listOpen) {
                        VStack(spacing: 6) {
                            ForEach(others) { g in
                                Button { zoom(to: g.at) } label: {
                                    HStack(spacing: 10) {
                                        pin(g)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(g.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                            Text("\(g.hole > 0 ? "On hole \(g.hole)" : "On the course") · \(ago(g.t))").font(.caption).foregroundStyle(Color.fcMuted)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        Text("\(others.count) other group\(others.count == 1 ? "" : "s") on the course").font(.subheadline.weight(.semibold))
                    }
                    .tint(Color.fcInk)
                }
            }
        }
        .foregroundStyle(Color.fcInk)
        .padding(14)
        .background(Color.fcCard)
        .environment(\.colorScheme, .light)
    }

    private func ago(_ t: Date) -> String {
        let m = Int((serverNow.timeIntervalSince(t) / 60).rounded())
        return m < 1 ? "just now" : "\(m) min ago"
    }
}
