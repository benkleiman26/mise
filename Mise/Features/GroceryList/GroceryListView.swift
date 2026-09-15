import SwiftUI

/// The hero screen, empty until Phase 2 builds `ListGenerator`.
struct GroceryListView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("No grocery list yet", systemImage: "checklist")
            } description: {
                Text("Plan some meals, then tap Make list. Mise merges what the recipes share, leaves out what is already in your pantry, and sorts the rest by aisle.")
            }
            .navigationTitle("List")
        }
    }
}

#Preview {
    GroceryListView()
}
