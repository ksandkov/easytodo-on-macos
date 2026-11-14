import AppKit
import SwiftData
import SwiftUI

@MainActor
struct TodoListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var windowManager: WindowManager
    @Query(sort: [
        SortDescriptor(\TodoTask.sortOrder),
        SortDescriptor(\TodoTask.createdAt)
    ]) private var tasks: [TodoTask]

    @AppStorage(EasyTODOSettings.alwaysOnTop) private var alwaysOnTop = true
    @AppStorage(EasyTODOSettings.hiddenDockIcon) private var hiddenDockIcon = false
    @AppStorage(EasyTODOSettings.showMenuBar) private var showMenuBar = true
    @AppStorage(EasyTODOSettings.transparency) private var transparency = 0.80

    @State private var selectedDate = Date()
    @State private var isCalendarPresented = false
    @State private var isHeaderQuickAddPresented = false
    @State private var isFooterQuickAddPresented = false
    @State private var deletedTaskToRestore: DeletedTaskSnapshot?
    @State private var undoKeyMonitor: Any?
    @State private var fireworksTrigger = 0
    @State private var headerHeight: CGFloat = 76

    private let calendar = Calendar.current
    private let dayRefreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    init(windowManager: WindowManager? = nil) {
        self.windowManager = windowManager ?? .shared
    }

    private var completedCount: Int {
        displayedTasks.filter(\.isCompleted).count
    }

    private var orderedTasks: [TodoTask] {
        displayedTasks
    }

    private var displayedTasks: [TodoTask] {
        TaskListOrdering.ordered(tasksScheduled(on: selectedDate))
    }

    private var hasActiveAndCompletedTasks: Bool {
        displayedTasks.contains { !$0.isCompleted } && displayedTasks.contains { $0.isCompleted }
    }

    private var headerTitle: String {
        if calendar.isDateInToday(selectedDate) {
            return "Today"
        }

        return selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    var body: some View {
        ZStack {
            noteSurface

            VStack(spacing: 0) {
                header

                if !windowManager.isCollapsed {
                    Divider()
                        .padding(.horizontal, 18)

                    List {
                        if displayedTasks.isEmpty {
                            VStack(spacing: 6) {
                                Text("No tasks for \(shortDate(for: selectedDate))")
                                    .font(.system(size: 15))
                                Text("Add your first task below.")
                                    .font(.system(size: 13))
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }

                        ForEach(orderedTasks) { task in
                            VStack(spacing: 0) {
                                if shouldShowCompletedSeparator(before: task) {
                                    completedSeparator
                                }

                                TaskRow(
                                    task: task,
                                    onUpdate: saveChanges,
                                    onCompletionChanged: handleCompletionChange,
                                    onMoveToDate: moveTask,
                                    onRepeatRuleChanged: updateRepeatRule,
                                    isCardStyle: true
                                ) {
                                    delete(task)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .onMove(perform: moveTasks)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)

                    Divider()
                        .padding(.horizontal, 18)

                    footerAddTask
                }
            }
            CompletionFireworksView(trigger: fireworksTrigger)
        }
        .frame(
            minWidth: 280,
            idealWidth: 340,
            minHeight: windowManager.isCollapsed ? headerHeight : WindowManager.minimumExpandedHeight,
            idealHeight: windowManager.isCollapsed ? headerHeight : 480,
            maxHeight: windowManager.isCollapsed ? headerHeight : .infinity
        )
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .onPreferenceChange(HeaderHeightPreferenceKey.self) { height in
            guard height > 0 else { return }
            headerHeight = height
            windowManager.updateHeaderHeight(height)
        }
        .contextMenu {
            Button {
                SettingsWindowManager.shared.showSettings()
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }

            Button(action: toggleCollapsed) {
                Label(
                    windowManager.isCollapsed ? "Expand Task List" : "Collapse to Header",
                    systemImage: windowManager.isCollapsed ? "chevron.down" : "chevron.up"
                )
            }

            Divider()

            Button {
                windowManager.closeMainWindow()
            } label: {
                Label("Close Window", systemImage: "xmark")
            }

            Button {
                windowManager.minimizeMainWindow()
            } label: {
                Label("Minimize Window", systemImage: "minus")
            }

            Button {
                windowManager.zoomMainWindow()
            } label: {
                Label("Zoom Window", systemImage: "arrow.up.left.and.arrow.down.right")
            }

            Divider()

            Button {
                alwaysOnTop.toggle()
                windowManager.applyWindowSettings()
            } label: {
                Label("Always on Top", systemImage: alwaysOnTop ? "checkmark.circle.fill" : "circle")
            }

            Menu {
                transparencyMenuButton(title: "100%", value: 1.0)
                transparencyMenuButton(title: "80%", value: 0.80)
                transparencyMenuButton(title: "50%", value: 0.50)
            } label: {
                Label("Transparency: \(transparencyTitle)", systemImage: "slider.horizontal.3")
            }

            if deletedTaskToRestore != nil {
                Divider()

                Button {
                    undoLastDeletedTask()
                } label: {
                    Label("Undo Delete", systemImage: "arrow.uturn.backward")
                }
            }

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit EasyTODO", systemImage: "power")
            }
        }
        .sheet(isPresented: $isCalendarPresented) {
            CalendarPlannerView(
                tasks: tasks,
                selectedDate: $selectedDate,
                onAddTask: { title, date, categoryID in
                    _ = addTask(title: title, for: date, categoryID: categoryID)
                },
                onUpdate: saveChanges,
                onCompletionChanged: handleCompletionChange,
                onDelete: delete,
                onMoveTasks: { date, source, destination in
                    moveTasks(on: date, from: source, to: destination)
                }
            )
        }
        .onAppear {
            runDailyTaskMaintenance()
            installUndoDeleteKeyboardMonitor()
            windowManager.applyWindowSettings()
            windowManager.applyActivationPolicy()
        }
        .onDisappear {
            removeUndoDeleteKeyboardMonitor()
        }
        .onReceive(NotificationCenter.default.publisher(for: .easyTODOFocusNewTask)) { _ in
            windowManager.showMainWindow()
            focusNewTaskInput()
        }
        .onReceive(NotificationCenter.default.publisher(for: .easyTODOUndoDeleteTask)) { _ in
            undoLastDeletedTask()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            saveChanges()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            saveChanges()
        }
        .onReceive(dayRefreshTimer) { _ in
            runDailyTaskMaintenance()
        }
        .onChange(of: alwaysOnTop) { _, _ in
            windowManager.applyWindowSettings()
        }
        .onChange(of: transparency) { _, _ in
            windowManager.applyWindowSettings()
        }
        .onChange(of: hiddenDockIcon) { _, _ in
            windowManager.applyActivationPolicy()
        }
        .onChange(of: showMenuBar) { _, _ in
            windowManager.applyActivationPolicy()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                runDailyTaskMaintenance()
            } else {
                saveChanges()
            }
        }
    }

    private var noteSurface: some View {
        Color(nsColor: .textBackgroundColor)
            .ignoresSafeArea()
            .contentShape(Rectangle())
    }

    private var footerAddTask: some View {
        Button {
            windowManager.showMainWindow()
            isHeaderQuickAddPresented = false
            isFooterQuickAddPresented = true
        } label: {
            Text("+ Add Task")
                .font(.system(size: 19))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .accessibilityLabel("Add task at bottom")
        .accessibilityIdentifier("footer-add-task")
        .popover(isPresented: $isFooterQuickAddPresented, arrowEdge: .bottom) {
            HeaderQuickAddPopover(
                onSubmit: { title, categoryID in
                    addTask(title: title, for: selectedDate, categoryID: categoryID) != nil
                },
                onCancel: dismissQuickAdd
            )
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 3) {
                Text(headerTitle)
                    .font(.system(size: 26, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("\(completedCount) / \(displayedTasks.count) complete")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .help("Double-click to collapse or expand the task list")
            .accessibilityAction(named: Text("Collapse or expand task list"), toggleCollapsed)

            Button {
                if windowManager.isCollapsed {
                    toggleCollapsed()
                }
                isCalendarPresented = true
            } label: {
                Image(systemName: "calendar")
                    .frame(width: 28, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open calendar")
            .accessibilityLabel("Open calendar")
            .accessibilityIdentifier("header-calendar")

            Button {
                SettingsWindowManager.shared.showSettings()
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 28, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("header-settings")

            Button(action: showHeaderQuickAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add task")
            .accessibilityIdentifier("header-add-task")
            .popover(isPresented: $isHeaderQuickAddPresented, arrowEdge: .top) {
                HeaderQuickAddPopover(
                    onSubmit: { title, categoryID in
                        addTask(title: title, for: selectedDate, categoryID: categoryID) != nil
                    },
                    onCancel: dismissQuickAdd
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: toggleCollapsed)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: HeaderHeightPreferenceKey.self, value: geometry.size.height)
            }
        }
    }

    private func showHeaderQuickAdd() {
        windowManager.showMainWindow()
        isFooterQuickAddPresented = false
        isHeaderQuickAddPresented = true
    }

    private func dismissQuickAdd() {
        isHeaderQuickAddPresented = false
        isFooterQuickAddPresented = false
    }

    private func toggleCollapsed() {
        dismissQuickAdd()
        windowManager.toggleCollapsed(headerHeight: headerHeight)
    }

    private var transparencyTitle: String {
        "\(Int((transparency * 100).rounded()))%"
    }

    private func transparencyMenuButton(title: String, value: Double) -> some View {
        Button {
            transparency = value
            windowManager.applyWindowSettings()
        } label: {
            Label(title, systemImage: isSelectedTransparency(value) ? "checkmark.circle.fill" : "circle")
        }
    }

    private func isSelectedTransparency(_ value: Double) -> Bool {
        abs(transparency - value) < 0.001
    }

    private var completedSeparator: some View {
        Rectangle()
            .fill(.secondary.opacity(0.25))
            .frame(height: 1)
            .padding(.vertical, 16)
    }

    private func shouldShowCompletedSeparator(before task: TodoTask) -> Bool {
        guard hasActiveAndCompletedTasks, task.isCompleted else { return false }
        return orderedTasks.first(where: \.isCompleted) === task
    }

    private func focusNewTaskInput() {
        showHeaderQuickAdd()
    }

    private func delete(_ task: TodoTask) {
        dismissQuickAdd()
        do {
            deletedTaskToRestore = try DeletedTaskSnapshot.delete(task, in: modelContext, calendar: calendar)
        } catch {
            assertionFailure("Unable to delete task: \(error)")
        }
    }

    private func undoLastDeletedTask() {
        guard let deletedTaskToRestore else { return }

        do {
            try deletedTaskToRestore.restore(in: modelContext)
            selectedDate = deletedTaskToRestore.scheduledDate
            self.deletedTaskToRestore = nil
        } catch {
            assertionFailure("Unable to restore task: \(error)")
        }
    }

    private func installUndoDeleteKeyboardMonitor() {
        guard undoKeyMonitor == nil else { return }

        undoKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if isHeaderQuickAddPresented || isFooterQuickAddPresented, event.keyCode == 53 {
                dismissQuickAdd()
                return nil
            }

            guard isUndoDeleteShortcut(event), deletedTaskToRestore != nil else {
                return event
            }

            undoLastDeletedTask()
            return nil
        }
    }

    private func removeUndoDeleteKeyboardMonitor() {
        guard let undoKeyMonitor else { return }

        NSEvent.removeMonitor(undoKeyMonitor)
        self.undoKeyMonitor = nil
    }

    private func isUndoDeleteShortcut(_ event: NSEvent) -> Bool {
        guard event.charactersIgnoringModifiers?.lowercased() == "z" else {
            return false
        }

        return event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.control)
    }

    private func moveTasks(from source: IndexSet, to destination: Int) {
        moveTasks(on: selectedDate, from: source, to: destination)
    }

    private func moveTasks(on date: Date, from source: IndexSet, to destination: Int) {
        TaskListOrdering.moveTasks(from: source, to: destination, in: tasksScheduled(on: date))
        saveChanges()
    }

    private func moveTask(_ task: TodoTask, to date: Date) {
        TaskScheduling.move(task, to: date, among: tasks, calendar: calendar)
        saveChanges()
    }

    private func updateRepeatRule(_ task: TodoTask, to repeatRule: TaskRepeatRule) {
        do {
            try TaskRepeatScheduler.setRepeatRule(
                repeatRule,
                for: task,
                tasks: tasks,
                in: modelContext,
                calendar: calendar
            )
        } catch {
            assertionFailure("Unable to update task repeat rule: \(error)")
        }
    }

    private func handleCompletionChange(task: TodoTask, oldValue: Bool, newValue: Bool) {
        let taskDate = task.scheduledDay(in: calendar)

        if !oldValue && newValue {
            TaskListOrdering.moveCompletedTaskToFront(task, in: tasksScheduled(on: taskDate))
        } else if oldValue && !newValue {
            TaskListOrdering.moveReactivatedTaskToEnd(task, in: tasksScheduled(on: taskDate))
        }

        saveChanges()

        guard !oldValue && newValue else { return }

        CompletionFeedbackPlayer.playTaskCompletedSound()
        fireworksTrigger += 1
    }

    private func addTask(title: String, for date: Date, categoryID: UUID? = nil) -> TodoTask? {
        do {
            let task = try TaskCreation.addTask(title: title, scheduledDate: date, in: modelContext, calendar: calendar, categoryID: categoryID)

            return task
        } catch {
            assertionFailure("Unable to save task: \(error)")
            return nil
        }
    }

    private func tasksScheduled(on date: Date) -> [TodoTask] {
        tasks.filter { task in
            task.isScheduled(on: date, calendar: calendar)
        }
    }

    private func runDailyTaskMaintenance() {
        let today = calendar.startOfDay(for: .now)
        var didChange = false

        for task in tasks where task.scheduledDate == nil {
            task.scheduledDate = today
            didChange = true
        }

        didChange = TaskDayMaintenance.rolloverUnfinishedTasksToToday(
            tasks,
            today: today,
            calendar: calendar
        ) || didChange

        if selectedDate < today {
            selectedDate = today
        }

        if didChange {
            saveChanges()
        }
    }

    private func shortDate(for date: Date) -> String {
        if calendar.isDateInToday(date) {
            return "Today"
        }

        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Unable to save tasks: \(error)")
        }
    }
}

private struct HeaderHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
