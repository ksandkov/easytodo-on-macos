import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import EasyTODO

final class WindowAccessTests: XCTestCase {
    @MainActor
    func testDockCanBeHiddenWithTheMenuBarDisabled() {
        XCTAssertEqual(WindowManager.activationPolicy(hideDockIcon: true, showMenuBar: false), .accessory)
        XCTAssertEqual(WindowManager.activationPolicy(hideDockIcon: false, showMenuBar: false), .regular)
    }

    @MainActor
    func testDockVisibilityDoesNotDependOnTheMenuBar() {
        XCTAssertEqual(WindowManager.activationPolicy(hideDockIcon: true, showMenuBar: true), .accessory)
        XCTAssertEqual(WindowManager.activationPolicy(hideDockIcon: false, showMenuBar: true), .regular)
    }

    func testHideMenuBarToggleReadsTheInverseOfVisibility() {
        var isVisible = true
        let visibility = Binding(get: { isVisible }, set: { isVisible = $0 })
        let isHidden = SettingsView.hideMenuBarBinding(for: visibility)

        XCTAssertFalse(isHidden.wrappedValue)
        isVisible = false
        XCTAssertTrue(isHidden.wrappedValue)
    }

    func testHideMenuBarToggleWritesTheInverseAndHandlesRepeatedSelections() {
        var isVisible = true
        let visibility = Binding(get: { isVisible }, set: { isVisible = $0 })
        let isHidden = SettingsView.hideMenuBarBinding(for: visibility)

        isHidden.wrappedValue = true
        XCTAssertFalse(isVisible)
        isHidden.wrappedValue = true
        XCTAssertFalse(isVisible)
        isHidden.wrappedValue = false
        XCTAssertTrue(isVisible)
        isHidden.wrappedValue = false
        XCTAssertTrue(isVisible)
    }

    @MainActor
    func testReferenceRowsUseLargerTextAndCompletedStrikethrough() async throws {
        _ = NSApplication.shared
        let suite = "EasyTODOTests.ReferenceLayout.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = WindowManager(defaults: defaults)
        let container = try PersistenceController.modelContainer(inMemory: true)
        container.mainContext.insert(TodoTask(title: "Reference task"))
        let completed = TodoTask(title: "Completed task")
        completed.isCompleted = true
        container.mainContext.insert(completed)
        try container.mainContext.save()
        let window = manager.makeMainWindow(modelContainer: container)
        defer { window.close() }
        window.makeKeyAndOrderFront(nil)
        let content = try XCTUnwrap(window.contentView)
        try await waitForLayout { self.taskTitleLabels(in: content).count == 2 }
        let labels = taskTitleLabels(in: content)
        for label in labels {
            let font = try XCTUnwrap(label.attributedStringValue.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
            XCTAssertEqual(font.pointSize, 19)
            let strike = label.attributedStringValue.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int
            XCTAssertEqual(strike, label.stringValue == "Completed task" ? NSUnderlineStyle.single.rawValue : 0)
        }
        manager.toggleCollapsed(headerHeight: 94)
        try await waitForLayout { manager.isCollapsed && window.frame.height < 120 }
        XCTAssertTrue(taskTitleLabels(in: content).isEmpty)
    }

    @MainActor
    func testBottomAddTaskOpensInputAndSavesATask() async throws {
        _ = NSApplication.shared
        let suite = "EasyTODOTests.BottomAdd.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = WindowManager(defaults: defaults)
        let container = try PersistenceController.modelContainer(inMemory: true)
        let window = manager.makeMainWindow(modelContainer: container)
        defer { window.close() }
        window.makeKeyAndOrderFront(nil)
        let content = try XCTUnwrap(window.contentView)
        content.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        // Deliver directly to the hosting view: XCTest cannot activate a real application window.
        // The footer label is 12 points above the bottom edge, with a 23-point line height.
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: NSPoint(x: 90, y: 24), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
            ))
            if type == .leftMouseDown {
                content.mouseDown(with: event)
            } else {
                content.mouseUp(with: event)
            }
        }
        try await waitForLayout {
            NSApp.windows.contains { $0.parent === window && $0.isVisible && $0.firstResponder is NSTextView }
        }
        let input = try XCTUnwrap(NSApp.windows.first { $0.parent === window && $0.isVisible && $0.firstResponder is NSTextView })
        defer { input.close() }
        for (characters, keyCode) in [("x", UInt16(7)), ("\r", UInt16(36))] {
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: input.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: keyCode
            ))
            input.sendEvent(event)
        }
        try await waitForLayout {
            (try? container.mainContext.fetch(FetchDescriptor<TodoTask>()))?.first?.title == "x"
        }
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<TodoTask>()).count, 1)
    }

    @MainActor
    func testConfiguredMainWindowCanReceiveKeyboardInput() async throws {
        _ = NSApplication.shared
        let window = TaskWindow(
            contentRect: NSRect(x: 100, y: 200, width: 340, height: 480),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        WindowManager.shared.configureMainWindow(window)
        await Task.yield()

        XCTAssertTrue(window.canBecomeKey, "Editing requires a window that accepts keyboard focus.")
    }

    @MainActor
    func testTaskTitleEditorReceivesTypedTextAndReturn() async throws {
        _ = NSApplication.shared
        var title = "Existing title"
        var didCommit = false
        let window = TaskWindow(
            contentRect: NSRect(x: 100, y: 200, width: 340, height: 480),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(rootView: TaskTitleEditor(
            text: Binding(get: { title }, set: { title = $0 }),
            onCommit: { didCommit = true },
            onCancel: {}
        ).padding())
        WindowManager.shared.configureMainWindow(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try await waitForLayout { window.firstResponder is NSTextView }

        let fieldEditor = try XCTUnwrap(window.firstResponder as? NSTextView)
        fieldEditor.selectAll(nil)
        for (characters, keyCode) in [("x", UInt16(7)), ("\r", UInt16(36))] {
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode
            ))
            window.sendEvent(event)
        }
        XCTAssertEqual(title, "x")
        XCTAssertTrue(didCommit)
    }

    @MainActor
    func testExistingTaskCanBeDoubleClickedTypedAndSaved() async throws {
        _ = NSApplication.shared
        let suite = "EasyTODOTests.EditExisting.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try PersistenceController.modelContainer(inMemory: true)
        let task = TodoTask(title: "Original title")
        container.mainContext.insert(task)
        try container.mainContext.save()
        let manager = WindowManager(defaults: defaults)
        let window = manager.makeMainWindow(modelContainer: container)
        defer { window.close() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        func titleView(in view: NSView) -> FloatingTaskTitleView? {
            if let title = view as? FloatingTaskTitleView { return title }
            return view.subviews.compactMap { titleView(in: $0) }.first
        }
        try await waitForLayout { window.contentView.flatMap { titleView(in: $0) } != nil }
        let title = try XCTUnwrap(window.contentView.flatMap { titleView(in: $0) })
        let point = title.convert(NSPoint(x: title.bounds.midX, y: title.bounds.midY), to: nil)
        // Deliver the second click directly; a synthetic first click enters AppKit's drag-tracking loop.
        for clickCount in [2] {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: clickCount, clickCount: clickCount,
                    pressure: type == .leftMouseDown ? 1 : 0
                ))
                window.sendEvent(event)
            }
        }
        XCTAssertTrue(window.canBecomeKey)
        try await waitForLayout { window.firstResponder is NSTextView }
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        editor.selectAll(nil)
        for (characters, keyCode) in [("x", UInt16(7)), ("\r", UInt16(36))] {
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: keyCode
            ))
            window.sendEvent(event)
        }
        try await waitForLayout { task.title == "x" }
        let saved = try ModelContext(container).fetch(FetchDescriptor<TodoTask>())
        XCTAssertEqual(saved.first?.title, "x")
    }

    @MainActor
    func testMenuBarPreferenceUpdatesTheRealStatusItem() async throws {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: EasyTODOSettings.showMenuBar)
        let manager = MenuBarManager.shared
        defer {
            if let previous {
                defaults.set(previous, forKey: EasyTODOSettings.showMenuBar)
            } else {
                defaults.removeObject(forKey: EasyTODOSettings.showMenuBar)
            }
        }
        defaults.set(false, forKey: EasyTODOSettings.showMenuBar)
        let container = try PersistenceController.modelContainer(inMemory: true)
        manager.configure(modelContainer: container)
        manager.applicationDidFinishLaunching()

        func statusItem() -> NSStatusItem? {
            Mirror(reflecting: manager).children.first { $0.label == "statusItem" }?.value as? NSStatusItem
        }

        XCTAssertNil(statusItem())
        defaults.set(true, forKey: EasyTODOSettings.showMenuBar)
        try await waitForLayout { statusItem() != nil }
        XCTAssertTrue(statusItem()?.isVisible == true)
        XCTAssertFalse(statusItem()?.button?.title.isEmpty ?? true)

        defaults.set(false, forKey: EasyTODOSettings.showMenuBar)
        try await waitForLayout { statusItem() == nil }
    }

    @MainActor
    func testMainWindowRestoresSizeAndPositionAcrossManagerInstances() throws {
        _ = NSApplication.shared
        let suite = "EasyTODOTests.WindowGeometry.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try PersistenceController.modelContainer(inMemory: true)
        let manager = WindowManager(defaults: defaults)
        let window = manager.makeMainWindow(modelContainer: container)
        defer { window.close() }
        XCTAssertEqual(window.frame.width, 340, accuracy: 1)
        XCTAssertTrue(window.canBecomeKey)
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        let expected = NSRect(x: screen.minX + 60, y: screen.minY + 60, width: 400, height: 410)
        window.setFrame(expected, display: false)
        manager.closeMainWindow()

        let restoredManager = WindowManager(defaults: defaults)
        let restoredWindow = restoredManager.makeMainWindow(modelContainer: container)
        defer { restoredWindow.close() }
        XCTAssertEqual(restoredWindow.frame, expected)
    }

    @MainActor
    func testCollapsedWindowRestoresItsExpandedSizeAfterRelaunch() async throws {
        _ = NSApplication.shared
        let suite = "EasyTODOTests.CompactGeometry.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try PersistenceController.modelContainer(inMemory: true)
        let manager = WindowManager(defaults: defaults)
        let window = manager.makeMainWindow(modelContainer: container)
        defer { window.close() }
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        let expandedFrame = NSRect(x: screen.minX + 80, y: screen.minY + 80, width: 400, height: 430)
        window.setFrame(expandedFrame, display: false)
        manager.toggleCollapsed(headerHeight: 76)
        try await waitForLayout { window.frame.height < 120 }
        manager.closeMainWindow()

        let restoredManager = WindowManager(defaults: defaults)
        let restoredWindow = restoredManager.makeMainWindow(modelContainer: container)
        defer { restoredWindow.close() }
        XCTAssertTrue(restoredManager.isCollapsed)
        XCTAssertLessThan(restoredWindow.frame.height, 120)
        XCTAssertEqual(restoredWindow.frame.maxY, expandedFrame.maxY, accuracy: 1)
        restoredManager.toggleCollapsed(headerHeight: 76)
        try await waitForLayout { abs(restoredWindow.frame.height - expandedFrame.height) < 1 }
        XCTAssertEqual(restoredWindow.frame, expandedFrame)
    }

    @MainActor
    func testExpandingNearTheScreenEdgeKeepsTheWindowVisible() async throws {
        _ = NSApplication.shared
        let suite = "EasyTODOTests.ExpandedVisibility.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try PersistenceController.modelContainer(inMemory: true)
        let manager = WindowManager(defaults: defaults)
        let window = manager.makeMainWindow(modelContainer: container)
        defer { window.close() }
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        manager.toggleCollapsed(headerHeight: 76)
        try await waitForLayout { window.frame.height < 120 }
        window.setFrameOrigin(NSPoint(x: screen.minX + 20, y: screen.minY + 20))
        manager.toggleCollapsed(headerHeight: 76)
        try await waitForLayout { window.frame.height >= 320 }
        XCTAssertTrue(screen.contains(window.frame))
    }

    @MainActor
    func testHideAndShowDoesNotResetTheCurrentGeometry() async throws {
        _ = NSApplication.shared
        let suite = "EasyTODOTests.ShowGeometry.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = WindowManager(defaults: defaults)
        let container = try PersistenceController.modelContainer(inMemory: true)
        let window = manager.makeMainWindow(modelContainer: container)
        defer { window.close() }
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        let expected = NSRect(x: screen.minX + 60, y: screen.minY + 60, width: 400, height: 410)
        window.setFrame(expected, display: false)
        manager.closeMainWindow()
        manager.showMainWindow()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(window.frame, expected)
    }

    @MainActor
    func testShortWindowKeepsItsHeightAfterReopenRelaunchAndCompactMode() async throws {
        _ = NSApplication.shared
        let suite = "EasyTODOTests.ShortWindow.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try PersistenceController.modelContainer(inMemory: true)
        container.mainContext.insert(TodoTask(title: "Small window task"))
        try container.mainContext.save()
        let manager = WindowManager(defaults: defaults)
        let window = manager.makeMainWindow(modelContainer: container)
        defer { window.close() }
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        let expected = NSRect(x: screen.minX + 60, y: screen.minY + 60, width: 380, height: 180)
        XCTAssertEqual(window.minSize.height, 180)
        window.setFrame(expected, display: false)
        manager.closeMainWindow()
        manager.showMainWindow()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(window.frame, expected)
        XCTAssertEqual(try XCTUnwrap(window.contentView).frame.height, 180, accuracy: 1)
        manager.toggleCollapsed(headerHeight: 76)
        try await waitForLayout { window.frame.height < 120 }
        manager.toggleCollapsed(headerHeight: 76)
        try await waitForLayout { !manager.isCollapsed && abs(window.frame.height - 180) < 1 }
        XCTAssertEqual(window.minSize.height, 180)
        manager.closeMainWindow()

        let restoredManager = WindowManager(defaults: defaults)
        let restoredWindow = restoredManager.makeMainWindow(modelContainer: container)
        defer { restoredWindow.close() }
        XCTAssertEqual(restoredWindow.frame, expected)
    }

    @MainActor
    func testGeometryFromADisconnectedDisplayReturnsToAVisibleScreen() {
        let screen = NSRect(x: 0, y: 0, width: 800, height: 600)
        let saved = NSRect(x: 9000, y: 9000, width: 340, height: 480)
        let restored = WindowManager.visibleFrame(saved, screens: [screen])
        XCTAssertTrue(screen.contains(restored))
        XCTAssertEqual(restored.size, saved.size)
        let oversized = WindowManager.visibleFrame(NSRect(x: -100, y: -100, width: 2000, height: 1600), screens: [screen])
        XCTAssertTrue(screen.contains(oversized))
    }

    @MainActor
    func testNativeSettingsWindowFitsItsChangingContent() async throws {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let previousMenuBar = defaults.object(forKey: EasyTODOSettings.showMenuBar)
        let previousDock = defaults.object(forKey: EasyTODOSettings.hiddenDockIcon)
        defer {
            for (key, value) in [(EasyTODOSettings.showMenuBar, previousMenuBar), (EasyTODOSettings.hiddenDockIcon, previousDock)] {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(true, forKey: EasyTODOSettings.showMenuBar)
        defaults.set(false, forKey: EasyTODOSettings.hiddenDockIcon)
        SettingsWindowManager.shared.showSettings()
        let window = try XCTUnwrap(NSApp.windows.first { $0.identifier?.rawValue == "easy-todo-settings" })
        defer { window.close() }
        try await waitForLayout { abs(window.frame.width - 420) < 1 }
        let originalHeight = window.frame.height
        XCTAssertLessThan(originalHeight, 600)
        defaults.set(true, forKey: EasyTODOSettings.hiddenDockIcon)
        defaults.set(false, forKey: EasyTODOSettings.showMenuBar)
        try await waitForLayout { window.frame.height > originalHeight }
        XCTAssertEqual(window.frame.width, 420, accuracy: 1)
        XCTAssertLessThan(window.frame.height, 600)
    }

    @MainActor
    func testSettingsContentFitsACompactWindow() {
        _ = NSApplication.shared
        let content = NSHostingView(rootView: SettingsView())
        let size = content.fittingSize

        XCTAssertEqual(size.width, 420, accuracy: 1)
        XCTAssertGreaterThan(size.height, 300)
        XCTAssertLessThan(size.height, 600)
    }

    @MainActor
    func testHostedWindowRestoresItsHeightAfterCollapsing() async throws {
        _ = NSApplication.shared
        let suite = "EasyTODOTests.HostedGeometry.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = WindowManager(defaults: defaults)
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 200, width: 340, height: 480),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        manager.configureMainWindow(window)
        let container = try PersistenceController.modelContainer(inMemory: true)
        window.contentView = NSHostingView(rootView: TodoListView(windowManager: manager).modelContainer(container))

        try await waitForLayout { abs(window.frame.height - 480) < 1 }
        let originalTop = window.frame.maxY

        manager.toggleCollapsed(headerHeight: 70)
        try await waitForLayout {
            window.frame.height < 120 && (window.contentView?.fittingSize.height ?? 480) < 120
        }
        XCTAssertTrue(manager.isCollapsed)

        manager.toggleCollapsed(headerHeight: 70)
        try await waitForLayout { abs(window.frame.height - 480) < 1 }
        XCTAssertFalse(manager.isCollapsed)
        XCTAssertEqual(window.frame.maxY, originalTop, accuracy: 1)
    }

    @MainActor
    func testHeaderDoubleClickExpandsTheCollapsedWindow() async throws {
        _ = NSApplication.shared
        let suite = "EasyTODOTests.HeaderGeometry.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = WindowManager(defaults: defaults)
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 200, width: 340, height: 480),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer {
            if manager.isCollapsed { manager.toggleCollapsed(headerHeight: 70) }
            window.close()
        }
        let container = try PersistenceController.modelContainer(inMemory: true)
        window.contentView = NSHostingView(rootView: TodoListView(windowManager: manager).modelContainer(container))
        manager.configureMainWindow(window)
        window.makeKeyAndOrderFront(nil)
        try await waitForLayout { window.contentView?.window != nil }

        doubleClickHeader(in: window)
        try await waitForLayout { manager.isCollapsed && window.frame.height < 120 }
        doubleClickHeader(in: window, topInset: 5)
        try await waitForLayout { !manager.isCollapsed && window.frame.height >= 320 }
    }

    @MainActor
    private func taskTitleLabels(in view: NSView) -> [NSTextField] {
        if view is FloatingTaskTitleView {
            return view.subviews.compactMap { $0 as? NSTextField }
        }
        return view.subviews.flatMap { taskTitleLabels(in: $0) }
    }

    @MainActor
    private func doubleClickHeader(in window: NSWindow, topInset: CGFloat = 25) {
        for clickCount in 1...2 {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(
                    with: type,
                    location: NSPoint(x: 40, y: window.frame.height - topInset),
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: clickCount,
                    clickCount: clickCount,
                    pressure: type == .leftMouseDown ? 1 : 0
                )!
                NSApp.sendEvent(event)
            }
        }
    }

    @MainActor
    private func waitForLayout(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition() && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), "The hosted view did not reach the requested state.")
    }
}
