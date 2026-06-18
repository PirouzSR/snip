import SwiftUI
import AppKit

/// Reusable floating panel with a native Liquid Glass background (macOS 26 `NSGlassEffectView`).
final class GlassPanel<Content: View>: NSPanel {

    private let hosting: NSHostingView<Content>

    init(content: Content, size: NSSize) {
        hosting = NSHostingView(rootView: content)
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                   backing: .buffered, defer: false)

        isFloatingPanel = false
        level = .floating
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        // Drag only by the titlebar/toolbar strip; dragging content (e.g. the markup
        // canvas) must not move the window.
        isMovableByWindowBackground = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
        glass.cornerRadius = 16
        glass.contentView = hosting
        hosting.translatesAutoresizingMaskIntoConstraints = false
        contentView = glass
        if let container = contentView {
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: container.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }

        repositionTrafficLights()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func update(content: Content) { hosting.rootView = content }

    /// Animate the panel height while keeping the top edge anchored.
    func setHeight(_ height: CGFloat, animated: Bool) {
        var frame = self.frame
        let delta = height - frame.height
        frame.origin.y -= delta
        frame.size.height = height
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(frame, display: true)
            }
        } else {
            setFrame(frame, display: true)
        }
    }

    private func repositionTrafficLights() {
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(type)?.isHidden = false
        }
    }
}
