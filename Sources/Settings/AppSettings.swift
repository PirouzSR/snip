import SwiftUI
import Observation

/// Central, observable settings store persisted to `UserDefaults`.
/// Views observe it directly; non-view code reads/writes the same instance.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // MARK: General
    var launchAtLogin: Bool { didSet { persist(launchAtLogin, "launchAtLogin"); LoginItem.setEnabled(launchAtLogin) } }
    var keepOnTop: Bool { didSet { persist(keepOnTop, "keepOnTop") } }
    var autoCopyToClipboard: Bool { didSet { persist(autoCopyToClipboard, "autoCopyToClipboard") } }
    var appearance: AppearanceSetting { didSet { persist(appearance.rawValue, "appearance"); applyAppearance() } }
    var menuBarPresence: MenuBarPresence { didSet { persist(menuBarPresence.rawValue, "menuBarPresence") } }

    // MARK: Output
    var saveLocationBookmark: Data? { didSet { defaults.set(saveLocationBookmark, forKey: "saveLocationBookmark") } }
    var autoSave: Bool { didSet { persist(autoSave, "autoSave") } }
    var filenameTemplate: String { didSet { persist(filenameTemplate, "filenameTemplate") } }
    var imageFormat: ImageFormat { didSet { persist(imageFormat.rawValue, "imageFormat") } }
    var jpegQuality: Double { didSet { persist(jpegQuality, "jpegQuality") } }
    var videoFormat: VideoFormat { didSet { persist(videoFormat.rawValue, "videoFormat") } }
    var videoQuality: VideoQuality { didSet { persist(videoQuality.rawValue, "videoQuality") } }
    var frameRate: FrameRate { didSet { persist(frameRate.rawValue, "frameRate") } }

    // MARK: Behavior
    var countdownStyle: CountdownStyle { didSet { persist(countdownStyle.rawValue, "countdownStyle") } }
    var defaultShape: CaptureShape { didSet { persist(defaultShape.rawValue, "defaultShape") } }
    var defaultTimer: TimerDelay { didSet { persist(defaultTimer.rawValue, "defaultTimer") } }
    var playSound: Bool { didSet { persist(playSound, "playSound") } }
    var showPreview: ShowPreviewPolicy { didSet { persist(showPreview.rawValue, "showPreview") } }

    // MARK: History
    var saveHistory: Bool { didSet { persist(saveHistory, "saveHistory") } }
    var historyRetention: HistoryRetention { didSet { persist(historyRetention.rawValue, "historyRetention") } }

    // MARK: Onboarding / counters
    var hasOnboarded: Bool { didSet { persist(hasOnboarded, "hasOnboarded") } }
    var captureIndex: Int { didSet { persist(captureIndex, "captureIndex") } }

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "autoCopyToClipboard": true,
            "autoSave": true,
            "filenameTemplate": "Snip {date} {time}",
            "imageFormat": ImageFormat.png.rawValue,
            "jpegQuality": 0.9,
            "videoFormat": VideoFormat.mov.rawValue,
            "videoQuality": VideoQuality.high.rawValue,
            "frameRate": FrameRate.fps60.rawValue,
            "countdownStyle": CountdownStyle.fullScreenDim.rawValue,
            "defaultShape": CaptureShape.rectangle.rawValue,
            "defaultTimer": TimerDelay.none.rawValue,
            "showPreview": ShowPreviewPolicy.whenRecording.rawValue,
            "saveHistory": true,
            "historyRetention": HistoryRetention.month.rawValue,
            "menuBarPresence": MenuBarPresence.dockAndMenuBar.rawValue,
            "appearance": AppearanceSetting.system.rawValue,
            "captureIndex": 1,
        ])

        launchAtLogin = d.bool(forKey: "launchAtLogin")
        keepOnTop = d.bool(forKey: "keepOnTop")
        autoCopyToClipboard = d.bool(forKey: "autoCopyToClipboard")
        appearance = AppearanceSetting(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        menuBarPresence = MenuBarPresence(rawValue: d.string(forKey: "menuBarPresence") ?? "") ?? .dockAndMenuBar

        saveLocationBookmark = d.data(forKey: "saveLocationBookmark")
        autoSave = d.bool(forKey: "autoSave")
        filenameTemplate = d.string(forKey: "filenameTemplate") ?? "Snip {date} {time}"
        imageFormat = ImageFormat(rawValue: d.string(forKey: "imageFormat") ?? "") ?? .png
        jpegQuality = d.double(forKey: "jpegQuality")
        videoFormat = VideoFormat(rawValue: d.string(forKey: "videoFormat") ?? "") ?? .mov
        videoQuality = VideoQuality(rawValue: d.string(forKey: "videoQuality") ?? "") ?? .high
        frameRate = FrameRate(rawValue: d.integer(forKey: "frameRate")) ?? .fps60

        countdownStyle = CountdownStyle(rawValue: d.string(forKey: "countdownStyle") ?? "") ?? .fullScreenDim
        defaultShape = CaptureShape(rawValue: d.string(forKey: "defaultShape") ?? "") ?? .rectangle
        defaultTimer = TimerDelay(rawValue: d.integer(forKey: "defaultTimer")) ?? .none
        playSound = d.bool(forKey: "playSound")
        showPreview = ShowPreviewPolicy(rawValue: d.string(forKey: "showPreview") ?? "") ?? .whenRecording

        saveHistory = d.bool(forKey: "saveHistory")
        historyRetention = HistoryRetention(rawValue: d.integer(forKey: "historyRetention")) ?? .month

        hasOnboarded = d.bool(forKey: "hasOnboarded")
        captureIndex = d.integer(forKey: "captureIndex")
    }

    private func persist(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }

    func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    // MARK: Save location

    /// Resolves the chosen save directory, defaulting to ~/Pictures/Screenshots,
    /// creating it on demand.
    var saveDirectory: URL {
        if let bookmark = saveLocationBookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [],
                                  relativeTo: nil, bookmarkDataIsStale: &stale) {
                return url
            }
        }
        return defaultSaveDirectory
    }

    /// ~/Pictures/Screenshots, created if missing.
    var defaultSaveDirectory: URL {
        let fm = FileManager.default
        let pictures = fm.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        let dir = pictures.appendingPathComponent("Screenshots", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    func setSaveDirectory(_ url: URL) {
        saveLocationBookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Builds a filename (without extension) from the template tokens.
    func resolvedFilename(mode: String) -> String {
        let now = Date()
        let dateFmt = DateFormatter(); dateFmt.dateFormat = "yyyy-MM-dd"
        let timeFmt = DateFormatter(); timeFmt.dateFormat = "HH-mm-ss"
        var name = filenameTemplate
        name = name.replacingOccurrences(of: "{date}", with: dateFmt.string(from: now))
        name = name.replacingOccurrences(of: "{time}", with: timeFmt.string(from: now))
        name = name.replacingOccurrences(of: "{index}", with: String(captureIndex))
        name = name.replacingOccurrences(of: "{mode}", with: mode)
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Snip \(Int(now.timeIntervalSince1970))" : trimmed
    }
}
