import SwiftUI

/// Sharing a household with one other person, as rows inside Settings.
///
/// Every branch here returns rows, never a `Section`, and the sections are
/// assembled once at the top. The first version nested sections inside a
/// section, which does not render, and before that it rendered nothing at all
/// until its store existed, which meant the store was never built: a view that
/// renders nothing never appears, so the `.task` that creates it never runs.
/// The symptom was the whole section missing from Settings, which reads as an
/// old build rather than as a bug.
struct SyncSettingsView: View {
    @Environment(AppContainer.self) private var container
    /// The container's, not one of this screen's own. Sharing has to exist
    /// whether or not anybody is looking at Settings, which is the whole point
    /// of syncing on its own.
    private var store: SyncStore? { container.sync }
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var isJoining = false
    @State private var isConfirmingStop = false

    var body: some View {
        // Always present, so this view has something to appear as.
        Section {
            if let store {
                rows(store)
            } else {
                ProgressView()
            }
        } header: {
            Text("Share this household")
        } footer: {
            Text(footer)
        }
        .task {
            container.startSyncing()
            await store?.load()
        }
        .alert("Join another household", isPresented: $isJoining) {
            TextField("Invite code", text: $code)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Join") {
                let typed = code
                code = ""
                Task { await store?.joinSharing(code: typed) }
            }
            Button("Cancel", role: .cancel) { code = "" }
        } message: {
            Text("Only do this if you live with the person who sent the code. Your plan, list, pantry and recipes are combined with theirs, and both phones can then see and change everything.")
        }
        .confirmationDialog(
            "Stop sharing this household?",
            isPresented: $isConfirmingStop,
            titleVisibility: .visible
        ) {
            Button("Stop sharing", role: .destructive) { store?.stopSharing() }
            Button("Keep sharing", role: .cancel) {}
        } message: {
            Text("This phone keeps everything it has and stops sending and receiving. The other phone is not affected.")
        }

        if let store, store.step == .ready, store.isSharing, let invite = store.inviteCode {
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

        if let store, store.step == .ready {
            Section {
                if store.isSharing {
                    Button(role: .destructive) {
                        isConfirmingStop = true
                    } label: {
                        Text("Stop sharing")
                    }
                }
                Button("Sign out") {
                    Task { await store.signOut() }
                }
            } footer: {
                if let email = store.signedInEmail {
                    Text("Signed in as \(email).")
                }
            }
        }

        if let store, store.step != .notConfigured {
            Section {
                DisclosureGroup("Details") {
                    ForEach(store.details, id: \.0) { label, value in
                        LabeledContent(label, value: value)
                            .font(.footnote)
                    }
                    Button("Ask the server who I am") {
                        Task { await store.checkConnection() }
                    }
                    .font(.footnote)
                    if let says = store.serverSays {
                        Text(says)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("For working out why sync did or did not do something.")
            }
        }

        if let store, let shortfall = store.shortfall {
            Section {
                Label(shortfall, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
            }
        }

        if let store, let problem = store.problem {
            Section {
                Text(problem)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - The one section's rows

    @ViewBuilder
    private func rows(_ store: SyncStore) -> some View {
        switch store.step {
        case .notConfigured:
            Label("Not set up on this phone", systemImage: "icloud.slash")

        case .signedOut:
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
                Label(store.busy ? "Signing in" : "Sign in", systemImage: "person.crop.circle")
            }
            .disabled(store.busy || email.isEmpty || password.isEmpty)
            Button("Create an account") {
                Task { await store.signUp(email: email, password: password) }
            }
            .disabled(store.busy || email.isEmpty || password.count < 6)

        case .ready:
            if store.isSharing {
                Button {
                    Task { await store.sync() }
                } label: {
                    Label(
                        store.busy ? "Syncing" : "Sync now",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
                .disabled(store.busy)
                LabeledContent("Status", value: store.statusText)
            } else {
                Button {
                    Task { await store.startSharing() }
                } label: {
                    Label("Start sharing", systemImage: "person.2")
                }
                .disabled(store.busy)
                Button {
                    isJoining = true
                } label: {
                    Label("Join another household", systemImage: "arrow.right.circle")
                }
                .disabled(store.busy)
            }
        }
    }

    private var footer: String {
        guard let store else { return "" }
        switch store.step {
        case .notConfigured:
            return "This build has no server to sync with. Everything else works, it just stays on this phone. See supabase/README.md."
        case .signedOut:
            return "Sign in on both phones with your own accounts, then share the invite code so you shop from one list."
        case .ready:
            return store.isSharing
                ? "The week, the grocery list, the pantry and the recipes are shared with everyone holding this household's code."
                : "This phone already has its own household and keeps it whatever you do here. Start sharing to add a second phone in your home, then paste the code into that phone. Joining instead puts this phone into somebody else's household, which combines both sides' plans, lists, pantries and recipes."
        }
    }
}
