import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        TabView {
            GeneralPane(settings: state.settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutsPane()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            OutputPane(settings: state.settings)
                .tabItem { Label("Output", systemImage: "square.and.arrow.down") }
            BehaviorPane(settings: state.settings)
                .tabItem { Label("Behavior", systemImage: "camera") }
            HistoryPane(settings: state.settings, history: state.history)
                .tabItem { Label("History", systemImage: "clock") }
        }
        .frame(width: 520, height: 460)
    }
}

// MARK: - General

struct GeneralPane: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
            Toggle("Keep window on top", isOn: $settings.keepOnTop)
            Toggle("Auto-copy to clipboard after capture", isOn: $settings.autoCopyToClipboard)
            Picker("Appearance", selection: $settings.appearance) {
                ForEach(AppearanceSetting.allCases) { Text($0.title).tag($0) }
            }
            Picker("Menu bar & Dock", selection: $settings.menuBarPresence) {
                ForEach(MenuBarPresence.allCases) { Text($0.title).tag($0) }
            }
            .onChange(of: settings.menuBarPresence) { _, _ in
                (NSApp.delegate as? AppDelegate)?.applyActivationPolicy()
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Output

struct OutputPane: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Save location")
                    Spacer()
                    Text(settings.saveDirectory.path(percentEncoded: false))
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Button("Choose…") { chooseFolder() }
                }
                Toggle("Auto-save captures", isOn: $settings.autoSave)
                VStack(alignment: .leading, spacing: 4) {
                    TextField("File naming", text: $settings.filenameTemplate)
                    Text("Preview: \(settings.resolvedFilename(mode: "snip")).\(settings.imageFormat.fileExtension)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Tokens: {date} {time} {index} {mode}")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Section("Image") {
                Picker("Format", selection: $settings.imageFormat) {
                    ForEach(ImageFormat.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                if settings.imageFormat == .jpeg {
                    HStack {
                        Text("Quality")
                        Slider(value: $settings.jpegQuality, in: 0.5...1.0)
                        Text("\(Int(settings.jpegQuality * 100))%").monospacedDigit()
                    }
                }
            }
            Section("Video") {
                Picker("Format", selection: $settings.videoFormat) {
                    ForEach(VideoFormat.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Picker("Quality", selection: $settings.videoQuality) {
                    ForEach(VideoQuality.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Picker("Frame rate", selection: $settings.frameRate) {
                    ForEach(FrameRate.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { settings.setSaveDirectory(url) }
    }
}

// MARK: - Behavior

struct BehaviorPane: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Picker("Countdown overlay style", selection: $settings.countdownStyle) {
                ForEach(CountdownStyle.allCases) { Text($0.title).tag($0) }
            }
            Picker("Default capture shape", selection: $settings.defaultShape) {
                ForEach(CaptureShape.allCases) { Text($0.title).tag($0) }
            }
            Picker("Default timer delay", selection: $settings.defaultTimer) {
                ForEach(TimerDelay.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Play sound on capture", isOn: $settings.playSound)
            Picker("Show preview after capture", selection: $settings.showPreview) {
                ForEach(ShowPreviewPolicy.allCases) { Text($0.title).tag($0) }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - History

struct HistoryPane: View {
    @Bindable var settings: AppSettings
    var history: HistoryStore
    @State private var confirmClear = false

    var body: some View {
        Form {
            Toggle("Save capture history", isOn: $settings.saveHistory)
            Picker("History retention", selection: $settings.historyRetention) {
                ForEach(HistoryRetention.allCases) { Text($0.title).tag($0) }
            }
            LabeledContent("Storage used", value: history.storageUsedText)
            Button("Clear History…", role: .destructive) { confirmClear = true }
                .confirmationDialog("Delete all capture history?", isPresented: $confirmClear) {
                    Button("Clear History", role: .destructive) { history.clearAll() }
                } message: {
                    Text("This permanently removes saved thumbnails and history entries.")
                }
        }
        .formStyle(.grouped)
    }
}
