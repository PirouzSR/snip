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
        ZStack {
            if value.style == .fullScreenDim {
                Color.black.opacity(0.45).ignoresSafeArea()
            }
            numberView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var numberView: some View {
        if value.style == .fullScreenDim {
            Text("\(value.number)")
                .font(.system(size: 160, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText(countsDown: true))
                .id(value.number)
        } else {
            Text("\(value.number)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 96, height: 96)
                .glassEffect(.regular, in: .circle)
                .contentTransition(.numericText(countsDown: true))
                .id(value.number)
        }
    }
}
