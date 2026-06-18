import SwiftUI
import KeyboardShortcuts

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 28))
                .foregroundStyle(.secondary.opacity(0.5))
            instruction
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
                .foregroundStyle(.primary.opacity(0.08))
                .padding(12)
        )
    }

    private var instruction: Text {
        let shortcut = KeyboardShortcuts.getShortcut(for: .newSnip)?.description ?? "⌘⇧4"
        let key = Text(shortcut).fontDesign(.monospaced).foregroundColor(.primary)
        return Text("Press \(key) to start a snip.")
            .font(.body)
            .foregroundColor(.secondary)
    }
}
