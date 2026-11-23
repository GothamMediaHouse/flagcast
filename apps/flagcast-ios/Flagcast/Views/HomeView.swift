import SwiftUI

/// The app's home: scan the cart card (or type the codes), go back into a recent tournament, or sign in as a
/// golf pro or marshal. Matches public/golf/app/.
struct HomeView: View {
    @Environment(Router.self) private var router
    @State private var eventCode = ""
    @State private var cartCode = ""
    @State private var joinError: String?
    @State private var joining = false
    @State private var proEvent = ""
    @State private var pin = ""
    @State private var proError: String?
    @State private var signingIn = false
    @State private var scanning = false
    @State private var recents: [Recent] = []
    @State private var pros: [ProSignIn] = []
    @State private var serverSheet = false
    @State private var settings = false
    @State private var typing = false
    @State private var proOpen = false
    @FocusState private var focus: Field?
    enum Field { case event, cart, proEvent, pin }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                VStack(spacing: 14) {
                    playCard
                    if let r = recents.first(where: { !$0.code.isEmpty }) { resumeCard(r) }
                    if !others.isEmpty || !pros.isEmpty { recentCard }
                    proCard
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.top, -56)
                .padding(.bottom, 32)
                .frame(maxWidth: 520)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { VStack(spacing: 0) { Color.fcGreen.frame(height: 320); Color.fcPaper }.ignoresSafeArea() }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { recents = Recents.all(); pros = ProSignIns.all() }
        .sheet(isPresented: $scanning) {
            ScannerSheet { text in
                guard let r = Codes.route(text) else { return false }
                scanning = false
                router.go(r)
                return true
            }
        }
        .sheet(isPresented: $serverSheet) { ServerSheet() }
        .sheet(isPresented: $settings, onDismiss: { recents = Recents.all() }) { PlayerSettingsView() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { settings = true } label: { Image(systemName: "gearshape.fill") }.tint(.white).accessibilityLabel("Settings")
            }
            // the PIN pad has no return key: put the form's button above the keyboard
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                if focus == .proEvent || focus == .pin {
                    Button("Sign in") { Task { await signIn() } }.fontWeight(.semibold)
                } else {
                    Button("Open") { Task { await join() } }.fontWeight(.semibold)
                }
            }
        }
    }

    /// the tournament this phone last scored in goes in its own card; the rest are listed below it
    private var others: [Recent] {
        let first = recents.first { !$0.code.isEmpty }?.id
        return recents.filter { $0.id != first }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image("Logo").resizable().scaledToFit().frame(height: 28).accessibilityLabel("Flagcast")
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.caption.weight(.semibold)).tracking(1.4).textCase(.uppercase).foregroundStyle(Color.fcFlag).padding(.top, 14)
            Text("Your round,\nlive").font(FCType.display(52)).textCase(.uppercase).foregroundStyle(.white).lineSpacing(-6)
            Text("Score your cart, follow the leaderboard and watch the par 3s.")
                .font(.callout).foregroundStyle(Color.fcOnGreenMuted)
        }
        .padding(.top, 20).padding(.bottom, 84).padding(.horizontal, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fcGreen)
    }

    private var playCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "qrcode.viewfinder").font(.system(size: 26, weight: .semibold))
                    .frame(width: 54, height: 54).background(Color.fcFlag, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(Color.fcOnFlag)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Playing today?").font(.title3.weight(.bold))
                    Text("Scan the QR code on your cart card.").font(.subheadline).foregroundStyle(Color.fcMuted)
                }
            }
            Button { scanning = true } label: { Text("Scan cart card").font(.title3.weight(.semibold)) }
                .buttonStyle(.fcDark)
            if typing {
                HStack(alignment: .top, spacing: 10) {
                    codeField("Tournament code", "ABCD2345", $eventCode, 8, .event)
                    codeField("Cart code", "Optional", $cartCode, 6, .cart)
                }
                Button { Task { await join() } } label: { if joining { ProgressView() } else { Text("Open") } }
                    .buttonStyle(.fcPlain).disabled(joining)
                if let joinError { Text(joinError).font(.subheadline).foregroundStyle(Color.fcRed).accessibilityAddTraits(.isStaticText) }
            } else {
                Button("Type the codes instead") { withAnimation(.snappy) { typing = true }; focus = .event }
                    .font(.subheadline.weight(.semibold)).tint(Color.fcPrimary).frame(maxWidth: .infinity)
            }
        }
        .fcCard(padding: 18)
    }

    private func resumeCard(_ r: Recent) -> some View {
        let s = Cache.load(r.id)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Back to your round").fcLabel().padding(.horizontal, 4)
            Button { router.go(.score(id: r.id, code: r.code)) } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(r.name).font(.headline).foregroundStyle(Color.fcInk).lineLimit(2).multilineTextAlignment(.leading)
                        Text(["Cart \(r.code)", s?.course.name ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(Color.fcMuted).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.headline).foregroundStyle(Color.fcMuted)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) { Rectangle().fill(Color.fcFlag).frame(width: 5) }
                .fcCard(padding: 0)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .contextMenu { Button("Remove", systemImage: "trash", role: .destructive) { Recents.forget(r.id); recents = Recents.all() } }
        }
    }

    private var line: some View { Rectangle().fill(Color.fcLine).frame(height: 1) }

    private func codeField(_ label: String, _ placeholder: String, _ text: Binding<String>, _ max: Int, _ f: Field, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.footnote).foregroundStyle(Color.fcMuted)
            Group {
                if secure { SecureField(placeholder, text: text).keyboardType(.numberPad) }
                else { TextField(placeholder, text: text).textInputAutocapitalization(.characters) }
            }
            .font(.title3.monospaced().weight(.medium))
            .autocorrectionDisabled()
            .focused($focus, equals: f)
            .submitLabel(f == .event ? .next : .go)
            .onSubmit {
                switch f {
                case .event: focus = .cart
                case .cart: Task { await join() }
                case .proEvent: focus = .pin
                case .pin: Task { await signIn() }
                }
            }
            .onChange(of: text.wrappedValue) { _, v in if v.count > max { text.wrappedValue = String(v.prefix(max)) } }
            .padding(12)
            .background(Color.fcPaper, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.fcLine, lineWidth: 1.5))
            .accessibilityLabel(label)
        }
        .frame(maxWidth: .infinity)
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your tournaments").fcLabel()
            ForEach(pros) { p in
                recentRow(title: recents.first { $0.id == p.event }?.name ?? Cache.load(p.event)?.name ?? p.name,
                          detail: p.role == "pro" ? "Golf pro" : "Marshal", icon: "person.badge.key") { router.go(.pro(id: p.event)) }
                    .contextMenu { Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { ProSignIns.remove(p.id); pros = ProSignIns.all() } }
            }
            ForEach(others.prefix(6)) { r in
                recentRow(title: r.name, detail: r.code.isEmpty ? "Leaderboard" : "Cart \(r.code)", icon: r.code.isEmpty ? "list.number" : "flag") {
                    router.go(r.code.isEmpty ? .live(id: r.id) : .score(id: r.id, code: r.code))
                }
                .contextMenu { Button("Remove", systemImage: "trash", role: .destructive) { Recents.forget(r.id); recents = Recents.all() } }
            }
        }
        .fcCard(padding: 18)
    }

    private func recentRow(title: String, detail: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(Color.fcGreen2).frame(width: 24)
                Text(title).font(.body.weight(.semibold)).foregroundStyle(Color.fcInk).lineLimit(1)
                Spacer()
                Text(detail).fcLabel()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.fcMuted)
            }
            .padding(.horizontal, 12).frame(minHeight: 52)
            .background(Color.fcPaper, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.fcLine))
        }
        .buttonStyle(.plain)
    }

    private var proCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.snappy) { proOpen.toggle() } } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.badge.key.fill").font(.headline).foregroundStyle(Color.fcPrimary).frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Golf pro or marshal?").font(.body.weight(.semibold)).foregroundStyle(Color.fcInk)
                        Text("Sign in with the PIN the tournament desk gave you.").font(.footnote).foregroundStyle(Color.fcMuted)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: proOpen ? "chevron.up" : "chevron.down").font(.footnote.weight(.bold)).foregroundStyle(Color.fcMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if proOpen {
                HStack(alignment: .top, spacing: 10) {
                    codeField("Tournament code", "", $proEvent, 8, .proEvent)
                    codeField("PIN", "", $pin, 8, .pin, secure: true)
                }
                .padding(.top, 4)
                Button { Task { await signIn() } } label: { if signingIn { ProgressView().tint(Color.fcOnGreen) } else { Text("Sign in") } }
                    .buttonStyle(.fcDark).disabled(signingIn)
                if let proError { Text(proError).font(.subheadline).foregroundStyle(Color.fcRed) }
            }
        }
        .fcCard(padding: 16)
    }

    private var footer: some View {
        Link("flagcast.app", destination: Server.production)
            .font(.footnote).foregroundStyle(Color.fcMuted).padding(.top, 6)
            #if DEBUG
            .onLongPressGesture { serverSheet = true }
            #endif
    }

    private func join() async {
        joinError = nil
        guard let id = Codes.eventId(eventCode) else { joinError = "The tournament code is 8 letters and numbers."; return }
        let code = cartCode.trimmingCharacters(in: .whitespaces)
        if !code.isEmpty && Codes.cart(code) == nil { joinError = "The cart code is 6 letters and numbers."; return }
        joining = true; defer { joining = false }
        do {
            let s = try await API.state(id)
            Recents.remember(id: id, name: s.name, code: Codes.cart(code) ?? "")
            focus = nil
            router.go(code.isEmpty ? .live(id: id) : .score(id: id, code: Codes.cart(code)!))
        } catch let e as APIError where e.status == 404 {
            joinError = "We couldn’t find that tournament. Check the code on your cart card."
        } catch {
            joinError = (error as? APIError)?.message ?? "That didn’t work. Try again."
        }
    }

    private func signIn() async {
        proError = nil
        guard let id = Codes.eventId(proEvent) else { proError = "The tournament code is 8 letters and numbers."; return }
        let p = pin.trimmingCharacters(in: .whitespaces)
        signingIn = true; defer { signingIn = false }
        do {
            let r = try await API.post(id, "pro", ["pin": p, "op": "hello"])
            PinStore.save(p, for: id)
            ProSignIns.save(ProSignIn(id: id, event: id, name: (r["name"] as? String) ?? "Golf pro", role: (r["role"] as? String) ?? "pro"))
            pin = ""; focus = nil
            router.go(.pro(id: id))
        } catch {
            proError = (error as? APIError)?.message ?? "That didn’t work. Try again."
        }
    }
}

/// Debug builds only: point the app at a local copy of the site.
struct ServerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = UserDefaults.standard.string(forKey: Server.overrideKey) ?? ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://localhost:8787", text: $text).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Server") } footer: { Text("Empty uses \(Server.production.absoluteString). Debug builds only.") }
            }
            .navigationTitle("Server").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let t = text.trimmingCharacters(in: .whitespaces)
                        if t.isEmpty { UserDefaults.standard.removeObject(forKey: Server.overrideKey) } else { UserDefaults.standard.set(t, forKey: Server.overrideKey) }
                        dismiss()
                    }
                }
            }
        }
    }
}
