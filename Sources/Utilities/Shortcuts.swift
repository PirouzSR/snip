import KeyboardShortcuts

// Global hotkey definitions with the defaults from the spec table.
extension KeyboardShortcuts.Name {
    static let newSnip = Self("newSnip", default: .init(.four, modifiers: [.command, .shift]))
    static let newWindowSnip = Self("newWindowSnip", default: .init(.five, modifiers: [.command, .shift]))
    static let newFullScreenSnip = Self("newFullScreenSnip", default: .init(.three, modifiers: [.command, .shift]))
    static let newFreeformSnip = Self("newFreeformSnip", default: .init(.f, modifiers: [.command, .shift]))
    static let toggleRecording = Self("toggleRecording", default: .init(.r, modifiers: [.command, .shift]))
    static let openSnipApp = Self("openSnipApp", default: .init(.x, modifiers: [.command, .shift]))
    static let repeatLastCapture = Self("repeatLastCapture", default: .init(.z, modifiers: [.command, .shift]))
}
