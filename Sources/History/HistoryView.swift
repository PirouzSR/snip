import SwiftUI
import AppKit

struct HistoryView: View {
    @Bindable var state: AppState
    @State private var search = ""

    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 12), count: 3) }

    private var filtered: [CaptureItem] {
        guard !search.isEmpty else { return state.history.items }
        return state.history.items.filter {
            $0.dimensionText.localizedCaseInsensitiveContains(search)
            || $0.date.formatted().localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search by date or dimensions", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.regularMaterial)
            Divider()
            ScrollView {
                if filtered.isEmpty {
                    ContentUnavailableView("No Captures", systemImage: "photo.on.rectangle.angled",
                                           description: Text("Your capture history will appear here."))
                        .padding(.top, 80)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filtered) { item in
                            HistoryCell(state: state, item: item)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .onAppear { state.history.pruneDeletedFiles() }
    }
}

private struct HistoryCell: View {
    @Bindable var state: AppState
    let item: CaptureItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                if let thumb = state.history.thumbnail(for: item) {
                    Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: item.kind == .video ? "video" : "photo")
                        .font(.largeTitle).foregroundStyle(.secondary)
                }
                if item.kind == .video {
                    Image(systemName: "play.circle.fill")
                        .font(.title).foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(height: 110)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.1)))

            Text(item.date, format: .dateTime.month().day().hour().minute())
                .font(.caption).foregroundStyle(.secondary)
            Text(item.durationText ?? item.dimensionText)
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .onTapGesture { reopen() }
        .contextMenu {
            Button("Copy") { copy() }
            Button("Save As…") { saveAs() }
            if let url = item.fileURL {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            Divider()
            Button("Delete", role: .destructive) { state.history.delete(item) }
        }
    }

    private func reopen() {
        switch item.kind {
        case .image:
            if let url = item.fileURL, let img = NSImage(contentsOf: url) {
                state.currentImage = img; state.currentVideoURL = nil; state.previewKind = .image
                state.currentCaptureURL = url
                state.requestShowMainWindow?()
            }
        case .video:
            if let url = item.fileURL {
                state.currentVideoURL = url; state.currentImage = nil; state.previewKind = .video
                state.currentCaptureURL = url
                state.requestShowMainWindow?()
            }
        }
    }

    private func copy() {
        if item.kind == .image, let url = item.fileURL, let img = NSImage(contentsOf: url) {
            Clipboard.copy(image: img)
        } else if let url = item.fileURL {
            Clipboard.copy(fileURL: url)
        }
    }

    private func saveAs() {
        guard let source = item.fileURL else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = source.lastPathComponent
        if panel.runModal() == .OK, let dest = panel.url {
            try? FileManager.default.copyItem(at: source, to: dest)
        }
    }
}
