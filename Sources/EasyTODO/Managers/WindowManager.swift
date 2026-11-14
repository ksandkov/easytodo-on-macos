import AppKit
import SwiftData
import SwiftUI

/// Borderless windows must explicitly opt into keyboard and main-window focus.
final class TaskWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class WindowManager: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = WindowManager()
    static let minimumExpandedHeight: CGFloat = 180

    @Published private(set) var isCollapsed = false

    private struct SavedGeometry: Codable {
        var frame: CGRect
        var expandedFrame: CGRect?
    }

    private static let geometryKey = "mainWindowGeometry"
    private let defaults: UserDefaults
    private var modelContainer: ModelContainer?
    private var launchObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var mainWindow: NSWindow?
    private var compactLayout = CompactWindowLayout()
    private var expandedFrame: NSRect?
    private var layoutGeneration = 0
    private var isApplyingLayout = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
    }

    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        guard launchObserver == nil else { return }

        launchObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.showMainWindow() }
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveGeometry() }
        }
    }

    func makeMainWindow(modelContainer: ModelContainer) -> NSWindow {
        let window = TaskWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
            styleMask: [.borderless, .resizable, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        configureMainWindow(window)
        window.contentView = NSHostingView(rootView: ThemedContent(
            content: TodoListView(windowManager: self).modelContainer(modelContainer)
        ))
        return window
    }

    func configureMainWindow(_ window: NSWindow) {
        guard mainWindow !== window else {
            applyWindowSettings()
            return
        }

        isApplyingLayout = true
        mainWindow = window
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("easy-todo-main-window")
        window.title = "EasyTODO"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        compactLayout = CompactWindowLayout()
        expandedFrame = nil
        isCollapsed = false
        let screens = NSScreen.screens.map(\.visibleFrame)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var frame = NSRect(x: screen.midX - 170, y: screen.midY - 240, width: 340, height: 480)
        if let data = defaults.data(forKey: Self.geometryKey),
           let saved = try? JSONDecoder().decode(SavedGeometry.self, from: data) {
            if let expanded = saved.expandedFrame {
                let restoredExpanded = Self.visibleFrame(expanded, screens: screens)
                expandedFrame = restoredExpanded
                _ = compactLayout.toggle(frame: restoredExpanded, headerHeight: max(1, saved.frame.height))
                isCollapsed = true
            }
            frame = Self.visibleFrame(saved.frame, screens: screens, minimumHeight: isCollapsed ? 1 : Self.minimumExpandedHeight)
        }
        window.minSize = NSSize(width: 280, height: isCollapsed ? frame.height : Self.minimumExpandedHeight)
        window.maxSize = NSSize(width: .greatestFiniteMagnitude, height: isCollapsed ? frame.height : .greatestFiniteMagnitude)
        window.setFrame(frame, display: false)
        applyWindowSettings()
        isApplyingLayout = false
    }

    static func visibleFrame(_ saved: NSRect, screens: [NSRect], minimumHeight: CGFloat? = nil) -> NSRect {
        guard let fallback = screens.first else { return saved }
        let valid = saved.minX.isFinite && saved.minY.isFinite && saved.width.isFinite && saved.height.isFinite
            && saved.width > 0 && saved.height > 0
        let frame = valid ? saved : NSRect(x: fallback.midX - 170, y: fallback.midY - 240, width: 340, height: 480)
        let screen = screens.max { left, right in
            let leftIntersection = frame.intersection(left)
            let rightIntersection = frame.intersection(right)
            return max(0, leftIntersection.width) * max(0, leftIntersection.height)
                < max(0, rightIntersection.width) * max(0, rightIntersection.height)
        } ?? fallback
        let size = NSSize(
            width: min(max(280, frame.width), screen.width),
            height: min(max(minimumHeight ?? Self.minimumExpandedHeight, frame.height), screen.height)
        )
        return NSRect(
            x: min(max(frame.minX, screen.minX), screen.maxX - size.width),
            y: min(max(frame.minY, screen.minY), screen.maxY - size.height),
            width: size.width,
            height: size.height
        )
    }

    private func saveGeometry() {
        guard !isApplyingLayout, let window = mainWindow else { return }
        let geometry = SavedGeometry(frame: window.frame, expandedFrame: expandedFrame)
        guard let data = try? JSONEncoder().encode(geometry) else { return }
        defaults.set(data, forKey: Self.geometryKey)
    }

    func windowDidMove(_ notification: Notification) { saveGeometry() }
    func windowDidResize(_ notification: Notification) { saveGeometry() }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeMainWindow()
        return false
    }

    func applyWindowSettings() {
        guard let window = mainWindow else { return }
        window.level = defaults.bool(forKey: EasyTODOSettings.alwaysOnTop) ? .floating : .normal
        let transparency = defaults.object(forKey: EasyTODOSettings.transparency) as? Double ?? 0.80
        window.alphaValue = min(max(transparency, 0.50), 1.0)
    }

    static func activationPolicy(hideDockIcon: Bool, showMenuBar _: Bool) -> NSApplication.ActivationPolicy {
        hideDockIcon ? .accessory : .regular
    }

    func applyActivationPolicy() {
        NSApp.setActivationPolicy(Self.activationPolicy(
            hideDockIcon: defaults.bool(forKey: EasyTODOSettings.hiddenDockIcon),
            showMenuBar: defaults.bool(forKey: EasyTODOSettings.showMenuBar)
        ))
    }

    func toggleCollapsed(headerHeight: CGFloat) {
        guard let window = mainWindow, headerHeight.isFinite, headerHeight > 0 else { return }
        if !isCollapsed { expandedFrame = window.frame }
        let frame = compactLayout.toggle(frame: window.frame, headerHeight: headerHeight)
        isCollapsed = compactLayout.isCollapsed
        if !isCollapsed { expandedFrame = nil }
        let screens = NSScreen.screens.map(\.visibleFrame)
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        let currentScreen = screens.first { $0.contains(center) }
        let target = isCollapsed ? frame : Self.visibleFrame(frame, screens: currentScreen.map { [$0] } ?? screens)
        applyFrameAfterLayout(target, in: window)
    }

    func updateHeaderHeight(_ height: CGFloat) {
        guard isCollapsed, height.isFinite, height > 0, let window = mainWindow else { return }
        guard abs(window.frame.height - height) > 0.5 else { return }
        let frame = NSRect(x: window.frame.minX, y: window.frame.maxY - height, width: window.frame.width, height: height)
        applyFrameAfterLayout(frame, in: window)
    }

    private func applyFrameAfterLayout(_ frame: NSRect, in window: NSWindow) {
        layoutGeneration += 1
        let generation = layoutGeneration
        isApplyingLayout = true
        // SwiftUI must finish updating its content size before AppKit resizes the window.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.mainWindow === window, self.layoutGeneration == generation else { return }
            if self.isCollapsed {
                window.minSize = NSSize(width: 280, height: frame.height)
                window.maxSize = NSSize(width: .greatestFiniteMagnitude, height: frame.height)
            } else {
                window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                window.minSize = NSSize(width: 280, height: Self.minimumExpandedHeight)
            }
            window.setFrame(frame, display: true)
            self.isApplyingLayout = false
            self.saveGeometry()
        }
    }

    func showMainWindow() {
        if mainWindow == nil, let modelContainer {
            _ = makeMainWindow(modelContainer: modelContainer)
        }
        guard let window = mainWindow else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.setFrame(Self.visibleFrame(
            window.frame, screens: NSScreen.screens.map(\.visibleFrame), minimumHeight: isCollapsed ? 1 : Self.minimumExpandedHeight
        ), display: false)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeMainWindow() {
        saveGeometry()
        applyActivationPolicy()
        mainWindow?.orderOut(nil)
    }

    func minimizeMainWindow() { mainWindow?.miniaturize(nil) }

    func zoomMainWindow() {
        guard !isCollapsed else { return }
        mainWindow?.zoom(nil)
    }

    deinit {
        if let launchObserver { NotificationCenter.default.removeObserver(launchObserver) }
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
    }
}
