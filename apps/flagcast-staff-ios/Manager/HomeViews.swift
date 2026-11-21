import SwiftUI

/// Sign in with the club's email (a code comes by email), or with the Flagcast admin passcode.
struct SignInView: View {
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var code = ""
    @State private var sent = false
    @State private var busy = false
    @State private var message: String?
    @State private var passcode = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PhotoHeader(image: nil, kicker: "Flagcast", title: "Run your tournament", sub: "Teams, live scores and the TVs, from your phone.", height: 300)
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        CardTitle("Sign in")
                        if !sent {
                            TextField("Your club email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never).autocorrectionDisabled().padding(12).background(FC.paper2, in: RoundedRectangle(cornerRadius: 10))
                            Button { start() } label: { if busy { ProgressView().tint(.white) } else { Text("Email Me a Code") } }
                                .buttonStyle(GreenButton(full: true)).disabled(!email.contains("@") || busy)
                        } else {
                            Text("We sent a code to \(email).").font(.subheadline).foregroundStyle(FC.muted)
                            TextField("6-digit code", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode).font(FC.display(30))
                                .padding(12).background(FC.paper2, in: RoundedRectangle(cornerRadius: 10))
                            Button { verify() } label: { if busy { ProgressView().tint(.white) } else { Text("Sign In") } }
                                .buttonStyle(GreenButton(full: true)).disabled(code.count < 4 || busy)
                            Button("Use a different email") { sent = false; code = "" }.font(.subheadline).foregroundStyle(FC.link)
                        }
                        if let message { Text(message).font(.footnote).foregroundStyle(FC.red) }
                    }
                    .card()
                    Button("Flagcast admin? Use the admin passcode") { passcode = true }.font(.subheadline).foregroundStyle(FC.link).frame(maxWidth: .infinity)
                    NavigationLink("Have a desk link? Add a tournament without signing in") { AddByLinkView() }
                        .font(.subheadline).foregroundStyle(FC.link).frame(maxWidth: .infinity)
                }
                .padding(16).frame(maxWidth: 520)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(FC.paper)
        .sheet(isPresented: $passcode) { NavigationStack { AdminPasscodeView() } }
    }
    private func start() {
        busy = true; message = nil
        Task {
            do { let dev = try await model.startSignIn(email.trimmingCharacters(in: .whitespaces)); sent = true; if let dev { code = dev } }
            catch { message = error.localizedDescription }
            busy = false
        }
    }
    private func verify() {
        busy = true; message = nil
        Task {
            do { try await model.verify(email.trimmingCharacters(in: .whitespaces), code.trimmingCharacters(in: .whitespaces)) }
            catch { message = error.localizedDescription }
            busy = false
        }
    }
}

/// The Flagcast admin passcode: kept in the Keychain, unlocks the Admin tab without an email sign-in.
struct AdminPasscodeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var busy = false
    @State private var message: String?
    var body: some View {
        Form {
            if !(model.admin.pass ?? "").isEmpty {
                LabeledContent("Flagcast Admin", value: "Unlocked on this device")
                Button("Forget the Passcode", role: .destructive) { model.admin.forget() }
            } else {
                SwiftUI.Section {
                    SecureField("Admin passcode", text: $text).onSubmit(unlock)
                    Button { unlock() } label: { if busy { ProgressView() } else { Text("Unlock Admin") } }.disabled(text.isEmpty || busy)
                } footer: { Text(message ?? "The passcode is kept in this device’s Keychain. The Admin tab appears at the bottom.") }
            }
        }
        .navigationTitle("Admin passcode").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
    private func unlock() {
        busy = true; message = nil
        Task {
            do { try await model.admin.unlock(text); text = ""; dismiss() } catch { message = error.localizedDescription }
            busy = false
        }
    }
}

/// Every tournament this device knows: the club's, ones added by desk link, and ones opened from Admin.
/// Pick one to open it; make a new one; add one by its desk link.
struct TournamentPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var asSheet = false
    @State private var name = ""
    @State private var making = false
    @State private var message: String?

    var body: some View {
        List {
            if let c = model.me?.club {
                SwiftUI.Section { LabeledContent(c.name, value: c.canMake ? (c.credits < 0 ? "Unlimited" : "\(c.credits) left") : "") } footer: { Text(c.stateLine) }
            }
            SwiftUI.Section("Tournaments") {
                if model.shownEvents.isEmpty { Text(model.signedIn ? "No tournaments yet. Make one below." : "Sign in to see your club’s tournaments.").foregroundStyle(FC.muted) }
                ForEach(model.shownEvents) { e in
                    Button { model.selection = e.id; if asSheet { dismiss() } } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.name.isEmpty ? "Tournament" : e.name).font(.headline).foregroundStyle(FC.ink)
                                Text([e.date.flatMap(dayLine), e.club].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(FC.muted)
                            }
                            Spacer()
                            if model.selection == e.id { Image(systemName: "checkmark").foregroundStyle(FC.primary) }
                        }
                    }
                    .swipeActions { Button("Remove", role: .destructive) { Task { await model.remove(e.id) } } }
                }
            }
            if model.signedIn {
                SwiftUI.Section {
                    TextField("New tournament name", text: $name)
                    Button { make() } label: { if making { ProgressView() } else { Text("Make a Tournament") } }
                        .disabled(making || !(model.me?.club?.canMake ?? false))
                } footer: { if let message { Text(message).foregroundStyle(FC.red) } }
            }
            SwiftUI.Section { NavigationLink("Add a tournament by its desk link") { AddByLinkView() } }
            if !model.signedIn {
                SwiftUI.Section { NavigationLink("Sign in with your club email") { SignInView() } }
            }
        }
        .scrollContentBackground(.hidden).background(FC.paper)
        .navigationTitle("Tournaments")
        .toolbar { if asSheet { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } } }
        .refreshable { await model.refresh() }
    }
    private func make() {
        making = true; message = nil
        Task {
            do { try await model.create(name); name = ""; if asSheet { dismiss() } } catch { message = error.localizedDescription }
            making = false
        }
    }
}

struct AddByLinkView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var busy = false
    @State private var message: String?
    var body: some View {
        Form {
            SwiftUI.Section {
                TextField("https://flagcast.app/g/…/desk#…", text: $link, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button { add() } label: { if busy { ProgressView() } else { Text("Add Tournament") } }.disabled(link.isEmpty || busy)
            } footer: { Text(message ?? "Paste the desk link the organizer sent you. It looks like …/g/abcd2345/desk#longkey") }
        }
        .navigationTitle("Add by desk link")
    }
    private func add() {
        busy = true; message = nil
        Task {
            do { try await model.add(link: link.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() } catch { message = error.localizedDescription }
            busy = false
        }
    }
}
