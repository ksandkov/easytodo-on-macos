import SwiftUI

@MainActor
struct CategoryPicker: View {
    @ObservedObject var store = TaskCategoryStore.shared
    @Binding var selection: UUID?
    var isStrip = false
    var onSelection: () -> Void = {}
    @State private var isPresented = false

    private var category: TaskCategory? { store.categories.first { $0.id == selection } }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Group {
                if isStrip {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(category?.color ?? .gray)
                        .frame(width: 5, height: 26)
                        .frame(width: 16, height: 28)
                } else {
                    Circle()
                        .fill(category?.color ?? .gray)
                        .frame(width: 12, height: 12)
                        .padding(6)
                        .overlay { Circle().strokeBorder((category?.color ?? .gray).opacity(0.45), lineWidth: 1) }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Category: \(category?.name ?? "None")")
        .accessibilityLabel("Choose category: \(category?.name ?? "None")")
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            CategoryPalette(store: store, selection: store.validCategoryID(selection)) { id in
                selection = id
                isPresented = false
                onSelection()
            }
        }
    }
}

@MainActor
struct CategoryPalette: View {
    @ObservedObject var store: TaskCategoryStore
    let selection: UUID?
    var onSelect: (UUID?) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                entry(name: "No category", color: .gray, id: nil)
                ForEach(store.categories) { category in
                    entry(name: category.name, color: category.color, id: category.id)
                }
            }
        }
        .frame(width: 220, height: min(CGFloat(store.categories.count + 1) * 32, 240))
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .textBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
    }

    private func entry(name: String, color: Color, id: UUID?) -> some View {
        Button {
            onSelect(id)
        } label: {
            HStack(spacing: 9) {
                Circle().fill(color).frame(width: 12, height: 12)
                Text(name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark")
                    .opacity(selection == id ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selection == id ? .isSelected : [])
    }
}
