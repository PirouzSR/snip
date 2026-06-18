import SwiftUI
import AppKit

/// Shows the pre-capture timer countdown according to the user's `CountdownStyle`:
/// a full-screen dim with a big number, a small floating HUD, or nothing.
@MainActor
final class CountdownOverlay {
    private var panel: NSPanel?
    private let value = CountdownValue()

    func begin(style: CountdownStyle, seconds: Int) {
        guard style != .none, panel == nil, let screen = NSScreen.main else { return }
        value.style = style
        value.number = seconds

        let panel = NSPanel(contentRect: screen.frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: CountdownView(value: value))
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func update(seconds: Int) { value.number = seconds }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}

@MainActor
@Observable
private final class CountdownValue {
    var number: Int = 0
    var style: CountdownStyle = .fullScreenDim
}

private struct CountdownView: View {
    @Bindable var value: CountdownValue

    var body: some View {
        if value.style == .fullScreenDim {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()
                Text("\(value.number)")
                    .font(.system(size: 160, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(countsDown: true))
                    .id(value.number)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Subtle HUD: no dimming, a small pill anchored to the bottom-center.
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "timer").font(.system(size: 16, weight: .semibold))
                    Text("\(value.number)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .id(value.number)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 120)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
