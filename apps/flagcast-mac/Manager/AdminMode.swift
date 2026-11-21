import SwiftUI

// Admin mode (Flagcast staff only, design MacAdminMode): its own dark red sidebar with Overview, Sign-ups, Clubs,
// Tournaments, Cameras, Screens & phones and Activity. Switched with the Manager | Admin control at the top of either
// sidebar, or ⌥⌘A.

extension FC {
    static let adminRed = Color(hex: 0x2a1416), adminRed2 = Color(hex: 0x3a1c1f), onAdmin = Color(hex: 0xf3e7e5), onAdminMuted = Color(hex: 0xc9a9a6)
}

/// Manager | Admin, at the top of the sidebar (admins only).
struct ModeSwitch: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: 2) {
            seg("Manager", on: !model.adminMode) { model.adminMode = false }
            seg("Admin", on: model.adminMode) { model.adminMode = true }
        }
        .padding(2).background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .help("Switch between your club and Flagcast Admin (⌥⌘A)")
    }
    private func seg(_ t: String, on: Bool, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 26)
                .foregroundStyle(on ? (model.adminMode ? FC.adminRed : FC.green) : Color.white.opacity(0.8))
                .background(on ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 6)).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct AdminSidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(AdminModel.self) private var admin
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Color.clear.frame(height: 26).contentShape(Rectangle()).gesture(WindowDragGesture())
            ModeSwitch()
            HStack(spacing: 10) {
                FlagcastMark(size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("FLAGCAST").font(FC.display(22)).tracking(0.5)
                    Text("ADMIN").font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2).background(FC.red, in: RoundedRectangle(cornerRadius: 3))
                }
            }
            .padding(.horizontal, 6)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(AdminSection.allCases) { a in
                    let on = (model.adminSection ?? .overview) == a
                    Button { model.adminSection = a } label: {
                        HStack(spacing: 10) {
                            Image(systemName: a.icon).font(.system(size: 13)).frame(width: 18).foregroundStyle(on ? FC.adminRed : FC.onAdminMuted)
                            Text(a.title).font(.system(size: 13, weight: on ? .semibold : .medium))
                            Spacer()
                            if a == .signups, pending > 0 {
                                Text("\(pending)").font(.system(size: 11, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(FC.flag, in: Capsule()).foregroundStyle(FC.onFlag)
                            }
                        }
                        .foregroundStyle(on ? FC.adminRed : FC.onAdmin)
                        .padding(.horizontal, 8).padding(.vertical, 7)
                        .background(on ? FC.onAdmin : .clear, in: RoundedRectangle(cornerRadius: 7)).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            Divider().overlay(Color.white.opacity(0.14))
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 22)).foregroundStyle(FC.onAdminMuted)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.me?.email ?? "Admin passcode").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text("Flagcast staff").font(.system(size: 11)).foregroundStyle(FC.onAdminMuted)
                }
                Spacer()
                SettingsLink { Image(systemName: "gearshape").foregroundStyle(FC.onAdminMuted) }.buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 12)
        .foregroundStyle(FC.onAdmin)
        .background(FC.adminRed)
        .environment(\.colorScheme, .dark)
    }
    private var pending: Int { admin.clubs.filter { $0.status == "pending" }.count }
}

/// A page in Admin: big title on paper, a line under it, the page's buttons, then the content.
struct AdminScaffold<Actions: View, Content: View>: View {
    var title: String
    var sub: String
    @ViewBuilder var actions: Actions
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(FC.display(44))
                        Text(sub).font(.system(size: 14)).foregroundStyle(FC.muted)
                    }
                    Spacer()
                    actions
                }
                .padding(.top, 40)
                content
            }
            .padding(.horizontal, 28).padding(.bottom, 28)
        }
        .background(FC.paper)
    }
}

// MARK: - Overview

struct AdminOverview: View {
    @Environment(AdminModel.self) private var admin
    @Environment(AppModel.self) private var model
    @State private var looking: AdminClub?

    private var pending: [AdminClub] { admin.clubs.filter { $0.status == "pending" } }
    private var open: [AdminEvent] { admin.events.filter { !$0.gone && !$0.archived && !$0.hidden } }
    private var liveNow: [AdminEvent] { open.filter { $0.isToday && !$0.locked } }
    private var screensOn: Int { open.reduce(0) { $0 + $1.online } }
    private var screensAll: Int { liveNow.reduce(0) { $0 + $1.screens } }

    var body: some View {
        AdminScaffold(title: "Overview", sub: Date().formatted(date: .complete, time: .omitted)) {
            Button { Task { try? await admin.refresh(); await admin.refreshEvents(); await admin.refreshLog() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(PlainCardButton())
        } content: {
            ForEach(pending) { c in signup(c) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                stat("Clubs", "\(admin.clubs.count)", "\(admin.clubs.filter { $0.status == "active" }.count) active")
                stat("Tournaments live", "\(liveNow.count)", "\(open.count) open in all")
                if screensAll > 0 || screensOn > 0 { stat("Screens online", "\(screensOn)", screensAll > 0 ? "of \(screensAll) at today’s events" : "right now") }
                let scored = liveNow.reduce(0) { $0 + $1.scored }
                if scored > 0 { stat("Scores today", "\(scored)", "holes entered from the carts") }
            }
            if !liveNow.isEmpty {
                CardTitle("Live now")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                    ForEach(liveNow) { e in liveCard(e) }
                }
            }
            let offline = liveNow.flatMap { e in e.displays.filter { $0.online == 0 }.map { (e, $0) } }
            let empty = admin.clubs.filter { $0.status == "active" && $0.credits == 0 }
            if !offline.isEmpty || !empty.isEmpty {
                CardTitle("Needs a look")
                VStack(spacing: 0) {
                    ForEach(Array(offline.prefix(8).enumerated()), id: \.offset) { _, p in
                        row("tv.slash", FC.red, "\(p.1.name.isEmpty ? "A TV" : p.1.name) is off", "\(p.0.name) · \(p.0.clubName)") { model.adminSection = .screens }
                    }
                    ForEach(empty) { c in
                        row("exclamationmark.circle", FC.flag, "\(c.name) has no tournaments left", c.city.isEmpty ? "Add more on the club’s page" : c.city) { model.adminSection = .clubs }
                    }
                }
                .raisedCard()
            }
            if !admin.log.isEmpty {
                CardTitle("Activity")
                VStack(spacing: 0) {
                    ForEach(admin.log.prefix(8)) { l in
                        HStack(alignment: .firstTextBaseline) {
                            Text(l.what).font(.system(size: 13)).lineLimit(1)
                            Spacer()
                            Text(Date(timeIntervalSince1970: l.at / 1000).formatted(.relative(presentation: .named))).font(.system(size: 12)).foregroundStyle(FC.muted)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        Divider().overlay(FC.hairline)
                    }
                    Button("All activity ›") { model.adminSection = .activity }.buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(FC.link).padding(12)
                }
                .raisedCard()
            }
        }
        .task { await admin.refreshLog() }
        .sheet(item: $looking) { c in
            VStack(spacing: 0) {
                HStack { Text(c.name).font(FC.display(30)); Spacer(); Button("Done") { looking = nil }.buttonStyle(GreenButton()).keyboardShortcut(.defaultAction) }.padding(16)
                ClubInspector(club: admin.clubs.first { $0.id == c.id } ?? c).id(c.id)
            }
            .frame(width: 560, height: 700).background(FC.card)
        }
    }

    private func signup(_ c: AdminClub) -> some View {
        HStack(spacing: 16) {
            Text("NEEDS YOU").font(.system(size: 10, weight: .bold)).tracking(1).padding(.horizontal, 6).padding(.vertical, 3).background(FC.flag, in: RoundedRectangle(cornerRadius: 4)).foregroundStyle(FC.onFlag)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(c.name) asked to join").font(.system(size: 15, weight: .bold)).foregroundStyle(Color(hex: 0x14201a))
                Text(["Signed up \(Date(timeIntervalSince1970: c.created / 1000).formatted(.relative(presentation: .named)))", c.city.isEmpty ? nil : c.city, c.by.isEmpty ? nil : c.by].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 13)).foregroundStyle(Color(hex: 0x56625a))
            }
            Spacer()
            Button("Look First") { looking = c }.buttonStyle(PlainCardButton())
            Button("Decline") { Task { await admin.act("off", ["club": c.id], done: "Declined.") } }.buttonStyle(PlainCardButton())
            Button("Approve") { Task { await admin.act("approve", ["club": c.id], done: "Approved. They have an email.") } }.buttonStyle(GreenButton())
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color(hex: 0xfff8e1), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xecd58a)))
    }
    private func stat(_ label: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(FC.muted)
            Text(value).font(FC.display(38))
            Text(sub).font(.system(size: 12)).foregroundStyle(FC.muted).lineLimit(1)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).raisedCard()
    }
    private func liveCard(_ e: AdminEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { LiveChip(); Text(e.clubName.uppercased()).font(.system(size: 11, weight: .bold)).tracking(1).foregroundStyle(FC.muted); Spacer() }
            Text(e.name).font(FC.display(28)).lineLimit(1)
            Text(["\(e.teams) teams", "\(e.scored) scores in", e.screens > 0 ? "\(e.online) of \(e.screens) screens on" : nil].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 13)).foregroundStyle(FC.muted)
            HStack {
                Button("Open") { model.openAdmin(id: e.id, key: e.key, name: e.name, date: e.date, club: e.clubName) }.buttonStyle(GreenButton())
                Button("Screens") { model.adminSection = .screens }.buttonStyle(PlainCardButton())
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).raisedCard()
    }
    private func row(_ icon: String, _ color: Color, _ title: String, _ sub: String, _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(color).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) { Text(title).font(.system(size: 14, weight: .semibold)); Text(sub).font(.system(size: 12)).foregroundStyle(FC.muted) }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(FC.muted)
            }
            .padding(.horizontal, 16).padding(.vertical, 10).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sign-ups

struct SignupsView: View {
    @Environment(AdminModel.self) private var admin
    @State private var looking: AdminClub?
    private var pending: [AdminClub] { admin.clubs.filter { $0.status == "pending" }.sorted { $0.created > $1.created } }
    var body: some View {
        AdminScaffold(title: "Sign-ups", sub: pending.isEmpty ? "Nobody is waiting" : "\(pending.count) club\(pending.count == 1 ? "" : "s") waiting for you") { EmptyView() } content: {
            if pending.isEmpty {
                VStack(spacing: 8) { Image(systemName: "checkmark.circle").font(.system(size: 34)).foregroundStyle(FC.ok); Text("All caught up").font(.headline) }
                    .frame(maxWidth: .infinity, minHeight: 220).raisedCard()
            }
            ForEach(pending) { c in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(c.name).font(FC.display(30))
                        Spacer()
                        Text(Date(timeIntervalSince1970: c.created / 1000).formatted(.relative(presentation: .named))).font(.system(size: 12)).foregroundStyle(FC.muted)
                    }
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                        if !c.contact.isEmpty { GridRow { Text("Contact").foregroundStyle(FC.muted); Text(c.contact) } }
                        if !c.by.isEmpty { GridRow { Text("Email").foregroundStyle(FC.muted); Text(c.by).textSelection(.enabled) } }
                        if !c.phone.isEmpty { GridRow { Text("Phone").foregroundStyle(FC.muted); Text(c.phone).textSelection(.enabled) } }
                        if !c.city.isEmpty { GridRow { Text("Town").foregroundStyle(FC.muted); Text(c.city) } }
                    }
                    .font(.system(size: 13))
                    HStack {
                        Spacer()
                        Button("Look First") { looking = c }.buttonStyle(PlainCardButton())
                        Button("Decline") { Task { await admin.act("off", ["club": c.id], done: "Declined.") } }.buttonStyle(PlainCardButton())
                        Button("Approve") { Task { await admin.act("approve", ["club": c.id], done: "Approved. They have an email.") } }.buttonStyle(GreenButton())
                    }
                }
                .padding(18).raisedCard()
            }
        }
        .sheet(item: $looking) { c in
            VStack(spacing: 0) {
                HStack { Text(c.name).font(FC.display(30)); Spacer(); Button("Done") { looking = nil }.buttonStyle(GreenButton()).keyboardShortcut(.defaultAction) }.padding(16)
                ClubInspector(club: admin.clubs.first { $0.id == c.id } ?? c).id(c.id)
            }
            .frame(width: 560, height: 700).background(FC.card)
        }
    }
}

// MARK: - Cameras

/// Every open tournament's par 3s with a camera link per hole. Only Flagcast sets these; clubs pick "Par 3 camera"
/// for a TV and see the status.
struct CamerasView: View {
    @Environment(AdminModel.self) private var admin
    @State private var search = ""
    private var shown: [AdminEvent] {
        let q = search.lowercased()
        return admin.events.filter { !$0.gone && !$0.archived && !$0.hidden && !$0.p3.isEmpty && (q.isEmpty || $0.name.lowercased().contains(q) || $0.clubName.lowercased().contains(q)) }
            .sorted { ($0.isToday ? 0 : 1, $1.created) < ($1.isToday ? 0 : 1, $0.created) }
    }
    var body: some View {
        AdminScaffold(title: "Cameras", sub: "Par 3 camera links for every club’s tournament") {
            TextField("Find a tournament or club", text: $search).textFieldStyle(.roundedBorder).frame(width: 240)
        } content: {
            Help("Paste each par 3’s https link: an HLS stream (.m3u8) or a web player link such as a VDO.Ninja view link. Replays from the live feed need an HLS link that keeps a recording window (DVR); a web player link plays live only. Clubs see “Cameras are set up by Flagcast”.")
            if shown.isEmpty { Text(admin.events.isEmpty ? "Loading tournaments…" : "No open tournaments with par 3s.").foregroundStyle(FC.muted).frame(maxWidth: .infinity, minHeight: 160).raisedCard() }
            ForEach(shown) { e in CameraCard(event: e).id(e.id + e.cams.description) }
        }
    }
}

private struct CameraCard: View {
    @Environment(AdminModel.self) private var admin
    let event: AdminEvent
    @State private var links: [Int: String] = [:]
    @State private var useNDI: [Int: Bool] = [:]
    @State private var picked: [Int: String] = [:]
    @State private var signal: [Int: Bool] = [:]
    @State private var cloud: [Int: String]?
    @State private var cloudProblem: String?
    @State private var saving = false
    private var bridges: Bridges { Bridges.shared }
    private var sources: NDISources { NDISources.shared }
    private var changed: Bool { links.filter { !$0.value.isEmpty } != event.cams }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                if event.isToday && !event.locked { LiveChip() }
                Text(event.name).font(FC.display(26))
                Text("\(event.clubName)\(event.date.isEmpty ? "" : " · \(event.date)")").font(.system(size: 13)).foregroundStyle(FC.muted)
                Spacer()
                Button { Task { saving = true; if await admin.saveCams(event.id, links) { await check() }; saving = false } } label: { saving ? AnyView(ProgressView().controlSize(.small)) : AnyView(Text("Save Links")) }
                    .buttonStyle(GreenButton()).disabled(!changed || saving)
            }
            ForEach(event.p3, id: \.self) { h in holeRow(h) }
            if event.p3.contains(where: { useNDI[$0] == true }) {
                VStack(alignment: .leading, spacing: 4) {
                    if let tv = Bridges.tvURL(event.id) {
                        HStack {
                            Text("Clubhouse TVs on this network: open ").font(.system(size: 12)).foregroundStyle(FC.muted) + Text(tv).font(.system(size: 12, weight: .semibold).monospaced())
                            Button("Copy") { copy(tv) }.buttonStyle(.link).font(.system(size: 12))
                        }
                    }
                    Text(cloud == nil ? "Phones and replays: \(cloudProblem ?? "Cloudflare Stream isn’t set up yet, so NDI cameras show on the clubhouse TVs only.")" : "Phones and replays get it through Cloudflare Stream.")
                        .font(.system(size: 12)).foregroundStyle(FC.muted)
                    if let e = bridges.serverError { Text(e).font(.system(size: 12)).foregroundStyle(FC.red) }
                    Text(NDI_NOTICE).font(.system(size: 10)).foregroundStyle(FC.muted)
                }
            }
        }
        .padding(18).raisedCard()
        .task(id: event.id) {
            links = event.cams
            for h in event.p3 { if let src = UserDefaults.standard.string(forKey: "ndi.\(event.id)-\(h)") { useNDI[h] = true; picked[h] = src } }
            await check()
            while !Task.isCancelled { cloud = await admin.streamHealth(event.id); try? await Task.sleep(for: .seconds(10)) }
        }
    }

    @ViewBuilder private func holeRow(_ h: Int) -> some View {
        let ndi = useNDI[h] ?? false, b = bridges.bridge(event.id, h)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("Hole \(h)").font(.system(size: 14, weight: .semibold)).frame(width: 64, alignment: .leading)
                Picker("", selection: Binding(get: { ndi }, set: { useNDI[h] = $0; if $0 { sources.watch() } })) { Text("Link").tag(false); Text("NDI® source").tag(true) }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                if !ndi {
                    TextField("https://… (.m3u8 or a web player link)", text: Binding(get: { links[h] ?? "" }, set: { links[h] = $0 })).textFieldStyle(.roundedBorder)
                    dot(h)
                } else if !sources.available {
                    Text("Install the NDI runtime (ndi.video) on this Mac to receive NDI cameras.").font(.system(size: 12)).foregroundStyle(FC.red)
                    Spacer()
                } else {
                    Picker("", selection: Binding(get: { picked[h] ?? "" }, set: { picked[h] = $0 })) {
                        Text(sources.names.isEmpty ? "Looking for NDI sources…" : "Pick a source").tag("")
                        ForEach(sources.names, id: \.self) { Text($0).tag($0) }
                        if let p = picked[h], !p.isEmpty, !sources.names.contains(p) { Text("\(p) (not seen now)").tag(p) }
                    }
                    .labelsHidden()
                    if b == nil {
                        Button("Start") { Task { await start(h) } }.buttonStyle(GreenButton()).disabled((picked[h] ?? "").isEmpty)
                    } else {
                        Button("Stop") { bridges.stop(event: event.id, hole: h) }.buttonStyle(PlainCardButton())
                    }
                }
            }
            if ndi, let b {
                HStack(spacing: 14) {
                    Label(b.receiving ? "Live \(b.size)" : b.state, systemImage: "circle.fill").foregroundStyle(b.receiving ? FC.ok : FC.red)
                    Label(Bridges.tvURL(event.id) == nil ? "No club network" : "Clubhouse TVs", systemImage: "tv").foregroundStyle(b.receiving ? FC.ok : FC.muted)
                    if let up = b.uploading {
                        let c = cloud?[h]
                        Label(c == "connected" ? "Cloudflare: receiving" : up ? "Sending to Cloudflare" : "Cloudflare: not sending", systemImage: "icloud.and.arrow.up")
                            .foregroundStyle(c == "connected" ? FC.ok : up ? FC.flag : FC.red)
                    } else {
                        Label("TVs only (no Cloudflare Stream)", systemImage: "icloud.slash").foregroundStyle(FC.muted)
                    }
                }
                .font(.system(size: 12, weight: .semibold)).padding(.leading, 74)
            }
        }
    }
    private func start(_ h: Int) async {
        guard let src = picked[h], !src.isEmpty else { return }
        let target = await admin.streamTarget(event.id, h)
        cloudProblem = target.problem
        bridges.start(event: event.id, hole: h, source: src, rtmps: target.push)
        if target.push != nil { await admin.refreshEvents() }
    }
    @ViewBuilder private func dot(_ h: Int) -> some View {
        let url = event.cams[h] ?? ""
        if url.isEmpty { Text("No camera").font(.system(size: 12)).foregroundStyle(FC.muted).frame(width: 96, alignment: .leading) }
        else if !url.lowercased().contains(".m3u8") { Label("Web player", systemImage: "circle.dashed").font(.system(size: 12)).foregroundStyle(FC.muted).frame(width: 96, alignment: .leading).help("Can’t be checked from here: open it to see") }
        else if let ok = signal[h] { Label(ok ? "Live" : "No signal", systemImage: "circle.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(ok ? FC.ok : FC.red).frame(width: 96, alignment: .leading) }
        else { ProgressView().controlSize(.small).frame(width: 96, alignment: .leading) }
    }
    /// HLS links: fetch the playlist (cheap) to see whether the camera is sending.
    private func check() async {
        for (h, u) in event.cams where u.lowercased().contains(".m3u8") {
            guard let url = URL(string: u) else { continue }
            var req = URLRequest(url: url); req.timeoutInterval = 6
            let ok = await ((try? URLSession.shared.data(for: req)).map { d, r in (r as? HTTPURLResponse)?.statusCode == 200 && String(decoding: d.prefix(64), as: UTF8.self).contains("#EXTM3U") }) ?? false
            signal[h] = ok
        }
    }
}
