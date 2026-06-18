import SwiftUI
import KeyboardShortcuts

struct ShortcutsPane: View {
    private let rows: [(String, KeyboardShortcuts.Name)] = [
        ("New Snip", .newSnip),
        ("New Window Snip", .newWindowSnip),
        ("New Full Screen Snip", .newFullScreenSnip),
        ("New Free-form Snip", .newFreeformSnip),
        ("Start/Stop Recording", .toggleRecording),
        ("Open Snip App", .openSnipApp),
        ("Repeat Last Capture", .repeatLastCapture),
    ]

    var body: some View {
        Form {
            ForEach(rows, id: \.1) { label, name in
                LabeledContent(label) {
                    KeyboardShortcuts.Recorder(for: name)
                }
            }
        }
        .formStyle(.grouped)
    }
}
