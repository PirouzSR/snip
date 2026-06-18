import ScreenCaptureKit
import AVFoundation
import AppKit

/// Records the screen to a file using SCStream + SCRecordingOutput (macOS 15+),
/// which writes directly to disk without a manual AVAssetWriter pipeline.
@MainActor
final class RecordingEngine: NSObject, SCStreamDelegate, SCRecordingOutputDelegate {

    private(set) var isRecording = false
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private(set) var outputURL: URL?
    private(set) var pixelSize: CGSize = .zero
    private var finishContinuation: CheckedContinuation<Void, Never>?

    var onStop: ((URL?) -> Void)?
    var onError: ((Error) -> Void)?

    struct Options {
        var region: CGRect?          // nil = full display, in points top-left relative to display
        var windowID: CGWindowID?    // non-nil = record this single window instead of a display
        var displayID: CGDirectDisplayID
        var scale: CGFloat
        var showCursor: Bool
        var captureMicrophone: Bool
        var format: VideoFormat
        var quality: VideoQuality
        var fps: Int
    }

    func start(_ options: Options) async throws {
        guard !isRecording else { return }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        // Exclude Snip's own windows (hidden main window + recording HUD) from the recording.
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }

        let filter: SCContentFilter
        let regionPoints: CGRect

        if let windowID = options.windowID,
           let window = content.windows.first(where: { $0.windowID == windowID }) {
            filter = SCContentFilter(desktopIndependentWindow: window)
            regionPoints = CGRect(origin: .zero, size: window.frame.size)
        } else {
            guard let display = content.displays.first(where: { $0.displayID == options.displayID }) else {
                throw CaptureError.noDisplay
            }
            filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            regionPoints = options.region ?? CGRect(x: 0, y: 0, width: display.width, height: display.height)
        }

        let config = SCStreamConfiguration()
        if options.windowID == nil, options.region != nil { config.sourceRect = regionPoints }
        var pixelWidth = Int(regionPoints.width * options.scale)
        var pixelHeight = Int(regionPoints.height * options.scale)
        // Downscale to the chosen quality tier (720p/1080p/1440p) if the native grab is larger.
        if let target = options.quality.targetHeight, pixelHeight > target {
            let ratio = Double(target) / Double(pixelHeight)
            pixelWidth = (Int(Double(pixelWidth) * ratio) / 2) * 2   // keep even for H.264
            pixelHeight = target
        }
        config.width = pixelWidth
        config.height = pixelHeight
        config.showsCursor = options.showCursor
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.fps))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 6
        if options.captureMicrophone {
            config.captureMicrophone = true
        }
        pixelSize = CGSize(width: config.width, height: config.height)

        let url = makeOutputURL(format: options.format)
        outputURL = url

        let recConfig = SCRecordingOutputConfiguration()
        recConfig.outputURL = url
        recConfig.outputFileType = options.format == .mov ? .mov : .mp4
        recConfig.videoCodecType = .h264

        let output = SCRecordingOutput(configuration: recConfig, delegate: self)
        recordingOutput = output

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addRecordingOutput(output)
        self.stream = stream

        try await stream.startCapture()
        isRecording = true
    }

    func stop() async {
        guard isRecording, let stream else { return }
        isRecording = false
        // Wait until the recording output has flushed the file before handing it back,
        // otherwise the preview tries to play a not-yet-finalized movie and shows nothing.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            finishContinuation = cont
            Task {
                do { try await stream.stopCapture() } catch { onError?(error) }
                // Safety net if the finish delegate never fires.
                try? await Task.sleep(for: .seconds(3))
                finalizeFinish()
            }
        }
        if let output = recordingOutput {
            try? stream.removeRecordingOutput(output)
        }
        let url = outputURL
        self.stream = nil
        self.recordingOutput = nil
        onStop?(url)
    }

    private func finalizeFinish() {
        finishContinuation?.resume()
        finishContinuation = nil
    }

    /// The configured video save location (defaults to ~/Movies/Captures), created if missing.
    /// Names the file with the shared filename template so recordings match screenshots.
    private func makeOutputURL(format: VideoFormat) -> URL {
        let dir = AppSettings.shared.videoDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = AppSettings.shared.resolvedFilename(mode: "recording")
        return dir.appendingPathComponent("\(name).\(format.fileExtension)")
    }

    // MARK: SCStreamDelegate
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            self.isRecording = false
            self.onError?(error)
            self.finalizeFinish()
        }
    }

    // MARK: SCRecordingOutputDelegate
    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.finalizeFinish() }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        Task { @MainActor in
            self.onError?(error)
            self.finalizeFinish()
        }
    }
}
