import AppKit
import SwiftUI

@MainActor
struct QuickAddPanelView: View {
    @ObservedObject var categoryStore = TaskCategoryStore.shared
    @State private var categoryID: UUID?
    static let cornerRadius: CGFloat = 22

    var onSubmit: (String, UUID?) -> Void
    var onCancel: () -> Void

    @State private var title = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let image = AppLogo.quickAddImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 28, height: 28)
            }

            CategoryPicker(store: categoryStore, selection: $categoryID, onSelection: { isFocused = true })

            TextField("Quick add a task...", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .medium))
                .focused($isFocused)
                .onSubmit {
                    onSubmit(title, categoryStore.validCategoryID(categoryID))
                }

            Text("Return")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(.primary.opacity(0.06))
                )
        }
        .padding(.horizontal, 18)
        .frame(width: 520, height: 76)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.62))
        )
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 28, x: 0, y: 18)
        .onAppear {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
        .onExitCommand(perform: onCancel)
    }
}
