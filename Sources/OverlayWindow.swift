import SwiftUI
import AppKit
import ScreenCaptureKit
import Observation

/// What the user selected in the capture overlay.
enum SelectionResult {
    case region(rect: CGRect, screen: NSScreen, withMarkup: Bool)
    case freeform(path: [CGPoint], boundingRect: CGRect, screen: NSScreen, withMarkup: Bool)
    case window(SCWindow, withMarkup: Bool)
    case display(NSScreen, withMarkup: Bool)
}

/// Shared state across all per-screen overlay panels for one capture session.
@MainActor
@Observable
final class SelectionCoordinator {
    enum Phase { case crosshair, dragging, confirmed }

    let shape: CaptureShape
    var phase: Phase = .crosshair

    var activeScreen: NSScreen?
    var selectionRect: CGRect = .zero        // local to activeScreen, top-left origin, points
    var freeformPoints: [CGPoint] = []
    var cursorLocation: CGPoint = .zero       // local to activeScreen

    // Window mode
    var windows: [SCWindow] = []
    var hoveredWindow: SCWindow?

    private let completion: (SelectionResult?) -> Void
    private var finished = false

    init(shape: CaptureShape, completion: @escaping (SelectionResult?) -> Void) {
        self.shape = shape
        self.completion = completion
    }

    func confirm(withMarkup: Bool) {
        guard !finished else { return }
        switch shape {
        case .rectangle:
            guard let screen = activeScreen, selectionRect.width > 2, selectionRect.height > 2 else { cancel(); return }
            finish(.region(rect: selectionRect, screen: screen, withMarkup: withMarkup))
        case .freeform:
            guard let screen = activeScreen, freeformPoints.count > 2 else { cancel(); return }
            let bounds = boundingRect(of: freeformPoints)
            finish(.freeform(path: freeformPoints, boundingRect: bounds, screen: screen, withMarkup: withMarkup))
        case .window:
            guard let win = hoveredWindow else { cancel(); return }
            finish(.window(win, withMarkup: withMarkup))
        case .fullScreen:
            guard let screen = activeScreen ?? NSScreen.main else { cancel(); return }
            finish(.display(screen, withMarkup: withMarkup))
        }
    }

    func cancel() {
        guard !finished else { return }
        finished = true
        completion(nil)
    }

    private func finish(_ result: SelectionResult) {
        finished = true
        completion(result)
    }

    private func boundingRect(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// Borderless panel that can become key (so it receives keyboard events for Esc/Return).
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Presents transparent fullscreen overlays across all displays and reports the selection.
@MainActor
final class OverlayController {
    static let shared = OverlayController()

    private var panels: [OverlayPanel] = []
    private var coordinator: SelectionCoordinator?
    private var keyMonitor: Any?

    var isActive: Bool { !panels.isEmpty }

    /// Maps each on-screen window number to its front-to-back index (0 = front-most),
    /// using the window-server z-order that `SCShareableContent` doesn't guarantee.
    static func frontToBackOrder() -> [CGWindowID: Int] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        var order: [CGWindowID: Int] = [:]
        for (index, info) in infos.enumerated() {
            if let number = info[kCGWindowNumber as String] as? CGWindowID {
                order[number] = index
            }
        }
        return order
    }

    func begin(shape: CaptureShape, completion: @escaping (SelectionResult?) -> Void) {
        guard panels.isEmpty else { return }

        let coordinator = SelectionCoordinator(shape: shape) { [weak self] result in
            self?.teardown()
            completion(result)
        }
        self.coordinator = coordinator

        if shape == .window {
            Task {
                let content = try? await CaptureEngine.shareableContent()
                let ownPID = ProcessInfo.processInfo.processIdentifier
                let filtered = (content?.windows ?? []).filter { window in
                    // Only normal, on-screen application windows (layer 0). This excludes
                    // Electron/AppKit overlay panels (autocomplete popovers, shadows, status
                    // overlays) that otherwise sit on top and get captured instead of the
                    // real window — the cause of blank captures for apps like Cursor.
                    window.isOnScreen
                        && window.windowLayer == 0
                        && window.frame.width > 80 && window.frame.height > 80
                        && window.owningApplication?.processID != ownPID
                        && (window.title?.isEmpty == false || window.owningApplication != nil)
                }
                // Sort front-to-back using the real on-screen z-order so the window directly
                // under the cursor (e.g. Finder in front of Cursor) wins the hit test.
                let order = Self.frontToBackOrder()
                coordinator.windows = filtered.sorted { a, b in
                    (order[a.windowID] ?? .max) < (order[b.windowID] ?? .max)
                }
            }
        }

        for screen in NSScreen.screens {
            let panel = OverlayPanel(contentRect: screen.frame,
                                     styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.ignoresMouseEvents = false
            let root = SelectionView(coordinator: coordinator, screen: screen)
                .ignoresSafeArea()
            panel.contentView = NSHostingView(rootView: root)
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            panels.append(panel)
        }

        panels.first?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.push()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let coordinator = self?.coordinator else { return event }
            switch event.keyCode {
            case 53: // Escape
                coordinator.cancel(); return nil
            case 36, 76: // Return / keypad Enter
                coordinator.confirm(withMarkup: false); return nil
            default:
                return event
            }
        }

        // Full screen mode captures immediately if there is only one display.
        if shape == .fullScreen, NSScreen.screens.count == 1 {
            coordinator.activeScreen = NSScreen.main
            coordinator.confirm(withMarkup: false)
        }
    }

    private func teardown() {
        NSCursor.pop()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
        coordinator = nil
    }
}
