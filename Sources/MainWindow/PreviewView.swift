import SwiftUI
import AVKit

struct PreviewView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            previewArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(12)
            actionBar
        }
    }

    @ViewBuilder
    private var previewArea: some View {
        if state.previewKind == .video, let url = state.currentVideoURL {
            PlayerView(url: url)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
        } else if let image = state.currentImage {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
        }
    }

    private var actionBar: some View {
        HStack(spacing: 18) {
            action("doc.on.doc", "Copy") { state.copyCurrent() }
            action("square.and.arrow.down", "Save") { state.presentSavePanel() }
            ShareLinkButton(state: state)
            if state.previewKind == .image {
                action("pencil.and.outline", "Markup") { state.markupActive = true }
            }
            action("xmark.circle", "Clear") { state.discardCurrent() }
            action("trash", "Delete") { state.deleteCurrent() }
        }
        .font(.system(size: 16))
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private func action(_ symbol: String, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// AppKit AVPlayerView wrapper that owns its looping player. Avoids the AVKit-SwiftUI
/// `VideoPlayer` metadata crash and guarantees the player is loaded when the view appears.
private struct PlayerView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        context.coordinator.load(url: url, into: view)
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        context.coordinator.load(url: url, into: view)
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        MainActor.assumeIsolated { coordinator.teardown() }
    }

    @MainActor
    final class Coordinator {
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private var currentURL: URL?

        func load(url: URL, into view: AVPlayerView) {
            guard currentURL != url else { return }
            currentURL = url
            let item = AVPlayerItem(url: url)
            let queue = AVQueuePlayer()
            looper = AVPlayerLooper(player: queue, templateItem: item)
            player = queue
            view.player = queue
            queue.play()
        }

        func teardown() {
            player?.pause()
            looper?.disableLooping()
            looper = nil
            player = nil
        }
    }
}

private struct ShareLinkButton: View {
    @Bindable var state: AppState

    var body: some View {
        Group {
            if let url = state.currentVideoURL {
                ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
            } else if let image = state.currentImage {
                ShareLink(item: Image(nsImage: image), preview: SharePreview("Snip", image: Image(nsImage: image))) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share")
    }
}

/// Shown while a recording is in progress.
struct RecordingStatusView: View {
    @Bindable var state: AppState
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Circle().fill(.red).frame(width: 14, height: 14)
                    .opacity(pulse ? 0.3 : 1)
                    .animation(Motion.reduced ? nil : .easeInOut(duration: 0.8).repeatForever(), value: pulse)
                Text(state.recordingTimeText)
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
            }
            Button(role: .destructive) { Task { await state.stopRecording() } } label: {
                Label("Stop Recording", systemImage: "stop.fill")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { pulse = true }
    }
}
