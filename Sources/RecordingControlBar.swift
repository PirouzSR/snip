import SwiftUI

/// Minimal bottom-center recording controls shown while the main window is hidden.
/// Lives in Snip's own (excluded) app, so it never appears in the recording.
struct RecordingControlBar: View {
    @Bindable var state: AppState
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 7) {
                Circle().fill(.red).frame(width: 11, height: 11)
                    .opacity(pulse ? 0.3 : 1)
                    .animation(Motion.reduced ? nil : .easeInOut(duration: 0.8).repeatForever(), value: pulse)
                Text(state.recordingTimeText)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
            }

            Button { Task { await state.stopRecording() } } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .accessibilityLabel("Stop recording")

            Button { state.cancelRecording() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Cancel (discard)")
            .accessibilityLabel("Cancel recording")

            Button { AppDelegate.shared?.openSettingsWindow() } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .font(.system(size: 14))
        .padding(.horizontal, 16)
        .frame(height: 56)
        .glassEffect(.regular, in: .capsule)
        .onAppear { pulse = true }
    }
}
