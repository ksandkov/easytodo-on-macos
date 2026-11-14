import SwiftUI

@MainActor
struct CategorySettingsView: View {
    @ObservedObject var store = TaskCategoryStore.shared
    @State private var newName = ""
    @State private var newColor = Color.blue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !store.categories.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(store.categories) { category in
                            CategorySettingsRow(store: store, category: category)
                        }
                    }
                }
                .frame(height: min(CGFloat(store.categories.count) * 36, 180))
            }
            HStack(spacing: 8) {
                ColorPicker("New category color", selection: $newColor, supportsOpacity: false)
                    .labelsHidden()
                TextField("New category", text: $newName)
                    .onSubmit(addCategory)
                Button(action: addCategory) { Image(systemName: "plus") }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Add category")
                    .accessibilityLabel("Add category")
            }
            Text("Deleting a category keeps its tasks without a category.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func addCategory() {
        guard let hex = TaskCategory.colorHex(from: newColor), store.add(name: newName, colorHex: hex) != nil else { return }
        newName = ""
    }
}

@MainActor
private struct CategorySettingsRow: View {
    @ObservedObject var store: TaskCategoryStore
    let category: TaskCategory
    @State private var name: String
    @State private var isConfirmingDelete = false
    @FocusState private var isNameFocused: Bool

    init(store: TaskCategoryStore, category: TaskCategory) {
        self.store = store
        self.category = category
        _name = State(initialValue: category.name)
    }

    var body: some View {
        HStack(spacing: 8) {
            ColorPicker("Color for \(category.name)", selection: Binding(
                get: { category.color },
                set: { if let hex = TaskCategory.colorHex(from: $0) { store.recolor(id: category.id, colorHex: hex) } }
            ), supportsOpacity: false)
            .labelsHidden()
            TextField("Category name", text: $name)
                .focused($isNameFocused)
                .onSubmit(commitName)
                .onChange(of: isNameFocused) { _, focused in if !focused { commitName() } }
            Button {
                isConfirmingDelete = true
            } label: {
                Image(systemName: "trash")
            }
            .help("Delete category \(category.name)")
            .accessibilityLabel("Delete category \(category.name)")
        }
        .frame(height: 32)
        .onDisappear(perform: commitName)
        .confirmationDialog("Delete category \(category.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete category", role: .destructive) { store.remove(id: category.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its tasks will remain without a category.")
        }
    }

    private func commitName() {
        store.rename(id: category.id, name: name)
        if let saved = store.categories.first(where: { $0.id == category.id }) { name = saved.name }
    }
}
