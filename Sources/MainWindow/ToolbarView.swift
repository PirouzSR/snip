import SwiftUI
import KeyboardShortcuts

struct ToolbarView: View {
    @Bindable var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            // Leave room for the traffic lights.
            Spacer().frame(width: 64)

            branding

            NewButton(state: state)

            ModeSegments(mode: $state.mode)

            if state.mode == .snip {
                ShapeMenu(shape: $state.shape)
                TimerMenu(timer: $state.timer)
            } else {
                MicToggle(state: state)
            }

            Spacer(minLength: 0)

            OverflowMenu(state: state)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
    }

    private var branding: some View {
        HStack(spacing: 6) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 16))
                .foregroundStyle(.tint)
            Text("Snip")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - New (primary CTA)

private struct NewButton: View {
    @Bindable var state: AppState
    @State private var pressed = false

    var body: some View {
        Button(action: { state.primaryAction() }) {
            HStack(spacing: 4) {
                if let count = state.countdownValue {
                    Text("\(count)…").font(.system(size: 13, weight: .semibold))
                } else {
                    Image(systemName: state.mode == .record && state.isRecording ? "stop.fill" : "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text(label).font(.system(size: 13, weight: .semibold))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        // Red only while actively recording in Record mode; always accent in Snip mode.
        .tint(state.mode == .record && state.isRecording ? .red : .accentColor)
        .keyboardShortcut("n", modifiers: .command)
        .scaleEffect(pressed ? 0.96 : 1)
        .animation(Motion.animation(.spring(duration: 0.12)), value: pressed)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressed = $0 }, perform: {})
        .accessibilityLabel(label)
    }

    private var label: String {
        if state.mode == .record { return state.isRecording ? "Stop" : "New" }
        return "New"
    }
}

// MARK: - Mode segments

private struct ModeSegments: View {
    @Binding var mode: CaptureMode
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CaptureMode.allCases) { segment in
                segmentButton(segment)
            }
        }
        .padding(3)
        .background(.primary.opacity(0.06), in: .capsule)
    }

    private func segmentButton(_ segment: CaptureMode) -> some View {
        let active = mode == segment
        return Button {
            withAnimation(Motion.animation(.easeInOut(duration: 0.18))) { mode = segment }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: segment.symbol).font(.system(size: 11))
                Text(segment.title).font(.system(size: 12, weight: .medium))
            }
            .frame(width: 72, height: 26)
            .foregroundStyle(active ? Color.white : Color.secondary)
            .background {
                if active {
                    Capsule()
                        .fill(Color.accentColor)
                        .glassEffect(.regular.tint(.accentColor), in: .capsule)
                        .matchedGeometryEffect(id: "seg", in: ns)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(segment.title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

// MARK: - Shape menu

private struct ShapeMenu: View {
    @Binding var shape: CaptureShape

    var body: some View {
        Menu {
            ForEach(CaptureShape.allCases) { option in
                Button { shape = option } label: {
                    Label(option.title, systemImage: option.symbol)
                }
            }
        } label: {
            PillLabel(systemImage: shape.symbol)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Capture shape: \(shape.title)")
    }
}

// MARK: - Timer menu

private struct TimerMenu: View {
    @Binding var timer: TimerDelay

    var body: some View {
        Menu {
            ForEach(TimerDelay.allCases) { option in
                Button { timer = option } label: {
                    if option == timer { Label(option.title, systemImage: "checkmark") }
                    else { Text(option.title) }
                }
            }
        } label: {
            PillLabel(systemImage: "timer", text: timer == .none ? nil : "\(timer.rawValue)s")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Timer: \(timer.title)")
    }
}

// MARK: - Mic toggle (record mode)

private struct MicToggle: View {
    @Bindable var state: AppState

    var body: some View {
        Button { state.micEnabled.toggle() } label: {
            PillLabel(systemImage: state.micEnabled ? "mic.fill" : "mic.slash")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.micEnabled ? "Microphone on" : "Microphone off")
    }
}

// MARK: - Overflow menu

private struct OverflowMenu: View {
    @Bindable var state: AppState

    var body: some View {
        Menu {
            Button("Open Settings") { (NSApp.delegate as? AppDelegate)?.openSettingsWindow() }
                .keyboardShortcut(",", modifiers: .command)
            Button("Capture History") { (NSApp.delegate as? AppDelegate)?.showHistoryWindow() }
            Button("Copy Last Capture") { state.copyLastCapture() }
            Button("Open Last Capture") { state.openLastCapture() }
            Divider()
            Button("About Snip") { NSApp.orderFrontStandardAboutPanel(nil) }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 16))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 28, height: 28)
        .accessibilityLabel("More options")
    }
}

// MARK: - Reusable pill label

private struct PillLabel: View {
    var systemImage: String
    var text: String? = nil
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).font(.system(size: 12))
            if let text { Text(text).font(.system(size: 12, weight: .medium)) }
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).opacity(0.6)
        }
        .padding(.horizontal, 10).frame(height: 28)
        .background(hovering ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.ultraThinMaterial), in: .capsule)
        .overlay(Capsule().strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
        .onHover { hovering = $0 }
    }
}
