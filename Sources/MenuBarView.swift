import SwiftUI
import AppKit

/// Content of the menu-bar popover: a preview of the last snip with quick actions,
/// plus the standard capture/window commands.
struct MenuBarView: View {
    @Bindable var state: AppState
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            previewSection
            Divider()
            commands
        }
        .frame(width: 300)
    }

    // MARK: Preview

    /// Fills the popover content width (300 − 20 padding) at the image's aspect ratio,
    /// capping height for very tall portrait captures.
    private func previewSize(for image: NSImage) -> CGSize {
        let maxW: CGFloat = 280
        let maxH: CGFloat = 300
        let aspect = image.size.width / max(image.size.height, 1)
        var w = maxW
        var h = maxW / aspect
        if h > maxH { h = maxH; w = maxH * aspect }
        return CGSize(width: w, height: h)
    }

    @ViewBuilder
    private var previewSection: some View {
        if let image = state.lastCapturePreview {
            VStack(spacing: 8) {
                let size = previewSize(for: image)
                Image(nsImage: image)
                    .resizable()
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.12)))

                HStack(spacing: 8) {
                    quickButton("Copy", "doc.on.doc") { state.copyLastCapture(); dismiss() }
                    quickButton("Edit", "pencil.and.outline") { dismiss(); state.editLastCapture() }
                    quickButton("Save", "square.and.arrow.down") { dismiss(); state.saveLastCapture() }
                    quickButton("Share", "square.and.arrow.up") { state.shareLastCapture() }
                }
            }
            .padding(10)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 26)).foregroundStyle(.secondary)
                Text("No recent snip")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        }
    }

    private func quickButton(_ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .help(title)
        .accessibilityLabel(title)
    }

    // MARK: Commands

    private var commands: some View {
        VStack(spacing: 1) {
            MenuRow(title: "New Snip", symbol: "camera") {
                dismiss(); state.mode = .snip
                state.beginSnip(shape: state.shape, timer: state.timer)
            }
            MenuRow(title: state.isRecording ? "Stop Recording" : "New Recording",
                    symbol: state.isRecording ? "stop.circle" : "record.circle") {
                dismiss(); state.mode = .record; state.toggleRecording()
            }
            Divider().padding(.vertical, 3)
            MenuRow(title: "Open Snip", symbol: "macwindow") {
                dismiss(); state.requestShowMainWindow?()
            }
            MenuRow(title: "Capture History", symbol: "clock") {
                dismiss(); AppDelegate.shared?.showHistoryWindow()
            }
            MenuRow(title: "Settings…", symbol: "gearshape", shortcut: "⌘,") {
                dismiss(); AppDelegate.shared?.openSettingsWindow()
            }
            Divider().padding(.vertical, 3)
            MenuRow(title: "Quit Snip", symbol: "power") { NSApp.terminate(nil) }
        }
        .padding(8)
    }
}

/// A hover-highlighting row that mimics a native menu item.
private struct MenuRow: View {
    let title: String
    let symbol: String
    var shortcut: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 18)
                Text(title)
                Spacer()
                if let shortcut { Text(shortcut).foregroundStyle(.secondary).font(.caption.monospaced()) }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(hovering ? AnyShapeStyle(.tint.opacity(0.85)) : AnyShapeStyle(.clear),
                        in: .rect(cornerRadius: 6))
            .foregroundStyle(hovering ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
