# Snip

A fast, native macOS screenshot and screen-recording app that lives in your menu bar. Capture a region, window, full screen, or free-form selection; record video with optional narration; mark things up; and have everything copied, saved, and kept in a searchable history — all driven by global keyboard shortcuts.

> **Requires macOS 26 (Tahoe) or later.** Built with SwiftUI, AppKit, and ScreenCaptureKit.

<!-- TODO: add a screenshot or short demo GIF here -->

## Features

- **Capture shapes** — rectangular region, free-form (lasso), specific window, or full screen.
- **Screen recording** — record a region, window, or full screen to MOV or MP4, with selectable quality (720p/1080p/1440p/native) and frame rate (30/60 fps), plus optional microphone narration.
- **Markup** — annotate screenshots before saving or sharing.
- **Global shortcuts** — trigger any capture from anywhere; shortcuts are fully rebindable in Settings.
- **Timer & countdown** — optional 3/5/10-second delay with a full-screen dim, subtle HUD, or no countdown.
- **Auto-copy & auto-save** — copy to the clipboard and save to disk automatically.
- **Flexible output** — PNG, JPEG, HEIF, or TIFF for images; custom save folders; filename templates with `{date}`, `{time}`, `{index}`, and `{mode}` tokens.
- **Capture history** — browse past captures with configurable retention (7/30/90 days or forever).
- **Menu-bar native** — run as a menu-bar app, a Dock app, or both; light/dark/system appearance; optional launch at login and keep-on-top.

## Requirements

- macOS 26 (Tahoe) or later
- Xcode 16 or later (Swift 6)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (only if you want to regenerate the Xcode project from `project.yml`)

## Building

Clone the repo and open the project in Xcode:

```sh
git clone https://github.com/<your-username>/snip.git
cd snip
open Snip.xcodeproj
```

Then build and run the **Snip** scheme (⌘R).

If you change `project.yml` (targets, settings, dependencies), regenerate the project:

```sh
brew install xcodegen   # if not already installed
xcodegen generate
```

The only third-party dependency is [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts), resolved automatically via Swift Package Manager.

## Permissions

On first launch, Snip needs **Screen Recording** permission
(System Settings ▸ Privacy & Security ▸ Screen Recording). Recording with
narration also requests **Microphone** access. macOS may show a Gatekeeper
warning for unsigned local builds — building from source in Xcode avoids this.

## Default save locations

- Screenshots → `~/Pictures/Screenshots`
- Recordings → `~/Movies/Captures`

Both are configurable in Settings.

## License

[MIT](LICENSE) © 2026 Pirouz Ruppert
