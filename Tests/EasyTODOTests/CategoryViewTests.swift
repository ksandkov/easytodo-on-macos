import AppKit
import SwiftUI
import SwiftData
import XCTest
@testable import EasyTODO

final class CategoryViewTests: XCTestCase {
    @MainActor
    func testLargeCatalogKeepsSettingsAndPaletteBounded() throws {
        _ = NSApplication.shared
        let suite = "EasyTODOTests.CategoryViews.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TaskCategoryStore(defaults: defaults)
        for index in 0..<40 {
            store.add(name: "A long category name that should not expand the window \(index)", colorHex: "336699")
        }
        let settings = NSHostingView(rootView: CategorySettingsView(store: store).frame(width: 360))
        XCTAssertLessThanOrEqual(settings.fittingSize.height, 340)
        XCTAssertLessThanOrEqual(settings.fittingSize.width, 360)
        let palette = NSHostingView(rootView: CategoryPalette(store: store, selection: nil, onSelect: { _ in }))
        XCTAssertLessThanOrEqual(palette.fittingSize.height, 280)
        XCTAssertLessThanOrEqual(palette.fittingSize.width, 250)
    }

    @MainActor
    func testSettingsNameDraftKeepsSpacesAndCommitsOnReturn() async throws {
        _ = NSApplication.shared
        let suite = "EasyTODOTests.CategoryNameDraft.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TaskCategoryStore(defaults: defaults)
        let first = try XCTUnwrap(store.categories.first)
        let window = TaskWindow(contentRect: NSRect(x: 100, y: 100, width: 360, height: 260),
                                styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(rootView: CategorySettingsView(store: store))
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        func nameField(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.isEditable, field.stringValue == first.name { return field }
            return view.subviews.compactMap { nameField(in: $0) }.first
        }
        let field = try XCTUnwrap(window.contentView.flatMap { nameField(in: $0) })
        field.selectText(nil)
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        editor.selectAll(nil)
        for characters in ["Home ", "Office"] {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0))
            window.sendEvent(event)
        }
        XCTAssertEqual(editor.string, "Home Office")
        XCTAssertEqual(store.categories.first?.name, first.name)
        let enter = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        window.sendEvent(enter)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(store.categories.first?.name, "Home Office")
        XCTAssertEqual(TaskCategoryStore(defaults: defaults).categories.first?.name, "Home Office")
    }

    @MainActor
    func testQuickAddCircleSelectionReachesSavedTask() async throws {
        _ = NSApplication.shared
        let suite = "EasyTODOTests.NativeCategoryAdd.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TaskCategoryStore(defaults: defaults)
        let container = try PersistenceController.modelContainer(inMemory: true)
        var saved: TodoTask?
        let window = TaskWindow(contentRect: NSRect(x: 100, y: 100, width: 320, height: 44),
                                styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(rootView: HeaderQuickAddPopover(categoryStore: store, onSubmit: { title, id in
            do {
                saved = try TaskCreation.addTask(title: title, in: container.mainContext, categoryID: id, categoryStore: store)
                return saved != nil
            } catch {
                XCTFail("Unable to create task: \(error)")
                return false
            }
        }, onCancel: {}))
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds: 100_000_000)

        func click(_ target: NSWindow, point: NSPoint) throws {
            let view = try XCTUnwrap(target.contentView)
            var hit = view.hitTest(view.convert(point, from: nil))
            while let current = hit {
                if let button = current as? NSButton {
                    button.performClick(nil)
                    return
                }
                hit = current.superview
            }
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: target.windowNumber,
                    context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
                if type == .leftMouseDown { view.mouseDown(with: event) } else { view.mouseUp(with: event) }
            }
        }
        try click(window, point: NSPoint(x: 25, y: 22))
        try await Task.sleep(nanoseconds: 100_000_000)
        let palette = try XCTUnwrap(NSApp.windows.first { $0.parent === window && $0.isVisible })
        try click(palette, point: NSPoint(x: 90, y: palette.frame.height - 56))
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(window.firstResponder is NSTextView)
        for (characters, keyCode) in [("Native categorized task", UInt16(0)), ("\r", UInt16(36))] {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
            window.sendEvent(event)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        let task = try XCTUnwrap(saved)
        XCTAssertEqual(task.title, "Native categorized task")
        XCTAssertEqual(store.categoryID(for: task), store.categories.first?.id)
    }

    @MainActor
    func testQuickAddOwnsItsCategoryPopoverButNotOtherWindows() async throws {
        _ = NSApplication.shared
        let panel = NSPanel(contentRect: NSRect(x: 100, y: 100, width: 400, height: 76),
                            styleMask: [.titled], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 76))
        panel.contentView = anchor
        panel.makeKeyAndOrderFront(nil)
        let popover = NSPopover()
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 120))
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        defer { popover.close() }
        try await Task.sleep(nanoseconds: 100_000_000)
        let popoverWindow = try XCTUnwrap(popover.contentViewController?.view.window)
        XCTAssertTrue(QuickAddPanelManager.isInsideQuickAdd(panel, panel: panel))
        XCTAssertTrue(QuickAddPanelManager.isInsideQuickAdd(popoverWindow, panel: panel))
        XCTAssertFalse(QuickAddPanelManager.isInsideQuickAdd(nil, panel: panel))
        let other = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer { other.close() }
        XCTAssertFalse(QuickAddPanelManager.isInsideQuickAdd(other, panel: panel))
    }

    @MainActor
    func testPaletteClickSelectsNamedCategory() async throws {
        _ = NSApplication.shared
        let suite = "EasyTODOTests.CategoryClick.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TaskCategoryStore(defaults: defaults)
        var selected: UUID?
        let window = TaskWindow(contentRect: NSRect(x: 100, y: 100, width: 236, height: 144),
                                styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let content = NSHostingView(rootView: CategoryPalette(store: store, selection: nil, onSelect: { selected = $0 }))
        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        let point = NSPoint(x: 90, y: window.frame.height - 8 - 48)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
            if type == .leftMouseDown { content.mouseDown(with: event) } else { content.mouseUp(with: event) }
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(selected, store.categories.first?.id)
    }
}
