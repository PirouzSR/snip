import SwiftUI
import KeyboardShortcuts

struct OnboardingView: View {
    @Bindable var state: AppState
    let finish: () -> Void

    @State private var step = 0
    @State private var permissionGranted = CapturePermission.isGranted

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            content
            Spacer()
            controls
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            VStack(spacing: 8) {
                Text("Welcome to Snip").font(.largeTitle.bold())
                Text("Capture, record, and mark up your screen — the macOS-native way.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
        case 1:
            VStack(spacing: 12) {
                Text("Screen Recording Access").font(.title2.bold())
                Text("Snip needs permission to capture your screen. macOS will ask you to allow it.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button(permissionGranted ? "Granted ✓" : "Grant Permission") {
                    CapturePermission.request()
                    permissionGranted = CapturePermission.isGranted
                    if !permissionGranted { CapturePermission.openSystemSettings() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(permissionGranted)
            }
        default:
            VStack(spacing: 12) {
                Text("Your Shortcut").font(.title2.bold())
                Text("Press this anywhere to start a snip. Change it anytime in Settings.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                KeyboardShortcuts.Recorder(for: .newSnip)
            }
        }
    }

    private var controls: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
            }
            Spacer()
            Button(step < 2 ? "Continue" : "Get Started") {
                if step < 2 { step += 1 } else { finish() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }
}
