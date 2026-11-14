import SwiftUI

struct TaskTitleEditor: View {
    @Binding var text: String
    var onCommit: () -> Void
    var onCancel: () -> Void
    var fontSize: CGFloat = 15

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Task title", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: fontSize))
            .focused($isFocused)
            .onSubmit(onCommit)
            .onExitCommand(perform: onCancel)
            .onChange(of: isFocused) { wasFocused, isFocused in
                if wasFocused && !isFocused {
                    onCommit()
                }
            }
            .task {
                isFocused = true
            }
            .onDisappear(perform: onCommit)
            .accessibilityLabel("Edit task title")
    }
}
