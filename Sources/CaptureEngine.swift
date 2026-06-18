import ScreenCaptureKit
import AppKit

enum CaptureError: LocalizedError {
    case permissionDenied
    case noDisplay
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Screen Recording permission is required."
        case .noDisplay: "No matching display was found."
        case .captureFailed(let msg): msg
        }
    }
}

/// Screen-recording permission state and helpers (TCC, not a sandbox entitlement).
@MainActor
enum CapturePermission {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Triggers the system prompt the first time; returns the resulting state.
    @discardableResult
    static func request() -> Bool { CGRequestScreenCaptureAccess() }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}

/// Wraps ScreenCaptureKit still-image capture.
struct CaptureEngine {

    static func shareableContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw CaptureError.permissionDenied
        }
    }

    /// Snip's own running application(s), excluded from screenshots so the capture overlay
    /// (dimming + dashed selection border) never bleeds into the grab.
    private static func ownApplications(in content: SCShareableContent) -> [SCRunningApplication] {
        let bundleID = Bundle.main.bundleIdentifier
        return content.applications.filter { $0.bundleIdentifier == bundleID }
    }

    /// Captures a region of a display. `rect` is in points, top-left origin, relative to that display.
    static func captureRegion(_ rect: CGRect,
                              displayID: CGDirectDisplayID,
                              scale: CGFloat,
                              showCursor: Bool) async throws -> NSImage {
        let content = try await shareableContent()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.noDisplay
        }
        let filter = SCContentFilter(display: display,
                                     excludingApplications: ownApplications(in: content),
                                     exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = rect
        config.width = Int(rect.width * scale)
        config.height = Int(rect.height * scale)
        config.scalesToFit = false
        config.showsCursor = showCursor
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.captureResolution = .best
        return try await capture(filter: filter, config: config, pointSize: rect.size)
    }

    /// Captures a full display.
    static func captureDisplay(_ displayID: CGDirectDisplayID,
                               scale: CGFloat,
                               showCursor: Bool) async throws -> NSImage {
        let content = try await shareableContent()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.noDisplay
        }
        let filter = SCContentFilter(display: display,
                                     excludingApplications: ownApplications(in: content),
                                     exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.showsCursor = showCursor
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.captureResolution = .best
        let pointSize = CGSize(width: display.width, height: display.height)
        return try await capture(filter: filter, config: config, pointSize: pointSize)
    }

    /// Captures a single window independent of what's on top of it.
    static func captureWindow(windowID: CGWindowID, scale: CGFloat, showCursor: Bool) async throws -> NSImage {
        let content = try await shareableContent()
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.captureFailed("Window is no longer available.")
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = showCursor
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.captureResolution = .best
        config.ignoreShadowsSingleWindow = true
        return try await capture(filter: filter, config: config, pointSize: window.frame.size)
    }

    private static func capture(filter: SCContentFilter,
                                config: SCStreamConfiguration,
                                pointSize: CGSize) async throws -> NSImage {
        do {
            let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return NSImage(cgImage: cg, size: pointSize)
        } catch {
            throw CaptureError.captureFailed(error.localizedDescription)
        }
    }
}
