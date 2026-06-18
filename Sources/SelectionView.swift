import SwiftUI
import AppKit
import ScreenCaptureKit

/// The crosshair / rubber-band / confirm UI rendered inside each overlay panel.
struct SelectionView: View {
    @Bindable var coordinator: SelectionCoordinator
    let screen: NSScreen

    @State private var dragStart: CGPoint?
    @State private var dashPhase: CGFloat = 0

    private var dimOpacity: Double { coordinator.phase == .dragging ? 0.45 : 0.35 }

    var body: some View {
        GeometryReader { _ in
            ZStack {
                dimmedBackground
                content
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .onContinuousHover { phase in
                if case .active(let location) = phase {
                    coordinator.cursorLocation = location
                    coordinator.activeScreen = screen
                    if coordinator.shape == .window {
                        coordinator.hoveredWindow = windowAt(location)
                    }
                }
            }
            .accessibilityLabel("Screen capture selection mode. Drag to select an area. Press Escape to cancel.")
        }
        .ignoresSafeArea()
        .onAppear {
            if !Motion.reduced {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    dashPhase = -12
                }
            }
        }
    }

    // MARK: Background dim with a hole cut for the selection

    private var dimmedBackground: some View {
        Rectangle()
            .fill(Color.black.opacity(dimOpacity))
            .overlay {
                if isActiveScreen {
                    switch coordinator.shape {
                    case .rectangle, .fullScreen:
                        Rectangle()
                            .path(in: selectionFrame)
                            .fill(Color.black)
                            .blendMode(.destinationOut)
                    case .freeform:
                        freeformShape.fill(Color.black).blendMode(.destinationOut)
                    case .window:
                        if let rect = hoveredWindowRect {
                            Rectangle().path(in: rect).fill(Color.black).blendMode(.destinationOut)
                        }
                    }
                }
            }
            .compositingGroup()
            .animation(Motion.animation(.easeOut(duration: 0.15)), value: coordinator.phase)
    }

    // MARK: Foreground decorations

    @ViewBuilder
    private var content: some View {
        if isActiveScreen {
            switch coordinator.shape {
            case .rectangle, .fullScreen:
                if selectionFrame.width > 1 {
                    rectangleDecorations
                }
            case .freeform:
                freeformShape
                    .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            case .window:
                if let rect = hoveredWindowRect {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor, lineWidth: 4)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
                windowHint
            }

            if coordinator.shape != .window {
                coordinateHUD
            }
        }
    }

    private var rectangleDecorations: some View {
        let frame = selectionFrame
        return ZStack {
            Rectangle()
                .strokeBorder(.white, style: StrokeStyle(lineWidth: 1, dash: [6, 4], dashPhase: dashPhase))
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

            dimensionHUD(for: frame)

            if coordinator.phase == .confirmed {
                confirmToolbar(for: frame)
            }
        }
    }

    // MARK: HUDs

    private var coordinateHUD: some View {
        let loc = coordinator.cursorLocation
        return Text("\(Int(loc.x)), \(Int(loc.y)) px")
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .glassEffect(.regular, in: .capsule)
            .position(x: loc.x + 70, y: loc.y + 24)
            .opacity(coordinator.phase == .crosshair ? 1 : 0)
    }

    private func dimensionHUD(for frame: CGRect) -> some View {
        let aboveTop = frame.minY > 40
        let y = aboveTop ? frame.minY - 18 : frame.maxY + 18
        return Text("W: \(Int(frame.width)) × H: \(Int(frame.height)) px")
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.black.opacity(0.55), in: .capsule)
            .position(x: frame.midX, y: y)
    }

    private func confirmToolbar(for frame: CGRect) -> some View {
        let below = frame.maxY + 44 < screen.frame.height
        let y = below ? frame.maxY + 28 : frame.minY - 28
        return HStack(spacing: 14) {
            Button { coordinator.confirm(withMarkup: false) } label: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            .accessibilityLabel("Confirm capture")
            Button { coordinator.confirm(withMarkup: true) } label: {
                Image(systemName: "pencil")
            }
            .accessibilityLabel("Capture and open markup")
            Button { coordinator.cancel() } label: {
                Image(systemName: "xmark.circle").foregroundStyle(.secondary)
            }
            .accessibilityLabel("Cancel")
        }
        .font(.system(size: 18))
        .buttonStyle(.plain)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .position(x: frame.midX, y: y)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var windowHint: some View {
        Text("Click a window to capture it • Esc to cancel")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.black.opacity(0.5), in: .capsule)
            .position(x: screen.frame.width / 2, y: 60)
    }

    // MARK: Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                coordinator.activeScreen = screen
                coordinator.cursorLocation = value.location
                guard coordinator.shape == .rectangle || coordinator.shape == .freeform else { return }
                if dragStart == nil {
                    dragStart = value.startLocation
                    coordinator.phase = .dragging
                    if coordinator.shape == .freeform { coordinator.freeformPoints = [] }
                }
                if coordinator.shape == .rectangle {
                    coordinator.selectionRect = CGRect(origin: value.startLocation, size: .zero)
                        .union(CGRect(origin: value.location, size: .zero))
                } else {
                    coordinator.freeformPoints.append(value.location)
                }
            }
            .onEnded { value in
                switch coordinator.shape {
                case .rectangle, .freeform:
                    // Capture instantly on mouse-up — no confirm/markup toolbar step.
                    dragStart = nil
                    coordinator.confirm(withMarkup: false)
                case .window:
                    coordinator.hoveredWindow = windowAt(value.location)
                    if coordinator.hoveredWindow != nil { coordinator.confirm(withMarkup: false) }
                case .fullScreen:
                    coordinator.confirm(withMarkup: false)
                }
            }
    }

    // MARK: Helpers

    private var isActiveScreen: Bool { coordinator.activeScreen == screen || coordinator.activeScreen == nil }

    private var selectionFrame: CGRect { coordinator.selectionRect.standardizedNonNegative }

    private var freeformShape: Path {
        Path { p in
            guard let first = coordinator.freeformPoints.first else { return }
            p.move(to: first)
            for pt in coordinator.freeformPoints.dropFirst() { p.addLine(to: pt) }
            if coordinator.phase == .confirmed { p.closeSubpath() }
        }
    }

    /// Converts a window's global CG frame into this screen's local (top-left) point space.
    private func localRect(for window: SCWindow) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let originX = screen.frame.minX
        let originY = primaryHeight - screen.frame.maxY
        return CGRect(x: window.frame.minX - originX,
                      y: window.frame.minY - originY,
                      width: window.frame.width, height: window.frame.height)
    }

    private func windowAt(_ point: CGPoint) -> SCWindow? {
        // Windows are returned front-to-back; first hit wins.
        coordinator.windows.first { localRect(for: $0).contains(point) }
    }

    private var hoveredWindowRect: CGRect? {
        guard let win = coordinator.hoveredWindow else { return nil }
        return localRect(for: win)
    }
}
