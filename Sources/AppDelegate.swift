import SwiftUI
import AppKit
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The live delegate instance. `NSApp.delegate as? AppDelegate` is unreliable from some
    /// SwiftUI contexts (e.g. `.commands`), so menus route through this instead.
    static private(set) weak var shared: AppDelegate?

    let appState = AppState()

    private var mainPanel: GlassPanel<MainWindowRoot>?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var historyWindow: NSWindow?
    private var settingsWindow: NSWindow?

    private let compactHeight: CGFloat = 116
    private let expandedHeight: CGFloat = 420
    private let windowWidth: CGFloat = 540

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        appState.settings.applyAppearance()
        applyActivationPolicy()

        appState.requestShowMainWindow = { [weak self] in self?.showMainWindow() }
        appState.requestActivateApp = { NSApp.activate(ignoringOtherApps: true) }
        appState.isMainWindowVisible = { [weak self] in self?.mainPanel?.isVisible ?? false }

        setupStatusItem()
        registerHotkeys()
        observePreviewChanges()
        observeKeepOnTop()

        if appState.settings.hasOnboarded {
            showMainWindow()
        } else {
            showOnboarding()
        }

    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    // MARK: Main window

    private func makeMainPanelIfNeeded() {
        guard mainPanel == nil else { return }
        let root = MainWindowRoot(state: appState)
        let panel = GlassPanel(content: root, size: NSSize(width: windowWidth, height: compactHeight))
        panel.title = "Snip"
        if let screen = NSScreen.main {
            let x = screen.frame.midX - windowWidth / 2
            let y = screen.frame.maxY - 160
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.level = appState.settings.keepOnTop ? .floating : .normal
        mainPanel = panel
    }

    func showMainWindow() {
        makeMainPanelIfNeeded()
        applyWindowLevel()
        mainPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        syncWindowHeight(animated: false)
    }

    private func applyWindowLevel() {
        mainPanel?.level = appState.settings.keepOnTop ? .floating : .normal
    }

    /// Re-applies the window level whenever "Keep window on top" changes.
    private func observeKeepOnTop() {
        withObservationTracking {
            _ = appState.settings.keepOnTop
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyWindowLevel()
                self?.observeKeepOnTop()
            }
        }
    }

    func toggleMainWindow() {
        if let panel = mainPanel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            showMainWindow()
        }
    }

    private func observePreviewChanges() {
        // Lightweight polling-free observation via withObservationTracking re-arm.
        observeHasPreview()
    }

    private func observeHasPreview() {
        withObservationTracking {
            _ = appState.hasPreview
            _ = appState.markupActive
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.syncWindowHeight(animated: true)
                self?.observeHasPreview()
            }
        }
    }

    private func syncWindowHeight(animated: Bool) {
        guard let panel = mainPanel else { return }
        let target = appState.hasPreview ? expandedHeight : compactHeight
        panel.setHeight(target, animated: animated)
    }

    // MARK: Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Snip")
            button.image?.isTemplate = true
            button.action = #selector(togglePopover)
            button.target = self
        }
        statusItem = item
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover == nil {
            let p = NSPopover()
            p.behavior = .transient
            p.animates = true
            let view = MenuBarView(state: appState) { [weak self] in self?.popover?.performClose(nil) }
            p.contentViewController = NSHostingController(rootView: view)
            popover = p
        }
        if let popover, popover.isShown {
            popover.performClose(nil)
        } else {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover?.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: Settings

    /// AppDelegate-owned settings window. Reliable from any caller (the SwiftUI
    /// `showSettingsWindow:` action was flaky from the in-app menu), and explicitly
    /// raised above the floating main panel so it can't open hidden behind it.
    func openSettingsWindow() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView().environment(appState))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Snip Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 520, height: 460))
            window.center()
            settingsWindow = window
        }
        // Sit at the same level as the main panel so "keep on top" never hides it.
        settingsWindow?.level = (mainPanel?.level == .floating) ? .floating : .normal
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: History window

    func showHistoryWindow() {
        if historyWindow == nil {
            let hosting = NSHostingController(rootView: HistoryView(state: appState).frame(minWidth: 640, minHeight: 460))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Capture History"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.setContentSize(NSSize(width: 720, height: 520))
            window.center()
            historyWindow = window
        }
        historyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Onboarding

    private func showOnboarding() {
        let hosting = NSHostingController(rootView: OnboardingView(state: appState) { [weak self] in
            self?.appState.settings.hasOnboarded = true
            self?.dismissOnboarding()
            self?.showMainWindow()
        })
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.setContentSize(NSSize(width: 460, height: 520))
        window.center()
        window.isReleasedWhenClosed = false
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var onboardingWindow: NSWindow?
    private func dismissOnboarding() { onboardingWindow?.orderOut(nil); onboardingWindow = nil }

    // MARK: Activation policy

    func applyActivationPolicy() {
        switch appState.settings.menuBarPresence {
        case .dockAndMenuBar, .dockOnly: NSApp.setActivationPolicy(.regular)
        case .menuBarOnly: NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: Hotkeys

    private func registerHotkeys() {
        KeyboardShortcuts.onKeyUp(for: .newSnip) { [weak self] in
            guard let self else { return }
            self.appState.mode = .snip
            self.appState.beginSnip(shape: .rectangle, timer: self.appState.timer)
        }
        KeyboardShortcuts.onKeyUp(for: .newWindowSnip) { [weak self] in
            self?.appState.beginSnip(shape: .window, timer: .none)
        }
        KeyboardShortcuts.onKeyUp(for: .newFullScreenSnip) { [weak self] in
            self?.appState.beginSnip(shape: .fullScreen, timer: .none)
        }
        KeyboardShortcuts.onKeyUp(for: .newFreeformSnip) { [weak self] in
            self?.appState.beginSnip(shape: .freeform, timer: .none)
        }
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak self] in
            self?.appState.toggleRecording()
        }
        KeyboardShortcuts.onKeyUp(for: .openSnipApp) { [weak self] in
            self?.showMainWindow()
        }
        KeyboardShortcuts.onKeyUp(for: .repeatLastCapture) { [weak self] in
            self?.appState.repeatLast()
        }
    }
}
