import SwiftUI
import AppKit

/// A 50%-opacity outline drawn around the region being recorded, so the user can see exactly
/// what's captured. It lives in Snip's own (excluded) app, so it never appears in the recording.
@MainActor
final class RecordingBoundsOverlay {
    private var panel: NSPanel?

    /// `localRect` is in the selection overlay's screen-local, top-left coordinate space.
    func show(localRect: CGRect, on screen: NSScreen) {
        dismiss()
        // Convert screen-local (top-left) → global AppKit (bottom-left) panel frame.
        let globalX = screen.frame.minX + localRect.minX
        let globalY = screen.frame.maxY - localRect.maxY
        let frame = CGRect(x: globalX, y: globalY, width: localRect.width, height: localRect.height)

        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: RecordingBoundsView())
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct RecordingBoundsView: View {
    var body: some View {
        Rectangle()
            .strokeBorder(Color.red.opacity(0.5), lineWidth: 3)
    }
}
