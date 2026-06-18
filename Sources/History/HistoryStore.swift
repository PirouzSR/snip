import SwiftUI
import AppKit
import AVFoundation
import Observation

/// Persists capture metadata + thumbnails to Application Support and exposes them to the UI.
@MainActor
@Observable
final class HistoryStore {
    static let shared = HistoryStore()

    private(set) var items: [CaptureItem] = []

    private let fm = FileManager.default

    /// ~/Library/Application Support/Snip/History/
    private var historyDir: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Snip/History", isDirectory: true)
    }
    private var metadataURL: URL { historyDir.appendingPathComponent("history.json") }
    private var thumbsDir: URL { historyDir.appendingPathComponent("thumbnails", isDirectory: true) }
    private var imagesDir: URL { historyDir.appendingPathComponent("images", isDirectory: true) }

    private init() {
        try? fm.createDirectory(at: thumbsDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        load()
        pruneExpired()
    }

    // MARK: Public API

    func add(image: NSImage, fileURL: URL?) {
        guard AppSettings.shared.saveHistory else { return }
        let px = image.pixelSize
        var item = CaptureItem(kind: .image, fileURL: fileURL,
                               pixelWidth: Int(px.width), pixelHeight: Int(px.height))
        // Keep a full-resolution copy so the snip can be reopened/edited even when the
        // user hasn't enabled auto-save to their own folder (Snipping Tool keeps a history).
        if fileURL == nil, let data = image.pngData() {
            let url = imagesDir.appendingPathComponent("\(item.id.uuidString).png")
            if (try? data.write(to: url, options: .atomic)) != nil { item.fileURL = url }
        }
        item.thumbnailURL = writeThumbnail(image, id: item.id)
        items.insert(item, at: 0)
        save()
    }

    func add(videoURL: URL) {
        guard AppSettings.shared.saveHistory else { return }
        Task { await addVideo(videoURL) }
    }

    private func addVideo(_ url: URL) async {
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) }
        var size = CGSize.zero
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let natural = try? await track.load(.naturalSize) {
            size = natural
        }
        var item = CaptureItem(kind: .video, fileURL: url,
                               pixelWidth: Int(size.width), pixelHeight: Int(size.height))
        item.duration = duration
        if let poster = await videoPoster(asset) {
            item.thumbnailURL = writeThumbnail(poster, id: item.id)
        }
        items.insert(item, at: 0)
        save()
    }

    func delete(_ item: CaptureItem) {
        removeFiles(for: item)
        items.removeAll { $0.id == item.id }
        save()
    }

    func clearAll() {
        for item in items { removeFiles(for: item) }
        items.removeAll()
        save()
    }

    /// Removes the thumbnail and any internally-owned full-resolution copy (not user files).
    private func removeFiles(for item: CaptureItem) {
        if let t = item.thumbnailURL { try? fm.removeItem(at: t) }
        if let f = item.fileURL, f.path.hasPrefix(imagesDir.path) { try? fm.removeItem(at: f) }
    }

    func thumbnail(for item: CaptureItem) -> NSImage? {
        guard let url = item.thumbnailURL, let img = NSImage(contentsOf: url) else { return nil }
        return img
    }

    /// Total bytes used by thumbnails and internal full-resolution copies on disk.
    var storageUsed: Int64 {
        [thumbsDir, imagesDir].reduce(0) { total, dir in
            let urls = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            return total + urls.reduce(0) { sum, url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return sum + Int64(size)
            }
        }
    }

    var storageUsedText: String {
        ByteCountFormatter.string(fromByteCount: storageUsed, countStyle: .file)
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([CaptureItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }

    private func pruneExpired() {
        let retention = AppSettings.shared.historyRetention
        guard retention != .forever else { return }
        let cutoff = Date().addingTimeInterval(-Double(retention.rawValue) * 86_400)
        let expired = items.filter { $0.date < cutoff }
        // Only auto-saved screenshots inside our managed folder are removed — never files
        // the user placed there, and never on manual delete/clear.
        let managedDir = AppSettings.shared.defaultSaveDirectory.path
        for item in expired {
            removeFiles(for: item)
            if let f = item.fileURL, f.path.hasPrefix(managedDir) { try? fm.removeItem(at: f) }
        }
        items.removeAll { $0.date < cutoff }
        save()
    }

    // MARK: Thumbnails

    private func writeThumbnail(_ image: NSImage, id: UUID) -> URL? {
        let maxDim: CGFloat = 480
        let size = image.size
        let scale = min(1, maxDim / max(size.width, size.height))
        let target = NSSize(width: size.width * scale, height: size.height * scale)
        let thumb = NSImage(size: target)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: target),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy, fraction: 1)
        thumb.unlockFocus()
        guard let data = thumb.pngData() else { return nil }
        let url = thumbsDir.appendingPathComponent("\(id.uuidString).png")
        try? data.write(to: url, options: .atomic)
        return url
    }

    private func videoPoster(_ asset: AVURLAsset) async -> NSImage? {
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        guard let result = try? await gen.image(at: CMTime(seconds: 0.1, preferredTimescale: 600)) else {
            return nil
        }
        return NSImage(cgImage: result.image, size: .zero)
    }
}
