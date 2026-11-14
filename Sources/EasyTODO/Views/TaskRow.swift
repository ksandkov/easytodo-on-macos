import AppKit
import SwiftData
import SwiftUI

@MainActor
struct TaskRow: View {
    @Bindable var task: TodoTask
    @ObservedObject var categoryStore = TaskCategoryStore.shared
    var onUpdate: () -> Void
    var onCompletionChanged: (_ task: TodoTask, _ oldValue: Bool, _ newValue: Bool) -> Void
    var onMoveToDate: ((_ task: TodoTask, _ date: Date) -> Void)? = nil
    var onRepeatRuleChanged: ((_ task: TodoTask, _ repeatRule: TaskRepeatRule) -> Void)? = nil
    var isCardStyle = false
    var onDelete: () -> Void

    @State private var isHoveringDelete = false
    @State private var isConfirmingDelete = false
    @State private var titleEditing = TaskTitleEditing()
    @State private var isMoveDatePresented = false
    @State private var moveDate = Date()

    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 10) {
            CategoryPicker(store: categoryStore, selection: categoryBinding, isStrip: true)
                .opacity(task.isCompleted ? 0.45 : 1)

            if !isCardStyle {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 14)
            }

            CheckBox(isOn: $task.isCompleted, isSubtle: isCardStyle)
                .onChange(of: task.isCompleted) { oldValue, newValue in
                    onCompletionChanged(task, oldValue, newValue)
                }

            titleContent

            Button {
                isConfirmingDelete = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .frame(width: 28, height: 28)
                    .background {
                        Circle()
                            .fill(isHoveringDelete ? Color.red.opacity(0.12) : Color.clear)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isHoveringDelete ? Color.red : Color.secondary)
            .opacity(isHoveringDelete ? 1 : 0.75)
            .help("Delete task")
            .accessibilityLabel("Delete task")
            .onHover { isHoveringDelete = $0 }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .contextMenu {
            taskContextMenu
        }
        .popover(isPresented: $isMoveDatePresented, arrowEdge: .trailing) {
            moveDatePopover
        }
        .confirmationDialog(
            "Delete this task?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmDeleteMessage)
        }
    }

    @ViewBuilder
    private var titleContent: some View {
        if let sessionID = titleEditing.sessionID {
            TaskTitleEditor(
                text: $titleEditing.draft,
                onCommit: { commitTitleEdit(sessionID: sessionID) },
                onCancel: { titleEditing.cancel(sessionID: sessionID) },
                fontSize: isCardStyle ? 19 : 15
            )
            .frame(maxWidth: .infinity, minHeight: isCardStyle ? 26 : 22)
        } else {
            FloatingTaskTitle(
                title: task.title,
                isCompleted: task.isCompleted,
                fontSize: isCardStyle ? 19 : 15,
                fontWeight: .regular,
                onDoubleClick: beginTitleEdit
            )
            .contextMenu { taskContextMenu }
            .frame(maxWidth: .infinity, minHeight: isCardStyle ? 26 : 22)
        }
    }

    private func beginTitleEdit() {
        titleEditing.begin(title: task.title)
    }

    private func commitTitleEdit(sessionID: UUID) {
        guard let title = titleEditing.commit(sessionID: sessionID) else { return }

        task.title = title
        onUpdate()
    }

    @ViewBuilder
    private var taskContextMenu: some View {
        Button {
            beginTitleEdit()
        } label: {
            Label("Edit", systemImage: "pencil")
        }

        Menu("Category") {
            Button("No category") { categoryBinding.wrappedValue = nil }
            ForEach(categoryStore.categories) { category in
                Button {
                    categoryBinding.wrappedValue = category.id
                } label: {
                    Label(category.name, systemImage: categoryStore.categoryID(for: task) == category.id ? "checkmark" : "circle")
                }
            }
        }

        Divider()

        Button(role: .destructive) {
            isConfirmingDelete = true
        } label: {
            Label("Delete", systemImage: "trash")
        }

        if onMoveToDate != nil {
            Divider()

            Button {
                moveTaskToTomorrow()
            } label: {
                Label("Move to Tomorrow", systemImage: "calendar.badge.clock")
            }

            Button {
                moveDate = task.scheduledDay(in: calendar)
                isMoveDatePresented = true
            } label: {
                Label("Move to...", systemImage: "calendar")
            }
        }

        if onRepeatRuleChanged != nil {
            Divider()

            Menu {
                repeatRuleButton(.none)
                repeatRuleButton(.daily)
                repeatRuleButton(.weekly)
            } label: {
                Label("Repeat", systemImage: "repeat")
            }
        }
    }

    private var moveDatePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker("Move Date", selection: $moveDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()

            HStack {
                Button("Cancel") {
                    isMoveDatePresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Move") {
                    onMoveToDate?(task, moveDate)
                    isMoveDatePresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    private func repeatRuleButton(_ repeatRule: TaskRepeatRule) -> some View {
        Button {
            onRepeatRuleChanged?(task, repeatRule)
        } label: {
            if task.repeatRule == repeatRule {
                Label(repeatRule.title, systemImage: "checkmark")
            } else {
                Text(repeatRule.title)
            }
        }
    }

    private func moveTaskToTomorrow() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: task.scheduledDay(in: calendar)) ?? .now
        onMoveToDate?(task, tomorrow)
    }

    private var confirmDeleteMessage: String {
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "This task will be removed." : "\"\(title)\" will be removed."
    }

    private var categoryBinding: Binding<UUID?> {
        Binding {
            categoryStore.categoryID(for: task)
        } set: { categoryID in
            categoryStore.assign(categoryID, to: task)
        }
    }
}
