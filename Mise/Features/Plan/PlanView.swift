import SwiftUI

/// The week's meals. Phase 0b shows the empty state only: the week strip, the
/// builder and "Make list" are Phase 1 and Phase 2.
struct PlanView: View {
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("No meals planned", systemImage: "calendar")
            } description: {
                Text("Pick a few dinners for the week and Mise turns them into one grocery list, grouped the way you walk the store.")
            }
            .navigationTitle("Plan")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
        }
    }
}

#Preview {
    PlanView()
        .environment(AppContainer(inMemory: true))
}
