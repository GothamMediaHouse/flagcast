import SwiftUI
import MapKit

/// "Everyone" in the Course tab: a satellite map with you (the phone's GPS), your group and every other group
/// sharing its spot (POST …/where → groups, public/golf/groupsmap.js on the web). Only while the tournament is on:
/// the server leaves out groups that hide and spots older than 15 minutes, and never sends anyone's cart code.
struct GroupSpot: Identifiable, Equatable {
    var id: String { team }
    var team: String, name: String, hole: Int, at: GeoPoint, t: Date, me: Bool, sample: Bool

    init?(_ d: [String: Any]) {
        guard let team = d["team"] as? String, let at = d["at"] as? [Double], at.count == 2 else { return nil }
        self.team = team
        name = d["name"] as? String ?? ""
        hole = (d["hole"] as? NSNumber)?.intValue ?? 0
        self.at = GeoPoint(lat: at[0], lng: at[1])
        t = Date(timeIntervalSince1970: ((d["t"] as? NSNumber)?.doubleValue ?? 0) / 1000)
        me = d["me"] as? Bool ?? false
        sample = d["sample"] as? Bool ?? false
    }
}

/// A group's choice to hide its spot from the other golfers (the desk still sees it for pace of play). Kept per
/// cart code on this phone, and sent with every spot.
enum GroupPrivacy {
    static func key(_ code: String) -> String { "flagcast.hide.\(code)" }
    static func hidden(_ code: String) -> Bool { UserDefaults.standard.bool(forKey: key(code)) }
    static func set(_ code: String, _ on: Bool) { UserDefaults.standard.set(on, forKey: key(code)) }
}

/// The Everyone map (matches public/golf/groupsmap.js): full-bleed satellite with every group as a pin (hole number
/// and name), your blue dot, round buttons to show everyone or follow you, and a sheet with the course strip (which
/// hole each group is on), the groups just ahead and behind, every group with how far away it is, and the switch
/// to show or hide your group.
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
    @State private var show = true
    @State private var expanded = false
    @State private var picked: String?
    @State private var follow = false
    /// the ready-made notes golfers can send another group (empty when the desk turned them off)
    @State private var notes: [String] = []
    @State private var sentMsg: String?
    @State private var sending = false

    static let stale: TimeInterval = 6 * 60
    private static let blue = Color(UIColor(hex: 0x3a8bff)), night = Color(UIColor(hex: 0x0b1a12))

    private var others: [GroupSpot] { groups.filter { !$0.me } }
    private var mine: GroupSpot? { groups.first { $0.me } }
    private var on: Bool { Geo.trackingOn(state) && !off }
    private var total: Int { max(1, state.course.holes.count) }
    private var myHole: Int { mine?.hole ?? model.currentHole() }
    private var here: GeoPoint? { loc.fix?.at ?? mine?.at }
    /// holes from you the way the round goes: 1 = the hole ahead, total-1 = the hole behind
    private func gap(_ g: GroupSpot) -> Int? { myHole > 0 && g.hole > 0 ? (g.hole - myHole + total) % total : nil }
    private func away(_ g: GroupSpot) -> Double? { Geo.yds(here, g.at) }

    var body: some View {
        ZStack(alignment: .top) {
            map
            topBand
        }
        .overlay(alignment: .bottomTrailing) { fabs.padding(.trailing, 12).padding(.bottom, 14) }
        .safeAreaInset(edge: .bottom, spacing: 0) { sheet }
        .task(id: model.teamId) {
            show = !GroupPrivacy.hidden(model.code)
            fitted = false
            fit()
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(20))
            }
        }
        .onAppear { if loc.on { loc.resume() } }
        .onChange(of: loc.fix?.at) { _, p in
            if !fitted { fit() }
            if follow, let p { withAnimation(.easeInOut(duration: 0.3)) { camera = .camera(MapCamera(centerCoordinate: p.coordinate, distance: 420)) } }
        }
    }

    // ---- the map ----
    private var map: some View {
        Map(position: $camera, interactionModes: [.zoom, .pan, .rotate]) {
            // the holes: tee to green round the doglegs, faint, with the hole number by the green
            ForEach(state.map.holes.keys.sorted(), id: \.self) { n in
                if let h = state.map.holes[n], let g = Geo.middle(h) {
                    if let tee = h.tee {
                        MapPolyline(coordinates: ([tee] + h.line + [g]).map(\.coordinate))
                            .stroke(.white.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 6]))
                    }
                    Annotation("", coordinate: g.coordinate) {
                        Text("\(n)").font(.system(size: 9.5, weight: .heavy, design: .monospaced)).foregroundStyle(Color.fcOnFlag)
                            .frame(width: 19, height: 19).background(.white.opacity(0.8), in: Circle())
                    }
                }
            }
            ForEach(groups) { g in
                // your phone's own dot is newer than your group's last spot
                if !(g.me && loc.fix != nil) {
                    Annotation("", coordinate: g.at.coordinate, anchor: .leading) {
                        GroupPin(group: g, old: !g.me && serverNow.timeIntervalSince(g.t) > Self.stale, picked: picked == g.team)
                            .onTapGesture { focus(g) }
                    }
                }
            }
            if let me = loc.fix?.at {
                Annotation("", coordinate: me.coordinate) {
                    Circle().fill(Color(UIColor(hex: 0x2f7bff))).frame(width: 18, height: 18)
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                        .background(Circle().fill(Color(UIColor(hex: 0x2f7bff)).opacity(0.22)).frame(width: 38, height: 38))
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                        .accessibilityLabel("You")
                }
            }
        }
        .mapStyle(.imagery(elevation: .flat))
        .mapControlVisibility(.hidden)
        .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in follow = false })
    }

    /// "Live · 7 groups" over the top of the map
    private var topBand: some View {
        HStack(spacing: 8) {
            Circle().fill(on && problem == nil ? Color(UIColor(hex: 0x48d17c)) : Color(UIColor(hex: 0x8a948d))).frame(width: 8, height: 8)
            Text(!on ? "OFF TODAY" : problem != nil ? "NO SIGNAL" : "LIVE · \(others.count) GROUP\(others.count == 1 ? "" : "S")")
                .font(.system(size: 12, weight: .semibold, design: .monospaced)).tracking(1)
            Spacer()
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 26)
        .background(LinearGradient(colors: [Self.night.opacity(0.9), Self.night.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
    }

    private var fabs: some View {
        VStack(spacing: 10) {
            fab("arrow.up.left.and.arrow.down.right", "Show everyone", active: false) { picked = nil; follow = false; fitted = false; fit() }
            fab("location.fill", "Find me", active: follow) {
                guard let p = loc.fix?.at else { loc.start(); follow = true; return }
                follow = true; picked = nil
                withAnimation(.easeInOut(duration: 0.4)) { camera = .camera(MapCamera(centerCoordinate: p.coordinate, distance: 420)) }
            }
        }
    }
    private func fab(_ icon: String, _ label: String, active: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: icon).font(.system(size: 19, weight: .semibold))
                .frame(width: 48, height: 48)
                .background(active ? Color(UIColor(hex: 0x2f7bff)) : .white, in: Circle())
                .foregroundStyle(active ? .white : Color(UIColor(hex: 0x123628)))
                .shadow(color: .black.opacity(0.35), radius: 7, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // ---- the sheet ----
    private var sheet: some View {
        VStack(spacing: 0) {
            Button { withAnimation(.snappy(duration: 0.25)) { expanded.toggle() } } label: {
                Capsule().fill(Color.fcLine).frame(width: 40, height: 5).frame(maxWidth: .infinity).padding(.top, 9).padding(.bottom, 8).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Show less" : "Show every group")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if on, let g = pickedGroup {
                        card(g)
                    } else if !on {
                        Text(state.locked ? "The results are final, so the map of groups is off." : "Groups show here on the day of the tournament\(state.date.isEmpty ? "" : " (\(state.date))"), until the results are final.")
                            .font(.subheadline).foregroundStyle(Color.fcMuted)
                    } else {
                        if !loc.on {
                            Button { loc.start(); follow = true } label: { Label("Show where I am", systemImage: "location.fill") }.buttonStyle(.fcPrimary)
                        }
                        if let e = loc.error { Text(e).font(.footnote).foregroundStyle(Color.fcMuted) }
                        strip
                        if myHole > 0 && !others.isEmpty { nearby }
                        everyone
                        privacy
                        if let problem { Text(problem).font(.footnote).foregroundStyle(Color.fcMuted) }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 14)
            }
            .scrollDisabled(!expanded)
            .frame(height: pickedGroup != nil ? 360 : expanded ? 470 : (on ? 190 : 90))
        }
        .foregroundStyle(Color.fcInk)
        .background(Color.fcCard, in: UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22))
        .shadow(color: .black.opacity(0.3), radius: 14, y: -4)
    }

    /// a cell per hole, a dot per group on it; your hole in green
    private var strip: some View {
        let by = Dictionary(grouping: groups.filter { $0.hole > 0 }, by: \.hole)
        return HStack(spacing: 3) {
            ForEach(1...total, id: \.self) { k in
                let gs = by[k] ?? [], isMine = k == myHole
                Button { showHole(k) } label: {
                    VStack(spacing: 3) {
                        Text("\(k)").font(.system(size: 10.5, weight: .semibold, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.6)
                        HStack(spacing: 2) {
                            ForEach(Array(gs.prefix(2).enumerated()), id: \.offset) { _, g in
                                Circle().fill(g.me ? Color.fcFlag : Self.blue).frame(width: 5, height: 5)
                            }
                        }
                        .frame(height: 5)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 5)
                    .background(isMine ? Color.fcGreen : gs.isEmpty ? Color.fcPaper2 : Color(UIColor(hex: 0xdfe9fb)), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .foregroundStyle(isMine ? Color.fcOnGreen : gs.isEmpty ? Color.fcMuted : Color(UIColor(hex: 0x1c3f86)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hole \(k): \(gs.count) group\(gs.count == 1 ? "" : "s")")
            }
        }
    }

    private var nearby: some View {
        let n = total
        let near: [(g: GroupSpot, gap: Int)] = others.compactMap { g in gap(g).map { (g, $0) } }
        let sameHole = near.filter { $0.gap == 0 }.sorted { (away($0.g) ?? 0) < (away($1.g) ?? 0) }
        let ahead: GroupSpot? = near.filter { $0.gap > 0 && $0.gap <= n / 2 }.min { $0.gap < $1.gap }?.g ?? sameHole.first?.g
        let back = near.filter { $0.g.team != ahead?.team && ($0.gap > n / 2 || $0.gap == 0) }
        let behind: GroupSpot? = back.max { ($0.gap == 0 ? n : $0.gap) < ($1.gap == 0 ? n : $1.gap) }?.g
        return HStack(spacing: 8) { nearCard("GROUP AHEAD", ahead); nearCard("GROUP BEHIND", behind) }
    }
    private func nearCard(_ label: String, _ g: GroupSpot?) -> some View {
        Button { if let g { focus(g) } } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.system(size: 10.5, weight: .semibold, design: .monospaced)).tracking(1).foregroundStyle(Color.fcMuted)
                Text(g.map { shortName($0.name) } ?? "—").font(.headline).lineLimit(1)
                Text(g.map { "Hole \($0.hole)\(away($0).map { " · " + yards($0) } ?? "")" } ?? "Nobody yet").font(.caption).foregroundStyle(Color.fcMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(Color.fcPaper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.fcLine))
        }
        .buttonStyle(.plain).disabled(g == nil)
    }

    private var everyone: some View {
        let list = others.sorted { a, b in
            if let x = away(a), let y = away(b) { return x < y }
            return (a.hole == 0 ? 99 : a.hole) < (b.hole == 0 ? 99 : b.hole)
        }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(list.isEmpty ? "EVERY GROUP" : "EVERY GROUP (\(list.count))")
                Spacer()
                if here != nil && !list.isEmpty { Text("AWAY") }
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1.2).foregroundStyle(Color.fcMuted).padding(.bottom, 4)
            if list.isEmpty {
                Text("No other groups on the map yet. A group shows up when someone in it turns on GPS in Flagcast.")
                    .font(.subheadline).foregroundStyle(Color.fcMuted)
            }
            ForEach(list) { g in
                Button { focus(g) } label: {
                    HStack(spacing: 12) {
                        Text(g.hole > 0 ? "\(g.hole)" : "?").font(.system(size: 15, weight: .bold, design: .monospaced))
                            .frame(width: 38, height: 38)
                            .background(serverNow.timeIntervalSince(g.t) > Self.stale ? Color(UIColor(hex: 0x8a948d)) : Self.blue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(.white)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.name).font(.body.weight(.semibold)).lineLimit(1)
                            Text("\(g.hole > 0 ? "Hole \(g.hole)" : "On the course") · \(ago(g.t))").font(.caption).foregroundStyle(Color.fcMuted)
                        }
                        Spacer(minLength: 0)
                        if let d = away(g) { Text(yards(d)).font(.system(size: 15, weight: .bold, design: .monospaced)) }
                    }
                    .padding(.vertical, 9).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }

    private var privacy: some View {
        Toggle(isOn: $show) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Show my group to other golfers").font(.subheadline)
                Text(show ? "They see your group’s name and hole. Never your scores or codes." : "Hidden. Only the tournament desk sees where you are.")
                    .font(.caption).foregroundStyle(Color.fcMuted)
            }
        }
        .tint(Color.fcOK)
        .padding(12)
        .background(Color.fcPaper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onChange(of: show) { _, v in
            guard GroupPrivacy.hidden(model.code) == v else { return }
            GroupPrivacy.set(model.code, !v); Task { await load() }
        }
    }

    // ---- the card for a tapped group: who, where, how they're scoring, and a ready-made note ----
    private var pickedGroup: GroupSpot? { picked.flatMap { p in groups.first { $0.team == p } } }
    private func card(_ g: GroupSpot) -> some View {
        let info = Core.groupInfo(state, state.scores, g.team), n = total
        let whereText: String = {
            if g.me { return "Your group" }
            guard let gp = gap(g) else { return "" }
            if gp == 0 { return "On your hole" }
            return gp <= n / 2 ? "\(gp) hole\(gp == 1 ? "" : "s") ahead of you" : "\(n - gp) hole\(n - gp == 1 ? "" : "s") behind you"
        }()
        let sub = ["On hole \(g.hole > 0 ? "\(g.hole)" : "?")", whereText, g.me ? "" : away(g).map { "\(yards($0)) away" } ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(g.hole > 0 ? "\(g.hole)" : "?").font(.system(size: 16, weight: .bold, design: .monospaced))
                    .frame(width: 44, height: 44).background(g.me ? Color.fcFlag : Self.blue, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .foregroundStyle(g.me ? Color.fcOnFlag : .white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info?.name ?? g.name).font(.headline).lineLimit(1)
                    Text(sub).font(.caption).foregroundStyle(Color.fcMuted)
                }
                Spacer(minLength: 0)
                Button { picked = nil; sentMsg = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).frame(width: 32, height: 32).background(Color.fcPaper2, in: Circle()).foregroundStyle(Color.fcMuted)
                }
                .buttonStyle(.plain).accessibilityLabel("Back to every group")
            }
            HStack(spacing: 6) {
                stat("HOLE", g.hole > 0 ? "\(g.hole)" : "—"); stat("THRU", info?.thru ?? "—"); stat("SCORE", info?.score ?? "—"); stat("PLACE", info?.pos ?? "—")
            }
            if let info, !info.players.isEmpty {
                VStack(spacing: 0) {
                    ForEach(info.players, id: \.id) { p in
                        HStack { Text(p.name).font(.subheadline); Spacer(); Text(p.today).font(.subheadline.monospacedDigit()).foregroundStyle(Color.fcMuted) }
                            .padding(.vertical, 6)
                        if p.id != info.players.last?.id { Divider() }
                    }
                }
            } else if g.sample {
                Text("A sample group on the demo.").font(.subheadline).foregroundStyle(Color.fcMuted)
            }
            if !g.me && !notes.isEmpty {
                Text("Send a quick note. They see it with your group’s name.").font(.footnote).foregroundStyle(Color.fcMuted)
                FlowChips(items: notes, disabled: sending) { k in Task { await send(k, to: g) } }
                if let sentMsg { Text(sentMsg).font(.footnote.weight(.semibold)).foregroundStyle(Color.fcOK) }
            }
        }
        .padding(.top, 2)
    }
    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9.5, weight: .semibold, design: .monospaced)).tracking(1).foregroundStyle(Color.fcMuted)
            Text(value).font(.system(size: 17, weight: .bold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 9).padding(.vertical, 7)
        .background(Color.fcPaper2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    private func send(_ k: Int, to g: GroupSpot) async {
        guard let t = model.teamId, !sending else { return }
        sending = true; sentMsg = nil
        do {
            _ = try await API.post(model.id, "where", ["code": model.code, "team": t, "note": k, "to": g.team])
            sentMsg = "Sent to \(shortName(g.name))."
        } catch let e as APIError { sentMsg = e.message } catch {}
        sending = false
    }

    // ---- data ----
    private func load() async {
        guard let t = model.teamId else { return }
        do {
            let r = try await API.post(model.id, "where", ["code": model.code, "team": t, "hide": GroupPrivacy.hidden(model.code)])
            groups = ((r["groups"] as? [[String: Any]]) ?? []).compactMap(GroupSpot.init)
            notes = r["notes"] as? [String] ?? []
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
        let course = state.map.holes.values.flatMap { [$0.tee, Geo.middle($0)].compactMap { $0 } }
        if pts.count < 2 { pts += course }
        if !groups.isEmpty || loc.fix != nil { fitted = true }
        region(pts)
    }
    private func region(_ pts: [GeoPoint]) {
        guard !pts.isEmpty else { return }
        let lats = pts.map(\.lat), lngs = pts.map(\.lng)
        // a little extra at the bottom, where the sheet covers the map
        let dLat = max(0.0025, (lats.max()! - lats.min()!) * 1.6)
        let c = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2 - dLat * 0.12, longitude: (lngs.min()! + lngs.max()!) / 2)
        withAnimation(.easeInOut(duration: 0.45)) {
            camera = .region(MKCoordinateRegion(center: c, span: MKCoordinateSpan(latitudeDelta: dLat, longitudeDelta: max(0.0025, (lngs.max()! - lngs.min()!) * 1.4))))
        }
    }
    private func focus(_ g: GroupSpot) {
        if picked != g.team { sentMsg = nil }
        picked = g.team; follow = false
        withAnimation(.snappy(duration: 0.25)) { expanded = false }
        withAnimation(.easeInOut(duration: 0.45)) { camera = .camera(MapCamera(centerCoordinate: g.at.coordinate, distance: 420)) }
    }
    private func showHole(_ n: Int) {
        picked = nil; follow = false
        withAnimation(.snappy(duration: 0.25)) { expanded = false }
        let h = state.map.holes[n]
        region(groups.filter { $0.hole == n }.map(\.at) + [h?.tee, h.flatMap(Geo.middle)].compactMap { $0 })
    }

    private func shortName(_ n: String) -> String { n.components(separatedBy: " / ").first ?? n }
    private func yards(_ y: Double) -> String { y >= 1000 ? String(format: "%.1f mi", y / 1760) : "\(Int((y / 5).rounded()) * 5) yds" }
    private func ago(_ t: Date) -> String {
        let m = Int((serverNow.timeIntervalSince(t) / 60).rounded())
        return m < 1 ? "Just now" : "\(m) min ago"
    }
}

/// A group on the map: the hole it's on in a circle, its name in a tag (yours in the club's colour).
struct GroupPin: View {
    var group: GroupSpot
    var old = false
    var picked = false
    var body: some View {
        HStack(spacing: 0) {
            Text(group.hole > 0 ? "\(group.hole)" : "?").font(.system(size: 12, weight: .bold, design: .monospaced))
                .frame(width: 30, height: 30)
                .background(group.me ? Color.fcFlag : old ? Color(UIColor(hex: 0x8a948d)) : Color(UIColor(hex: 0x3a8bff)), in: Circle())
                .foregroundStyle(group.me ? Color.fcOnFlag : .white)
                .overlay(Circle().stroke(.white, lineWidth: 2.5))
                .background(Circle().fill(.white.opacity(picked ? 0.5 : 0)).frame(width: 40, height: 40))
                .zIndex(1)
            Text(group.me ? "Your group" : (group.name.components(separatedBy: " / ").first ?? group.name))
                .font(.system(size: 11.5, weight: group.me ? .bold : .semibold))
                .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 3)
                .background(group.me ? Color.fcFlag : Color(red: 8 / 255, green: 20 / 255, blue: 14 / 255).opacity(0.88),
                            in: UnevenRoundedRectangle(bottomTrailingRadius: 10, topTrailingRadius: 10))
                .foregroundStyle(group.me ? Color.fcOnFlag : .white)
                .padding(.leading, -8)
        }
        .opacity(old ? 0.6 : 1)
        .offset(x: -15)
        .shadow(color: .black.opacity(0.55), radius: 3, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(group.me ? "Your group, hole \(group.hole)" : "\(group.name), hole \(group.hole)")
    }
}

/// Ready-made notes as buttons that wrap onto as many lines as they need.
struct FlowChips: View {
    var items: [String]
    var disabled = false
    var tap: (Int) -> Void
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { k, t in
                Button { tap(k) } label: {
                    Text(t).font(.footnote.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.fcPaper, in: Capsule()).overlay(Capsule().stroke(Color.fcLine))
                }
                .buttonStyle(.plain).disabled(disabled)
            }
        }
    }
}
