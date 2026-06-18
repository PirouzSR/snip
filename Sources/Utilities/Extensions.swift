import SwiftUI
import AppKit

// MARK: - Reduce motion

enum Motion {
    /// True when the system asks apps to minimize animation.
    @MainActor static var reduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Returns the given animation, or a plain opacity-friendly fade when reduce-motion is on.
    @MainActor static func animation(_ animation: Animation) -> Animation? {
        reduced ? .easeInOut(duration: 0.12) : animation
    }
}

// MARK: - NSImage <-> CGImage

extension NSImage {
    var cgImage: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    /// Pixel dimensions of the first bitmap representation, falling back to point size.
    var pixelSize: CGSize {
        if let rep = representations.first {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return size
    }

    func pngData() -> Data? { bitmapData(for: .png) }

    /// Returns a downscaled copy whose longest side is at most `maxDimension` pixels, drawn
    /// once through a CoreGraphics context. Used to keep a lightweight preview resident
    /// instead of a full-resolution bitmap. Unlike `lockFocus`, this produces deterministic
    /// pixel dimensions (no surprise 2× Retina backing), so the retained copy stays small.
    func downscaled(maxDimension: CGFloat) -> NSImage {
        guard let cg = cgImage, let scaled = cg.resized(maxPixels: maxDimension) else { return self }
        return NSImage(cgImage: scaled, size: NSSize(width: scaled.width, height: scaled.height))
    }

    func data(for format: ImageFormat, jpegQuality: Double = 0.9) -> Data? {
        switch format {
        case .png: bitmapData(for: .png)
        case .jpeg: bitmapData(for: .jpeg, properties: [.compressionFactor: jpegQuality])
        case .heif: heicData(quality: jpegQuality)
        case .tiff: tiffRepresentation
        }
    }

    private func bitmapData(for type: NSBitmapImageRep.FileType,
                            properties: [NSBitmapImageRep.PropertyKey: Any] = [:]) -> Data? {
        guard let cg = cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: type, properties: properties)
    }

    private func heicData(quality: Double) -> Data? {
        guard let cg = cgImage else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.heic" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}

// MARK: - CGImage downscaling

extension CGImage {
    /// Returns a copy scaled so its longest side is at most `maxPixels`, preserving aspect
    /// ratio; returns `self` when already within bounds. A single `CGContext` draw avoids the
    /// offscreen window backing — and the ambiguous backing scale — of `NSImage.lockFocus`.
    func resized(maxPixels: CGFloat) -> CGImage? {
        let longest = CGFloat(max(width, height))
        guard longest > maxPixels, longest > 0 else { return self }
        let ratio = maxPixels / longest
        let w = max(Int((CGFloat(width) * ratio).rounded()), 1)
        let h = max(Int((CGFloat(height) * ratio).rounded()), 1)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(self, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
}

// MARK: - Clipboard

enum Clipboard {
    @MainActor static func copy(image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }

    @MainActor static func copy(fileURL: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([fileURL as NSURL])
    }
}

// MARK: - Geometry helpers

extension CGRect {
    /// Normalizes a rect that may have negative width/height (from a drag in any direction).
    var standardizedNonNegative: CGRect {
        CGRect(x: min(minX, maxX), y: min(minY, maxY),
               width: abs(width), height: abs(height)).standardized
    }
}

// MARK: - Coordinate conversion

enum ScreenGeometry {
    /// Converts a rect in a screen's local (bottom-left, point) space into the global
    /// CoreGraphics display space (top-left origin) used by ScreenCaptureKit source rects.
    static func cgDisplayRect(localRect: CGRect, on screen: NSScreen) -> CGRect {
        let frame = screen.frame
        // Flip Y relative to the primary screen (the one at index 0 defines global top).
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? frame.maxY
        let globalX = frame.minX + localRect.minX
        let globalTopY = primaryHeight - (frame.minY + localRect.maxY)
        return CGRect(x: globalX, y: globalTopY, width: localRect.width, height: localRect.height)
    }
}
