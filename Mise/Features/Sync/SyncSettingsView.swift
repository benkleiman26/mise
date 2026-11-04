import SwiftUI

/// Sharing a household with one other person, in Settings.
///
/// Three states and they are kept visibly apart, because "signed in" and
/// "sharing" are different things and conflating them is how someone ends up
/// signed in, syncing nothing, and unable to see why.
struct SyncSettingsView: View {
    @Environment(AppContainer.self) private var container
    @State private var store: SyncStore?
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var isJoining = false
    @State private var isConfirmingStop = false

    var body: some View {
        Group {
            if let store {
                switch store.step {
                case .notConfigured: notConfigured
                case .signedOut: signIn(store)
                case .ready: sharing(store)
                }

                if let problem = store.problem {
                    Section {
                        Text(problem).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task {
            if store == nil { store = SyncStore(container: container) }
            await store?.load()
        }
    }

    // MARK: - States

    @ViewBuilder
    private var notConfigured: some View {
        Section {
            Label("Sharing is not set up", systemImage: "icloud.slash")
        } footer: {
            Text("This copy of Mise has no server to sync with. Everything works, it just stays on this phone. See supabase/README.md in the project.")
        }
    }

    @ViewBuilder
    private func signIn(_ store: SyncStore) -> some View {
        Section {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
            SecureField("Password", text: $password)
                .textContentType(.password)

            Button {
                Task { await store.signIn(email: email, password: password) }
            } label: {
                if store.busy {
                    Label("Signing in", systemImage: "hourglass")
                } else {
                    Label("Sign in", systemImage: "person.crop.circle")
                }
            }
            .disabled(store.busy || email.isEmpty || password.isEmpty)

            Button("Create an account") {
                Task { await store.signUp(email: email, password: password) }
            }
            .disabled(store.busy || email.isEmpty || password.count < 6)
        } header: {
            Text("Share this household")
        } footer: {
            Text("Sign in on both phones with your own accounts, then share the invite code so you shop from one list.")
        }
    }

    @ViewBuilder
    private func sharing(_ store: SyncStore) -> some View {
        if store.isSharing {
            Section {
                Button {
                    Task { await store.sync() }
                } label: {
                    if store.busy {
                        Label("Syncing", systemImage: "hourglass")
                    } else {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(store.busy)

                LabeledContent("Status", value: store.statusText)
            } header: {
                Text("Sharing")
            } footer: {
                Text("The week, the grocery list and the pantry are shared. Recipes are not: import the same files on both phones and they line up.")
            }

            if let invite = store.inviteCode {
                Section {
                    Text(invite)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                    ShareLink(item: invite) {
                        Label("Send the invite code", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Invite code")
                } footer: {
                    Text("Anyone with this code and an account can read and change this household's list. Send it to one person, not to a group chat.")
                }
            }
        } else {
            Section {
                Button {
                    Task { await store.startSharing() }
                } label: {
                    Label("Start sharing", systemImage: "person.2")
                }
                .disabled(store.busy)

                Button {
                    isJoining = true
                } label: {
                    Label("Join with an invite code", systemImage: "arrow.right.circle")
                }
                .disabled(store.busy)
            } header: {
                Text("Share this household")
            } footer: {
                Text("Start on one phone, then join from the other with the code it shows. Whoever starts keeps their plan and list; whoever joins takes them on.")
            }
        }

        Section {
            if store.isSharing {
                Button(role: .destructive) { isConfirmingStop = true } label: {
                    Text("Stop sharing")
                }
            }
            Button("Sign out") { Task { await store.signOut() } }
        } footer: {
            if let email = store.signedInEmail {
                Text("Signed in as \(email).")
            }
        }
        .alert("Join a household", isPresented: $isJoining) {
            TextField("Invite code", text: $code)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Join") {
                Task { await store.joinSharing(code: code); code = "" }
            }
            Button("Cancel", role: .cancel) { code = "" }
        } message: {
            Text("Paste the code from the other phone.")
        }
        .confirmationDialog(
            "Stop sharing this household?",
            isPresented: $isConfirmingStop,
            titleVisibility: .visible
        ) {
            Button("Stop sharing", role: .destructive) { store.stopSharing() }
            Button("Keep sharing", role: .cancel) {}
        } message: {
            Text("This phone keeps everything it has and stops sending and receiving. The other phone is not affected.")
        }
    }
}
