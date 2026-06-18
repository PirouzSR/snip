import SwiftUI
import AppKit
import ScreenCaptureKit
import Observation

/// Root coordinator: owns capture/record flow, the preview state, and window intents.
@MainActor
@Observable
final class AppState {
    let settings = AppSettings.shared
    let history = HistoryStore.shared
    let recorder = RecordingEngine()

    var mode: CaptureMode = .snip
    var shape: CaptureShape
    var timer: TimerDelay

    // Preview state
    var currentImage: NSImage?
    var currentVideoURL: URL?
    var previewKind: CaptureKind?
    var markupActive = false

    /// On-disk file backing the current preview (for Delete). Saved screenshot or recording.
    var currentCaptureURL: URL?

    /// A lightweight (downscaled) copy of the most recent snip, kept resident for the
    /// menu-bar preview. Full-resolution pixels live on disk in the history store, so we
    /// don't hold a multi-megabyte bitmap in memory while idle.
    var lastCapturePreview: NSImage?

    var isMainWindowVisible: () -> Bool = { false }

    /// Full-resolution image for menu-bar actions: the live preview if present, otherwise
    /// the on-disk copy of the latest history item, falling back to the small preview.
    func latestFullResImage() -> NSImage? {
        if let currentImage { return currentImage }
        if let url = history.items.first(where: { $0.kind == .image })?.fileURL,
           let image = NSImage(contentsOf: url) { return image }
        return lastCapturePreview
    }

    // Transient UI state
    var isCapturing = false
    var countdownValue: Int?
    var recordingElapsed: TimeInterval = 0
    var errorMessage: String?
    var showError = false

    private var recordingTimer: Timer?
    private var lastResult: SelectionResult?

    // Window intents handled by the AppDelegate
    var requestShowMainWindow: (() -> Void)?
    var requestActivateApp: (() -> Void)?

    var hasPreview: Bool { previewKind != nil }
    /// Observable mirror of the recorder state so SwiftUI updates when recording starts/stops.
    private(set) var isRecording = false

    init() {
        let s = AppSettings.shared
        shape = s.defaultShape
        timer = s.defaultTimer
        recorder.onStop = { [weak self] url in self?.handleRecordingStopped(url) }
        recorder.onError = { [weak self] err in
            self?.isRecording = false
            self?.present(error: err.localizedDescription)
        }
    }

    // MARK: Primary actions

    func primaryAction() {
        switch mode {
        case .snip: beginSnip(shape: shape, timer: timer)
        case .record:
            if isRecording { Task { await stopRecording() } } else { beginRecording() }
        }
    }

    func beginSnip(shape: CaptureShape, timer: TimerDelay) {
        guard ensurePermission() else { return }
        guard !OverlayController.shared.isActive, !isCapturing else { return }
        self.shape = shape
        Task { await runCountdownThenOverlay(shape: shape, delay: timer.rawValue) }
    }

    private func runCountdownThenOverlay(shape: CaptureShape, delay: Int) async {
        if delay > 0 {
            for remaining in stride(from: delay, through: 1, by: -1) {
                countdownValue = remaining
                try? await Task.sleep(for: .seconds(1))
            }
            countdownValue = nil
        }
        presentOverlay(shape: shape)
    }

    private func presentOverlay(shape: CaptureShape) {
        isCapturing = true
        OverlayController.shared.begin(shape: shape) { [weak self] result in
            guard let self else { return }
            self.isCapturing = false
            guard let result else { return }
            self.lastResult = result
            Task { await self.handle(result) }
        }
    }

    // MARK: Capture execution

    private func handle(_ result: SelectionResult) async {
        let showCursor = false   // cursor is never included in captures
        do {
            let image: NSImage
            var markup = false
            switch result {
            case .region(let rect, let screen, let withMarkup):
                markup = withMarkup
                image = try await CaptureEngine.captureRegion(rect.standardizedNonNegative,
                                                              displayID: screen.displayID,
                                                              scale: screen.backingScaleFactor,
                                                              showCursor: showCursor)
            case .freeform(let path, let bounds, let screen, let withMarkup):
                markup = withMarkup
                let full = try await CaptureEngine.captureRegion(bounds.standardizedNonNegative,
                                                                 displayID: screen.displayID,
                                                                 scale: screen.backingScaleFactor,
                                                                 showCursor: showCursor)
                image = maskFreeform(full, path: path, bounds: bounds.standardizedNonNegative,
                                     scale: screen.backingScaleFactor) ?? full
            case .window(let window, let withMarkup):
                markup = withMarkup
                let windowID = window.windowID
                let scale = NSScreen.main?.backingScaleFactor ?? 2
                image = try await CaptureEngine.captureWindow(windowID: windowID, scale: scale, showCursor: showCursor)
            case .display(let screen, let withMarkup):
                markup = withMarkup
                image = try await CaptureEngine.captureDisplay(screen.displayID,
                                                               scale: screen.backingScaleFactor,
                                                               showCursor: showCursor)
            }
            finalizeImage(image, withMarkup: markup)
        } catch {
            present(error: error.localizedDescription)
        }
    }

    func finalizeImage(_ image: NSImage, withMarkup: Bool) {
        currentImage = image
        lastCapturePreview = image.downscaled(maxDimension: 512)
        currentVideoURL = nil
        previewKind = .image
        markupActive = withMarkup

        if settings.autoCopyToClipboard { Clipboard.copy(image: image) }

        var savedURL: URL?
        if settings.autoSave { savedURL = saveImageToDisk(image) }
        history.add(image: image, fileURL: savedURL)
        currentCaptureURL = history.items.first?.fileURL
        settings.captureIndex += 1

        if settings.playSound { NSSound(named: "Funk")?.play() }

        // Surface the window only when configured to, when it's already open, or when the
        // user asked to mark up. Otherwise the snip stays silent and we release the
        // full-resolution bitmap — it remains available on disk via the history store.
        if withMarkup || settings.showPreview == .always || isMainWindowVisible() {
            requestShowMainWindow?()
        } else {
            currentImage = nil
            previewKind = nil
        }
    }

    @discardableResult
    func saveImageToDisk(_ image: NSImage) -> URL? {
        let dir = settings.saveDirectory
        let name = settings.resolvedFilename(mode: "snip")
        let url = dir.appendingPathComponent("\(name).\(settings.imageFormat.fileExtension)")
        guard let data = image.data(for: settings.imageFormat, jpegQuality: settings.jpegQuality) else { return nil }
        do { try data.write(to: url); return url } catch {
            present(error: "Couldn't save: \(error.localizedDescription)"); return nil
        }
    }

    // MARK: Recording

    func beginRecording() {
        guard ensurePermission() else { return }
        guard let screen = NSScreen.main else { return }
        Task {
            do {
                let opts = RecordingEngine.Options(
                    region: nil,
                    displayID: screen.displayID,
                    scale: screen.backingScaleFactor,
                    showCursor: false,
                    captureMicrophone: micEnabled,
                    format: settings.videoFormat,
                    quality: settings.videoQuality,
                    fps: settings.frameRate.rawValue)
                try await recorder.start(opts)
                isRecording = true
                startRecordingTimer()
            } catch {
                isRecording = false
                present(error: error.localizedDescription)
            }
        }
    }

    var micEnabled = false

    func stopRecording() async {
        await recorder.stop()
    }

    func toggleRecording() {
        if isRecording { Task { await stopRecording() } } else { mode = .record; beginRecording() }
    }

    private func handleRecordingStopped(_ url: URL?) {
        isRecording = false
        stopRecordingTimer()
        guard let url else { return }
        currentVideoURL = url
        currentCaptureURL = url
        currentImage = nil
        previewKind = .video
        history.add(videoURL: url)
        if settings.showPreview != .never { requestShowMainWindow?() }
    }

    private func startRecordingTimer() {
        recordingElapsed = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recordingElapsed += 1 }
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate(); recordingTimer = nil
    }

    var recordingTimeText: String {
        let total = Int(recordingElapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: Repeat last

    func repeatLast() {
        guard let result = lastResult else { primaryAction(); return }
        Task { await handle(result) }
    }

    // MARK: Menu-bar actions (operate on the last capture)

    func copyLastCapture() {
        if let image = currentImage { Clipboard.copy(image: image); return }
        if let url = currentVideoURL { Clipboard.copy(fileURL: url); return }
        guard let last = history.items.first else { return }
        if last.kind == .image, let url = last.fileURL, let image = NSImage(contentsOf: url) {
            Clipboard.copy(image: image)
        } else if let url = last.fileURL {
            Clipboard.copy(fileURL: url)
        }
    }

    /// Opens the main window with the last snip in markup mode.
    func editLastCapture() {
        guard let image = latestFullResImage() else { return }
        currentImage = image
        currentVideoURL = nil
        previewKind = .image
        markupActive = true
        requestShowMainWindow?()
    }

    func saveLastCapture() {
        guard let image = latestFullResImage() else { return }
        currentImage = image
        previewKind = .image
        presentSavePanel()
    }

    // MARK: Preview actions

    func copyCurrent() {
        if let image = currentImage { Clipboard.copy(image: image) }
        else if let url = currentVideoURL { Clipboard.copy(fileURL: url) }
    }

    /// Clear: remove the snapshot from the app preview only. The saved file and history stay.
    func discardCurrent() {
        currentImage = nil
        currentVideoURL = nil
        currentCaptureURL = nil
        previewKind = nil
        markupActive = false
    }

    /// Delete: remove the saved file from disk and its history entry, then clear the preview.
    func deleteCurrent() {
        if let url = currentCaptureURL {
            try? FileManager.default.removeItem(at: url)
            if let item = history.items.first(where: { $0.fileURL == url }) {
                history.delete(item)
            }
        }
        discardCurrent()
    }

    /// Opens the most recent capture (image or video) in the default app.
    func openLastCapture() {
        if let url = currentVideoURL ?? history.items.first?.fileURL {
            NSWorkspace.shared.open(url)
        }
    }

    /// Presents a save panel for the current image with format options.
    func presentSavePanel() {
        guard let image = currentImage else {
            if let url = currentVideoURL { saveVideoAs(url) }
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [ImageFormat.png.utType, .jpeg, .heic, .tiff]
        panel.nameFieldStringValue = "\(settings.resolvedFilename(mode: "snip")).\(settings.imageFormat.fileExtension)"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            let fmt = ImageFormat.allCases.first { $0.fileExtension == url.pathExtension.lowercased() } ?? settings.imageFormat
            if let data = image.data(for: fmt, jpegQuality: settings.jpegQuality) {
                try? data.write(to: url)
            }
        }
    }

    private func saveVideoAs(_ source: URL) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [settings.videoFormat.utType]
        panel.nameFieldStringValue = "\(settings.resolvedFilename(mode: "recording")).\(settings.videoFormat.fileExtension)"
        if panel.runModal() == .OK, let dest = panel.url {
            try? FileManager.default.copyItem(at: source, to: dest)
        }
    }

    // MARK: Permission

    @discardableResult
    private func ensurePermission() -> Bool {
        if CapturePermission.isGranted { return true }
        CapturePermission.request()
        if !CapturePermission.isGranted {
            present(error: "Snip needs Screen Recording permission. Open System Settings ▸ Privacy & Security ▸ Screen Recording to enable it.")
            CapturePermission.openSystemSettings()
            return false
        }
        return true
    }

    private func present(error: String) {
        errorMessage = error
        showError = true
    }

    // MARK: Freeform masking

    private func maskFreeform(_ image: NSImage, path: [CGPoint], bounds: CGRect, scale: CGFloat) -> NSImage? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Build the clip path in pixel space, flipping Y for CoreGraphics' bottom-left origin.
        let cgPath = CGMutablePath()
        let mapped = path.map { p in
            CGPoint(x: (p.x - bounds.minX) * scale,
                    y: (bounds.height - (p.y - bounds.minY)) * scale)
        }
        if let first = mapped.first {
            cgPath.move(to: first)
            for pt in mapped.dropFirst() { cgPath.addLine(to: pt) }
            cgPath.closeSubpath()
        }
        ctx.addPath(cgPath)
        ctx.clip()
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let masked = ctx.makeImage() else { return nil }
        return NSImage(cgImage: masked, size: image.size)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
    }
}
