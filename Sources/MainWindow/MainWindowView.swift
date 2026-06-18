import SwiftUI

/// Root view hosted inside the glass panel.
struct MainWindowRoot: View {
    @Bindable var state: AppState

    var body: some View {
        MainWindowView(state: state)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
            .alert("Capture Error", isPresented: $state.showError, presenting: state.errorMessage) { _ in
                Button("OK", role: .cancel) {}
                Button("Open Settings") { CapturePermission.openSystemSettings() }
            } message: { msg in
                Text(msg)
            }
    }
}

struct MainWindowView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView(state: state)
                .frame(height: 44)
            Divider().opacity(0.4)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var content: some View {
        if state.markupActive, let image = state.currentImage {
            MarkupView(state: state, image: image)
                .transition(.opacity)
        } else if state.hasPreview {
            PreviewView(state: state)
                .transition(.opacity)
        } else if state.isRecording {
            RecordingStatusView(state: state)
                .transition(.opacity)
        } else {
            EmptyStateView()
                .transition(.opacity)
        }
    }
}
