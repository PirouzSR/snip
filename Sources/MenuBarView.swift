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

    @ViewBuilder
    private var previewSection: some View {
        if let image = state.lastCapturePreview {
            VStack(spacing: 8) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.12)))

                HStack(spacing: 8) {
                    quickButton("Copy", "doc.on.doc") { state.copyLastCapture(); dismiss() }
                    quickButton("Edit", "pencil.and.outline") { dismiss(); state.editLastCapture() }
                    quickButton("Save", "square.and.arrow.down") { dismiss(); state.saveLastCapture() }
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
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(title)
    }

    // MARK: Commands

    private var commands: some View {
        VStack(spacing: 1) {
            MenuRow(title: "New Snip", symbol: "camera", shortcut: "⌘⇧4") {
                dismiss(); state.mode = .snip
                state.beginSnip(shape: state.shape, timer: state.timer)
            }
            MenuRow(title: state.isRecording ? "Stop Recording" : "New Recording",
                    symbol: state.isRecording ? "stop.circle" : "record.circle", shortcut: "⌘⇧R") {
                dismiss(); state.mode = .record; state.toggleRecording()
            }
            Divider().padding(.vertical, 3)
            MenuRow(title: "Open Snip", symbol: "macwindow") {
                dismiss(); state.requestShowMainWindow?()
            }
            MenuRow(title: "Capture History", symbol: "clock") {
                dismiss(); (NSApp.delegate as? AppDelegate)?.showHistoryWindow()
            }
            MenuRow(title: "Settings…", symbol: "gearshape", shortcut: "⌘,") {
                dismiss(); (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
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
