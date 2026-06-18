import SwiftUI
import UniformTypeIdentifiers

// MARK: - Capture mode (Snip vs Record)

enum CaptureMode: String, CaseIterable, Identifiable, Codable {
    case snip
    case record

    var id: String { rawValue }
    var title: String { self == .snip ? "Snip" : "Record" }
    var symbol: String { self == .snip ? "camera" : "record.circle" }
}

// MARK: - Capture shape

enum CaptureShape: String, CaseIterable, Identifiable, Codable {
    case rectangle
    case freeform
    case window
    case fullScreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rectangle: "Rectangular Selection"
        case .freeform: "Free-form Selection"
        case .window: "Window Capture"
        case .fullScreen: "Full Screen"
        }
    }

    var symbol: String {
        switch self {
        case .rectangle: "rectangle.on.rectangle"
        case .freeform: "lasso"
        case .window: "macwindow"
        case .fullScreen: "display"
        }
    }
}

// MARK: - Timer delay

enum TimerDelay: Int, CaseIterable, Identifiable, Codable {
    case none = 0
    case three = 3
    case five = 5
    case ten = 10

    var id: Int { rawValue }

    var title: String {
        self == .none ? "No delay" : "\(rawValue) seconds"
    }
}

// MARK: - Output formats

enum ImageFormat: String, CaseIterable, Identifiable, Codable {
    case png, jpeg, heif, tiff
    var id: String { rawValue }
    var title: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .heif: "HEIF"
        case .tiff: "TIFF"
        }
    }
    var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .heif: "heic"
        case .tiff: "tiff"
        }
    }
    var utType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heif: .heic
        case .tiff: .tiff
        }
    }
}

enum VideoFormat: String, CaseIterable, Identifiable, Codable {
    case mov, mp4
    var id: String { rawValue }
    var title: String { self == .mov ? "MOV" : "MP4" }
    var fileExtension: String { rawValue }
    var utType: UTType { self == .mov ? .quickTimeMovie : .mpeg4Movie }
}

enum VideoQuality: String, CaseIterable, Identifiable, Codable {
    case low, medium, high, best
    var id: String { rawValue }

    /// Caps the recording's output height; `nil` keeps the screen's native resolution.
    var targetHeight: Int? {
        switch self {
        case .low: 720
        case .medium: 1080
        case .high: 1440
        case .best: nil
        }
    }

    var title: String {
        switch self {
        case .low: "720p"
        case .medium: "1080p"
        case .high: "1440p"
        case .best: "Native"
        }
    }
}

enum FrameRate: Int, CaseIterable, Identifiable, Codable {
    case fps30 = 30
    case fps60 = 60
    var id: Int { rawValue }
    var title: String { "\(rawValue)fps" }
}

// MARK: - Behavior settings

enum AppearanceSetting: String, CaseIterable, Identifiable, Codable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum MenuBarPresence: String, CaseIterable, Identifiable, Codable {
    case dockAndMenuBar, menuBarOnly, dockOnly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dockAndMenuBar: "Dock + Menu Bar"
        case .menuBarOnly: "Menu Bar Only"
        case .dockOnly: "Dock Only"
        }
    }
}

enum CountdownStyle: String, CaseIterable, Identifiable, Codable {
    case fullScreenDim, subtleHUD, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fullScreenDim: "Full screen dim"
        case .subtleHUD: "Subtle HUD"
        case .none: "None"
        }
    }
}

enum ShowPreviewPolicy: String, CaseIterable, Identifiable, Codable {
    case always, whenRecording, never
    var id: String { rawValue }
    var title: String {
        switch self {
        case .always: "Always"
        case .whenRecording: "When recording"
        case .never: "Never"
        }
    }
}

enum HistoryRetention: Int, CaseIterable, Identifiable, Codable {
    case week = 7
    case month = 30
    case quarter = 90
    case forever = 0
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .week: "7 days"
        case .month: "30 days"
        case .quarter: "90 days"
        case .forever: "Forever"
        }
    }
}

// MARK: - Capture result

enum CaptureKind: String, Codable {
    case image, video
}

struct CaptureItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var kind: CaptureKind
    var fileURL: URL?
    var thumbnailURL: URL?
    var date: Date = Date()
    var pixelWidth: Int
    var pixelHeight: Int
    var duration: Double?   // seconds, for video

    var dimensionText: String { "\(pixelWidth) × \(pixelHeight)" }

    var durationText: String? {
        guard let duration else { return nil }
        let total = Int(duration.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
