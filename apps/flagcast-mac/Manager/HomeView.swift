import SwiftUI

/// Home: sign in, the club, make a tournament, add one by its desk link, and the club's people.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var code = ""
    @State private var sent = false
    @State private var useCode = false
    @State private var password = ""
    @State private var busy = false
    @State private var err: String?
    @State private var newName = ""
    @State private var newErr: String?
    @State private var link = ""
    @State private var addErr: String?
    @State private var req = ClubRequest()
    @State private var reqErr: String?
    @State private var invite = ""
    @State private var inviteErr: String?
    @FocusState private var focus: Field?
    @State private var picture: CoursePicture?
    enum Field { case email, code, password, new, add }

    var body: some View {
        PhotoPage(image: picture?.image, height: 290, section: "Home", titleHeight: 186) {
            if model.signedIn { Button("Sign out") { Task { await model.signOut() } }.buttonStyle(GlassButton()) }
            Button { focus = .new } label: { Label("New tournament", systemImage: "plus") }.buttonStyle(WhiteButton()).disabled(!(model.me?.club?.canMake ?? false))
        } title: {
            HeroTitle(kicker: model.me?.club.map { $0.stateLine } ?? "Flagcast Manager", title: model.me?.club?.name ?? "Welcome to Flagcast", size: 64,
                      sub: model.me?.email ?? "Sign in with your club email to see your tournaments.")
        } content: {
            CardForm {
            if !model.signedIn || model.me == nil { signIn }
            else if let club = model.me?.club { clubSection(club) }
            else { requestClub }
            SwiftUI.Section {
                HStack {
                    TextField("Desk link", text: $link, prompt: Text("https://flagcast.app/g/…/desk#…")).focused($focus, equals: .add)
                        .onSubmit(add)
                    Button("Add", action: add).disabled(link.isEmpty)
                }
                if let addErr { Text(addErr).foregroundStyle(.red).font(.callout) }
            } header: { Text("Add a tournament you already have") } footer: { Text("Paste its desk link. It ends in a long key after a # sign.").foregroundStyle(.secondary) }
        }
            }
        .task { await model.loadConfig() }
        .onChange(of: model.focusNew) { _, on in if on { focus = .new; model.focusNew = false } }
        .onChange(of: model.focusAdd) { _, on in if on { focus = .add; model.focusAdd = false } }
        .onAppear { if model.focusNew { focus = .new; model.focusNew = false } }
        .task(id: model.events.first?.id) {
            // the photo: the course of the club's first tournament
            guard let e = model.events.first, let d = model.doc(e.id) else { return }
            if !d.loaded { await d.load() }
            d.picture.load(d.ev, id: d.id); picture = d.picture
        }
    }

    @ViewBuilder private var signIn: some View {
        SwiftUI.Section {
            if model.googleOn { GoogleSignInButton(height: 40, token: { t in run { await model.use(token: t) } }, failed: { err = $0 }) }
            if !useCode {
                TextField("Email", text: $email, prompt: Text("you@yourclub.com")).textContentType(.username).focused($focus, equals: .email).onSubmit { focus = .password }
                SecureField("Password", text: $password).textContentType(.password).focused($focus, equals: .password).onSubmit(login)
                HStack {
                    Button("Email Me a Code Instead") { useCode = true; err = nil }.buttonStyle(.link)
                    Spacer()
                    Button("Sign In", action: login).buttonStyle(.borderedProminent).disabled(email.isEmpty || password.isEmpty || busy)
                }
            } else if !sent {
                TextField("Email", text: $email, prompt: Text("you@yourclub.com")).textContentType(.emailAddress).focused($focus, equals: .email).onSubmit(start)
                HStack { Button("Use a Password") { useCode = false; err = nil }.buttonStyle(.link); Spacer(); Button("Email Me a Code", action: start).buttonStyle(.borderedProminent).disabled(email.isEmpty || busy) }
            } else {
                Text("We sent a 6-digit code to \(email). It works for 15 minutes.").foregroundStyle(.secondary)
                TextField("Code", text: $code, prompt: Text("123456")).font(.title3.monospaced()).focused($focus, equals: .code).onSubmit(verify)
                HStack { Button("Use a Different Email") { sent = false; code = "" }; Spacer(); Button("Sign In", action: verify).buttonStyle(.borderedProminent).disabled(code.count < 6 || busy) }
            }
            if let err { Text(err).foregroundStyle(.red).font(.callout) }
        } header: { Text("Sign in") } footer: {
            Text("Your email and password\(model.googleOn ? ", or Google" : ""). First time? Use “Email Me a Code”, then set a password in Settings. Flagcast staff get Admin when they sign in.").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var requestClub: some View {
        SwiftUI.Section {
            TextField("Club name", text: $req.name, prompt: Text("Willow Creek Country Club"))
            TextField("Your name", text: $req.contact)
            TextField("Phone", text: $req.phone)
            TextField("Town and state", text: $req.city, prompt: Text("Rye, NY"))
            HStack { Spacer(); Button("Send to Flagcast") { Task { do { try await model.club("request", ["name": req.name, "contact": req.contact, "phone": req.phone, "city": req.city]); await model.refresh() } catch { reqErr = error.localizedDescription } } }.buttonStyle(.borderedProminent).disabled(req.name.isEmpty) }
            if let reqErr { Text(reqErr).foregroundStyle(.red).font(.callout) }
        } header: { Text("Set up your club") } footer: { Text("Flagcast approves it and emails you.").foregroundStyle(.secondary) }
    }

    @ViewBuilder private func clubSection(_ club: ClubMe.Club) -> some View {
        SwiftUI.Section {
            LabeledContent("Club") { HStack { Text(club.name); StatusPill(text: club.status == "active" ? "Active" : club.status == "pending" ? "Waiting" : "Off", warn: club.status == "off") } }
            LabeledContent("Tournaments", value: club.stateLine)
            LabeledContent("Signed in as", value: model.me?.email ?? "")
        }
        if club.canMake {
            SwiftUI.Section("New tournament") {
                HStack {
                    TextField("Name", text: $newName, prompt: Text("Member-Guest 2027")).focused($focus, equals: .new).onSubmit(make)
                    Button("Make Tournament", action: make).buttonStyle(.borderedProminent).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let newErr { Text(newErr).foregroundStyle(.red).font(.callout) }
            }
        }
        SwiftUI.Section {
            ForEach(model.me?.members ?? [], id: \.self) { m in
                HStack {
                    Text(m.email); if m.role == "owner" { Text("owner").foregroundStyle(.secondary) }
                    Spacer()
                    if model.me?.isOwner == true && m.role != "owner" {
                        Button("Remove", role: .destructive) { Task { do { try await model.club("uninvite", ["email": m.email]); await model.refresh() } catch { inviteErr = error.localizedDescription } } }.buttonStyle(.borderless)
                    }
                }
            }
            if model.me?.isOwner == true {
                HStack {
                    TextField("Add someone", text: $invite, prompt: Text("name@yourclub.com"))
                    Button("Add") { Task { do { try await model.club("invite", ["email": invite]); invite = ""; await model.refresh() } catch { inviteErr = error.localizedDescription } } }.disabled(invite.isEmpty)
                }
            }
            if let inviteErr { Text(inviteErr).foregroundStyle(.red).font(.callout) }
        } header: { Text("People who can run your club’s tournaments") }
    }

    private func run(_ f: @escaping () async throws -> Void) { busy = true; err = nil; Task { defer { busy = false }; do { try await f() } catch { err = error.localizedDescription } } }
    private func login() { run { try await model.login(email.trimmingCharacters(in: .whitespaces), password); password = "" } }
    private func start() { busy = true; err = nil; Task { defer { busy = false }; do { let dev = try await model.startSignIn(email.trimmingCharacters(in: .whitespaces)); sent = true; code = dev ?? ""; focus = .code } catch { err = error.localizedDescription } } }
    private func verify() { busy = true; err = nil; Task { defer { busy = false }; do { try await model.verify(email.trimmingCharacters(in: .whitespaces), code); sent = false; code = "" } catch { err = error.localizedDescription } } }
    private func make() { newErr = nil; Task { do { try await model.create(newName.trimmingCharacters(in: .whitespaces)); newName = "" } catch { newErr = error.localizedDescription } } }
    private func add() { addErr = nil; Task { do { try await model.add(link: link); link = "" } catch { addErr = error.localizedDescription } } }
}

struct ClubRequest { var name = ""; var contact = ""; var phone = ""; var city = "" }

struct StatusPill: View {
    var text: String, warn = false
    var body: some View {
        Text(text.uppercased()).font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2)
            .background(warn ? Color.red : Color.fcFlag, in: RoundedRectangle(cornerRadius: 4)).foregroundStyle(warn ? .white : .black)
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("updates.auto") private var autoCheck = true
    var body: some View {
        TabView {
            Form {
                LabeledContent("Signed in as", value: model.me?.email ?? "Not signed in")
                if let c = model.me?.club { LabeledContent("Club", value: c.name) }
                if model.signedIn {
                    PasswordSetter()
                    Button("Sign Out") { Task { await model.signOut() } }
                }
            }
            .formStyle(.grouped).tabItem { Label("Account", systemImage: "person.crop.circle") }
            AdminPassSettings()
                .formStyle(.grouped).tabItem { Label("Admin", systemImage: "key") }
            Form {
                Toggle("Show engineering tools", isOn: Binding(get: { model.showEngineering }, set: { model.showEngineering = $0 }))
                Text(model.isAdmin ? "You’re signed in as a Flagcast admin, so Engineering is always on." : "Adds Engineering to the Screens page: every TV in one table, routing several at once, scenes and take-overs. Club staff don’t need it.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .formStyle(.grouped).tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
            Form {
                Toggle("Check for updates when Flagcast Manager opens", isOn: $autoCheck)
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                Button("Check for Updates Now") { Updates.shared.check() }
            }
            .formStyle(.grouped).tabItem { Label("Updates", systemImage: "arrow.down.circle") }
        }
        .frame(width: 500, height: 360)
    }
}

/// Settings → Admin: the Flagcast Admin passcode. It opens the Admin section without an email sign-in.
struct AdminPassSettings: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var busy = false
    @State private var message: String?
    var body: some View {
        Form {
            SwiftUI.Section {
                if !(model.admin.pass ?? "").isEmpty {
                    LabeledContent("Flagcast Admin", value: "Unlocked on this Mac")
                    Button("Forget the Passcode") { model.admin.forget(); if model.adminSection != nil && !model.isAdmin { model.adminSection = nil }; message = nil }
                } else {
                    SecureField("Admin passcode", text: $text).onSubmit(unlock)
                    HStack {
                        Button("Unlock Admin", action: unlock).disabled(text.isEmpty || busy)
                        if busy { ProgressView().controlSize(.small) }
                    }
                }
            } footer: {
                Text(message ?? "The passcode is kept in your Keychain. Admin shows in the sidebar.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }
    private func unlock() {
        guard !text.isEmpty else { return }
        busy = true; message = nil
        Task {
            do { try await model.admin.unlock(text); text = ""; model.adminSection = .clubs; message = "Admin is unlocked." }
            catch { message = error.localizedDescription }
            busy = false
        }
    }
}

/// Settings → Account: set or change the password (then sign in with email + password on any device).
struct PasswordSetter: View {
    @Environment(AppModel.self) private var model
    @State private var pass = ""
    @State private var again = ""
    @State private var msg: String?
    @State private var busy = false
    var body: some View {
        SecureField(model.me?.password == true ? "New password" : "Set a password", text: $pass).textContentType(.newPassword)
        SecureField("Type it again", text: $again).textContentType(.newPassword)
        HStack {
            if let msg { Text(msg).font(.callout).foregroundStyle(.secondary) }
            Spacer()
            Button(model.me?.password == true ? "Change Password" : "Set Password") {
                guard pass == again else { msg = "The two don’t match."; return }
                busy = true
                Task { do { try await model.setPassword(pass); pass = ""; again = ""; msg = "Saved. Sign in with your email and this password." } catch { msg = error.localizedDescription }; busy = false }
            }
            .disabled(pass.count < 10 || busy)
        }
        Text("At least 10 characters.").font(.caption).foregroundStyle(.secondary)
    }
}
