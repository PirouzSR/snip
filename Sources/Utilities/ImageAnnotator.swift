import SwiftUI
import AppKit

// MARK: - Annotation model

enum MarkupTool: String, CaseIterable, Identifiable {
    case pen, highlighter, rectangle, ellipse, arrow, text, eraser
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .arrow: "arrow.up.right"
        case .text: "textformat"
        case .eraser: "eraser"
        }
    }
}

struct Annotation: Identifiable {
    let id = UUID()
    var tool: MarkupTool
    var points: [CGPoint] = []     // pen / highlighter
    var start: CGPoint = .zero     // shapes / arrow / text origin
    var end: CGPoint = .zero
    var colorRGBA: [Double]
    var width: CGFloat
    var text: String = ""

    var color: Color {
        Color(.sRGB, red: colorRGBA[0], green: colorRGBA[1], blue: colorRGBA[2], opacity: colorRGBA[3])
    }
}

// MARK: - Markup view

struct MarkupView: View {
    @Bindable var state: AppState
    let image: NSImage

    /// A full editor snapshot (image + annotations) so undo/redo covers both drawing and crops.
    private struct Snapshot { var image: NSImage; var annotations: [Annotation] }

    @State private var workingImage: NSImage
    @State private var annotations: [Annotation] = []
    @State private var undoStack: [Snapshot] = []
    @State private var redoStack: [Snapshot] = []
    @State private var current: Annotation?
    @State private var tool: MarkupTool = .pen
    @State private var color: Color = .red
    @State private var width: CGFloat = 4
    @State private var canvasSize: CGSize = .zero

    // Text editing
    @State private var editingTextID: Annotation.ID?
    @FocusState private var textFocused: Bool

    // Crop mode
    @State private var cropping = false
    @State private var cropRect: CGRect = .zero
    @State private var cropGestureStart: CGRect?
    @State private var activeCropHandle: CropHandle?
    @State private var cropMoving = false
    // `NSEvent.modifierFlags` can be stale inside SwiftUI drag closures, so we also track the
    // shift key with a live event monitor for aspect-ratio-locked cropping.
    @State private var shiftHeld = false
    @State private var flagsMonitor: Any?

    init(state: AppState, image: NSImage) {
        self.state = state
        self.image = image
        _workingImage = State(initialValue: image)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.4)
            canvas
            actionBar
        }
        .onChange(of: tool) { _, _ in commitText() }   // switching tools finishes any open text box
        .onAppear {
            shiftHeld = NSEvent.modifierFlags.contains(.shift)
            flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                shiftHeld = event.modifierFlags.contains(.shift)
                return event
            }
        }
        .onDisappear {
            if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
        }
    }

    /// Copy / Save / Share along the bottom, matching the new-snip preview action bar.
    private var actionBar: some View {
        HStack(spacing: 18) {
            actionButton("doc.on.doc", "Copy") { copyFlattened() }
            actionButton("square.and.arrow.down", "Save") { saveFlattened() }
            actionButton("square.and.arrow.up", "Share") { shareFlattened() }
        }
        .font(.system(size: 16))
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private func actionButton(_ symbol: String, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) { Image(systemName: symbol) }
            .buttonStyle(.plain)
            .help(label)
            .accessibilityLabel(label)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            if cropping {
                Text("\(Int(cropPixelSize.width)) × \(Int(cropPixelSize.height)) px")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { cropping = false }
                Button("Apply Crop") { applyCrop() }
                    .buttonStyle(.borderedProminent)
                    .disabled(cropRect.width < 8 || cropRect.height < 8)
            } else {
                ForEach(MarkupTool.allCases) { t in
                    Button { tool = t } label: {
                        Image(systemName: t.symbol)
                            .frame(width: 26, height: 26)
                            .background(tool == t ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(t.rawValue.capitalized)
                    .accessibilityLabel(t.rawValue.capitalized)
                }
                Button { beginCrop() } label: {
                    Image(systemName: "crop").frame(width: 26, height: 26)
                }
                .buttonStyle(.plain).help("Crop").accessibilityLabel("Crop")
                Divider().frame(height: 18)
                ColorSwatchPicker(color: $color)
                Slider(value: $width, in: 1...24).frame(width: 80)
                Divider().frame(height: 18)
                Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.plain).disabled(undoStack.isEmpty).accessibilityLabel("Undo")
                    .keyboardShortcut("z", modifiers: .command)
                Button { redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .buttonStyle(.plain).disabled(redoStack.isEmpty).accessibilityLabel("Redo")
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                Spacer()
                Button { flattenAndExit() } label: {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .help("Done — apply markup and exit")
                .accessibilityLabel("Done")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let fitted = fittedSize(in: geo.size)
            // Top-left of the (centered) image within the full canvas area.
            let imageOrigin = CGPoint(x: (geo.size.width - fitted.width) / 2,
                                      y: (geo.size.height - fitted.height) / 2)
            ZStack {
                // Image + annotations + crop visuals, in the image's own coordinate space.
                ZStack {
                    Image(nsImage: workingImage)
                        .resizable()
                        .interpolation(.high)
                    AnnotationsLayer(annotations: annotations, current: current, editingTextID: editingTextID)
                    if cropping { cropOverlay }
                }
                .frame(width: fitted.width, height: fitted.height)
                .contentShape(Rectangle())
                .gesture(cropping ? nil : unifiedGesture)
                .overlay(textEditors)

                // While cropping, a single gesture covers the whole canvas so handles at (or
                // beyond) the image edges stay reachable — not clipped to the image frame.
                if cropping {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(cropGesture(imageOrigin: imageOrigin))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { canvasSize = fitted }
            .onChange(of: fitted) { _, newValue in canvasSize = newValue }
        }
    }

    /// Inset kept clear around the image on every side, so crop handles sitting on the edges
    /// (and the area just outside them) always fall within the canvas-wide gesture layer.
    /// Kept under the handle hit threshold / √2 so even the corner band stays grabbable.
    private let canvasInset: CGFloat = 16

    private func fittedSize(in available: CGSize) -> CGSize {
        let maxW = max(available.width - canvasInset * 2, 1)
        let maxH = max(available.height - canvasInset * 2, 1)
        let aspect = workingImage.size.width / max(workingImage.size.height, 1)
        var w = maxW
        var h = w / aspect
        if h > maxH { h = maxH; w = h * aspect }
        return CGSize(width: max(w, 1), height: max(h, 1))
    }

    // MARK: Crop overlay (starts at full image; drag handles inward/outward)

    private var cropPixelSize: CGSize {
        let scale = workingImage.pixelSize.width / max(canvasSize.width, 1)
        return CGSize(width: cropRect.width * scale, height: cropRect.height * scale)
    }

    private func beginCrop() {
        cropping = true
        cropRect = CGRect(origin: .zero, size: canvasSize)   // start at the full image
    }

    private var cropOverlay: some View {
        ZStack {
            // Dim everything outside the crop rect.
            Color.black.opacity(0.5)
                .overlay { Rectangle().path(in: cropRect).fill(Color.black).blendMode(.destinationOut) }
                .compositingGroup()

            // Crop border.
            Rectangle()
                .strokeBorder(.white, lineWidth: 1.5)
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)

            // Resize handles (visual only — input is handled by the canvas-wide crop gesture).
            ForEach(CropHandle.allCases, id: \.self) { handle in
                let p = handle.position(in: cropRect)
                Circle().fill(.white).overlay(Circle().strokeBorder(.black.opacity(0.25)))
                    .frame(width: 14, height: 14)
                    .position(p)
            }
        }
        .allowsHitTesting(false)
    }

    /// One drag gesture for the entire crop interaction. It maps the touch into the image's
    /// coordinate space, grabs the nearest handle within a threshold (so corners are easy to
    /// hit, even at the very edge), and otherwise moves the whole rect.
    private func cropGesture(imageOrigin: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let startPt = CGPoint(x: value.startLocation.x - imageOrigin.x,
                                      y: value.startLocation.y - imageOrigin.y)
                let curPt = CGPoint(x: value.location.x - imageOrigin.x,
                                    y: value.location.y - imageOrigin.y)
                if cropGestureStart == nil {
                    cropGestureStart = cropRect
                    activeCropHandle = handleNear(startPt, in: cropRect)
                    cropMoving = activeCropHandle == nil && cropRect.contains(startPt)
                }
                guard let start = cropGestureStart else { return }
                let dx = curPt.x - startPt.x
                let dy = curPt.y - startPt.y
                if let handle = activeCropHandle {
                    cropRect = resizedRect(start: start, handle: handle, dx: dx, dy: dy)
                } else if cropMoving {
                    cropRect = movedRect(start: start, dx: dx, dy: dy)
                }
            }
            .onEnded { _ in
                cropGestureStart = nil
                activeCropHandle = nil
                cropMoving = false
            }
    }

    /// Closest handle whose drawn position is within the hit threshold of `point`, else nil.
    private func handleNear(_ point: CGPoint, in rect: CGRect) -> CropHandle? {
        let threshold: CGFloat = 24
        var best: (handle: CropHandle, dist: CGFloat)?
        for handle in CropHandle.allCases {
            let p = handle.position(in: rect)
            let d = hypot(point.x - p.x, point.y - p.y)
            if d <= threshold, best == nil || d < best!.dist { best = (handle, d) }
        }
        return best?.handle
    }

    private func movedRect(start: CGRect, dx: CGFloat, dy: CGFloat) -> CGRect {
        var x = start.minX + dx
        var y = start.minY + dy
        x = min(max(0, x), canvasSize.width - start.width)
        y = min(max(0, y), canvasSize.height - start.height)
        return CGRect(x: x, y: y, width: start.width, height: start.height)
    }

    private func resizedRect(start: CGRect, handle: CropHandle, dx: CGFloat, dy: CGFloat) -> CGRect {
        let minSize: CGFloat = 24
        var minX = start.minX, minY = start.minY, maxX = start.maxX, maxY = start.maxY
        if handle.movesLeft { minX = min(max(0, start.minX + dx), maxX - minSize) }
        if handle.movesRight { maxX = max(min(canvasSize.width, start.maxX + dx), minX + minSize) }
        if handle.movesTop { minY = min(max(0, start.minY + dy), maxY - minSize) }
        if handle.movesBottom { maxY = max(min(canvasSize.height, start.maxY + dy), minY + minSize) }

        // Shift held: lock to the starting rect's aspect ratio.
        if shiftHeld || NSEvent.modifierFlags.contains(.shift) {
            let aspect = start.width / max(start.height, 1)
            let w = maxX - minX
            let h = maxY - minY
            let movesH = handle.movesLeft || handle.movesRight
            let movesV = handle.movesTop || handle.movesBottom
            if movesH && movesV {
                // Corner: drive off whichever axis changed proportionally more.
                let wRatio = w / max(start.width, 1)
                let hRatio = h / max(start.height, 1)
                if wRatio >= hRatio {
                    if handle.movesTop { minY = maxY - min(w / aspect, maxY) }
                    else { maxY = minY + min(w / aspect, canvasSize.height - minY) }
                } else {
                    if handle.movesLeft { minX = maxX - min(h * aspect, maxX) }
                    else { maxX = minX + min(h * aspect, canvasSize.width - minX) }
                }
            } else if movesH {
                // Left/right edge: width drives height (anchored at the top edge).
                maxY = minY + min(w / aspect, canvasSize.height - minY)
            } else {
                // Top/bottom edge: height drives width (anchored at the left edge).
                maxX = minX + min(h * aspect, canvasSize.width - minX)
            }
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: Drawing gesture (disabled while cropping)

    private var unifiedGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !cropping else { return }
                handleDrawChanged(value)
            }
            .onEnded { value in
                guard !cropping else { return }
                handleDrawEnded(value)
            }
    }

    /// Only the text annotation currently being edited shows an editable field; committed
    /// text is rendered by the Canvas (so it bakes into the flattened output).
    @ViewBuilder
    private var textEditors: some View {
        if let id = editingTextID, let idx = annotations.firstIndex(where: { $0.id == id }) {
            TextField("Text", text: $annotations[idx].text)
                .textFieldStyle(.plain)
                .font(.system(size: annotations[idx].width * 4))
                .foregroundStyle(annotations[idx].color)
                .multilineTextAlignment(.leading)
                .focused($textFocused)
                .fixedSize()
                // Anchor the field's top-left at the tap point so it grows to the right (and
                // down), keeping the text left-aligned instead of expanding from the center.
                .offset(x: annotations[idx].start.x, y: annotations[idx].start.y)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onSubmit { commitText() }
                .onChange(of: textFocused) { _, focused in if !focused { commitText() } }
        }
    }

    private func handleDrawChanged(_ value: DragGesture.Value) {
        guard tool != .text else { return }   // text is placed on tap (ended)
        if editingTextID != nil { commitText() }   // drawing elsewhere finishes the open text box
        if current == nil {
            var annot = Annotation(tool: tool, colorRGBA: rgba(of: color), width: width)
            annot.start = value.startLocation
            annot.end = value.location
            if tool == .pen || tool == .highlighter || tool == .eraser {
                annot.points = [value.startLocation]
            }
            current = annot
        }
        if tool == .pen || tool == .highlighter || tool == .eraser {
            current?.points.append(value.location)
        } else {
            current?.end = value.location
        }
    }

    private func handleDrawEnded(_ value: DragGesture.Value) {
        if tool == .text {
            // Tapping while a box is open deselects/commits it; the next tap starts a new one.
            if editingTextID != nil {
                commitText()
            } else {
                placeText(at: value.location)
            }
            return
        }
        if let annot = current {
            pushUndo()
            annotations.append(annot)
        }
        current = nil
    }

    // MARK: Editing operations

    private func placeText(at point: CGPoint) {
        commitText()   // finish any in-progress field first
        pushUndo()
        var annot = Annotation(tool: .text, colorRGBA: rgba(of: color), width: width)
        annot.start = point
        annotations.append(annot)
        editingTextID = annot.id
        textFocused = true
    }

    private func commitText() {
        guard let id = editingTextID else { return }
        if let idx = annotations.firstIndex(where: { $0.id == id }),
           annotations[idx].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            annotations.remove(at: idx)        // discard empty text boxes…
            if !undoStack.isEmpty { undoStack.removeLast() }  // …and the no-op undo step it created
        }
        editingTextID = nil
    }

    /// Records the current editor state so the next mutation can be undone.
    private func pushUndo() {
        undoStack.append(Snapshot(image: workingImage, annotations: annotations))
        redoStack.removeAll()
    }

    private func undo() {
        commitText()
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(Snapshot(image: workingImage, annotations: annotations))
        workingImage = prev.image
        annotations = prev.annotations
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(Snapshot(image: workingImage, annotations: annotations))
        workingImage = next.image
        annotations = next.annotations
    }

    private func rgba(of color: Color) -> [Double] {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .red
        return [Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent), Double(ns.alphaComponent)]
    }

    // MARK: Flatten & crop

    /// Renders the working image with all annotations baked in, at full pixel resolution.
    @MainActor
    private func renderFlattened() -> NSImage? {
        let renderSize = canvasSize == .zero ? workingImage.size : canvasSize
        let composed = ZStack {
            Image(nsImage: workingImage).resizable().interpolation(.high)
            AnnotationsLayer(annotations: annotations, current: nil)
        }
        .frame(width: renderSize.width, height: renderSize.height)

        let renderer = ImageRenderer(content: composed)
        renderer.scale = workingImage.pixelSize.width / max(renderSize.width, 1)
        guard let cg = renderer.cgImage else { return nil }
        return NSImage(cgImage: cg, size: workingImage.size)
    }

    @MainActor
    private func applyCrop() {
        guard cropRect.width >= 8, cropRect.height >= 8 else { cropping = false; return }
        guard let flat = renderFlattened(), let cg = flat.cgImage else { cropping = false; return }
        // Map crop rect (canvas points, top-left) into image pixels. CGImage cropping uses
        // an upper-left origin, matching the canvas coordinate space.
        let scale = CGFloat(cg.width) / max(canvasSize.width, 1)
        let pxRect = CGRect(x: cropRect.minX * scale, y: cropRect.minY * scale,
                            width: cropRect.width * scale, height: cropRect.height * scale)
            .integral
        if let cropped = cg.cropping(to: pxRect) {
            pushUndo()   // crop is undoable
            let pointSize = NSSize(width: pxRect.width / scale, height: pxRect.height / scale)
            workingImage = NSImage(cgImage: cropped, size: pointSize)
            annotations.removeAll()   // baked into the cropped image; restored on undo
        }
        cropping = false
        cropRect = .zero
    }

    @MainActor
    private func copyFlattened() {
        if let image = renderFlattened() { Clipboard.copy(image: image) }
    }

    @MainActor
    private func saveFlattened() {
        guard let image = renderFlattened() else { return }
        state.currentImage = image
        state.previewKind = .image
        state.presentSavePanel()
    }

    @MainActor
    private func shareFlattened() {
        guard let image = renderFlattened(),
              let view = NSApp.keyWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: [image])
        picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
    }

    @MainActor
    private func flattenAndExit() {
        if let flattened = renderFlattened() {
            state.currentImage = flattened
            state.lastCapturePreview = flattened.downscaled(maxDimension: 512)
            if state.settings.autoCopyToClipboard { Clipboard.copy(image: flattened) }
        }
        state.markupActive = false
    }
}

// MARK: - Crop handles

private enum CropHandle: CaseIterable {
    case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight

    var movesLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesRight: Bool { self == .topRight || self == .right || self == .bottomRight }
    var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }
    var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }

    func position(in r: CGRect) -> CGPoint {
        let x = movesLeft ? r.minX : (movesRight ? r.maxX : r.midX)
        let y = movesTop ? r.minY : (movesBottom ? r.maxY : r.midY)
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Rendering layer

private struct AnnotationsLayer: View {
    let annotations: [Annotation]
    let current: Annotation?
    var editingTextID: Annotation.ID? = nil

    var body: some View {
        Canvas { ctx, _ in
            for annot in annotations {
                if annot.tool == .text && annot.id == editingTextID { continue }
                draw(annot, in: &ctx)
            }
            if let current { draw(current, in: &ctx) }
        }
    }

    private func draw(_ annot: Annotation, in ctx: inout GraphicsContext) {
        var path = Path()
        switch annot.tool {
        case .pen, .highlighter:
            guard let first = annot.points.first else { return }
            path.move(to: first)
            for p in annot.points.dropFirst() { path.addLine(to: p) }
            let opacity = annot.tool == .highlighter ? 0.4 : 1.0
            ctx.stroke(path, with: .color(annot.color.opacity(opacity)),
                       style: StrokeStyle(lineWidth: annot.tool == .highlighter ? annot.width * 2.2 : annot.width,
                                          lineCap: .round, lineJoin: .round))
        case .rectangle:
            path.addRect(rect(annot))
            ctx.stroke(path, with: .color(annot.color), lineWidth: annot.width)
        case .ellipse:
            path.addEllipse(in: rect(annot))
            ctx.stroke(path, with: .color(annot.color), lineWidth: annot.width)
        case .arrow:
            drawArrow(annot, in: &ctx)
        case .text:
            guard !annot.text.isEmpty else { return }
            let text = Text(annot.text)
                .font(.system(size: annot.width * 4))
                .foregroundColor(annot.color)
            ctx.draw(text, at: annot.start, anchor: .topLeading)
        case .eraser:
            guard let first = annot.points.first else { return }
            path.move(to: first)
            for p in annot.points.dropFirst() { path.addLine(to: p) }
            // Clear annotation pixels drawn earlier, revealing the screenshot beneath —
            // a progressive eraser that never touches the base image.
            var eraser = ctx
            eraser.blendMode = .destinationOut
            eraser.stroke(path, with: .color(.black),
                          style: StrokeStyle(lineWidth: max(annot.width * 2.5, 16),
                                             lineCap: .round, lineJoin: .round))
        }
    }

    private func rect(_ annot: Annotation) -> CGRect {
        CGRect(origin: annot.start, size: .zero).union(CGRect(origin: annot.end, size: .zero))
    }

    private func drawArrow(_ annot: Annotation, in ctx: inout GraphicsContext) {
        var line = Path()
        line.move(to: annot.start)
        line.addLine(to: annot.end)
        ctx.stroke(line, with: .color(annot.color), style: StrokeStyle(lineWidth: annot.width, lineCap: .round))

        let angle = atan2(annot.end.y - annot.start.y, annot.end.x - annot.start.x)
        let headLength = max(12, annot.width * 3)
        var head = Path()
        head.move(to: annot.end)
        head.addLine(to: CGPoint(x: annot.end.x - headLength * cos(angle - .pi / 6),
                                 y: annot.end.y - headLength * sin(angle - .pi / 6)))
        head.move(to: annot.end)
        head.addLine(to: CGPoint(x: annot.end.x - headLength * cos(angle + .pi / 6),
                                 y: annot.end.y - headLength * sin(angle + .pi / 6)))
        ctx.stroke(head, with: .color(annot.color), style: StrokeStyle(lineWidth: annot.width, lineCap: .round))
    }
}

// MARK: - Color swatch picker

/// A compact color dot that opens a popover palette of preset swatches plus a custom option.
private struct ColorSwatchPicker: View {
    @Binding var color: Color
    @State private var showing = false

    private let presets: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .black, .white]
    private var columns: [GridItem] { Array(repeating: GridItem(.fixed(30), spacing: 8), count: 4) }

    var body: some View {
        Button { showing.toggle() } label: {
            Circle()
                .fill(color)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(.primary.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Color")
        .accessibilityLabel("Color")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(spacing: 12) {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(presets, id: \.self) { swatch in
                        swatchButton(swatch)
                    }
                }
                Divider()
                HStack {
                    Text("Custom…").font(.callout)
                    Spacer()
                    ColorPicker("", selection: $color).labelsHidden()
                }
            }
            .padding(14)
            .frame(width: 168)
        }
    }

    private func swatchButton(_ swatch: Color) -> some View {
        ZStack {
            if color == swatch {
                Circle().strokeBorder(Color.accentColor, lineWidth: 2.5).frame(width: 30, height: 30)
            }
            Circle()
                .fill(swatch)
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(.primary.opacity(0.15)))
        }
        .frame(width: 30, height: 30)
        .contentShape(Circle())
        .onTapGesture { color = swatch; showing = false }
    }
}
