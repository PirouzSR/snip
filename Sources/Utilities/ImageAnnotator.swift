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

    @State private var workingImage: NSImage
    @State private var annotations: [Annotation] = []
    @State private var redoStack: [Annotation] = []
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
    @State private var cropDragStart: CGPoint?

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
                Text("Drag to crop")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { cropping = false; cropRect = .zero }
                Button("Apply Crop") { applyCrop() }
                    .buttonStyle(.borderedProminent)
                    .disabled(cropRect.width < 4 || cropRect.height < 4)
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
                Button { cropping = true; cropRect = .zero } label: {
                    Image(systemName: "crop").frame(width: 26, height: 26)
                }
                .buttonStyle(.plain).help("Crop").accessibilityLabel("Crop")
                Divider().frame(height: 18)
                ColorSwatchPicker(color: $color)
                Slider(value: $width, in: 1...24).frame(width: 80)
                Divider().frame(height: 18)
                Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.plain).disabled(annotations.isEmpty).accessibilityLabel("Undo")
                Button { redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .buttonStyle(.plain).disabled(redoStack.isEmpty).accessibilityLabel("Redo")
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
            ZStack {
                Image(nsImage: workingImage)
                    .resizable()
                    .interpolation(.high)
                AnnotationsLayer(annotations: annotations, current: current, editingTextID: editingTextID)
                if cropping { cropOverlay }
            }
            // Gesture, drawing layer, and text overlay all share this fitted coordinate
            // space (origin at the image's top-left). Centering is done by the outer
            // flexible frame so the drag location matches where the canvas draws.
            .frame(width: fitted.width, height: fitted.height)
            .contentShape(Rectangle())
            .gesture(unifiedGesture)
            .overlay(textEditors)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { canvasSize = fitted }
            .onChange(of: fitted) { _, newValue in canvasSize = newValue }
        }
        .padding(12)
    }

    private func fittedSize(in available: CGSize) -> CGSize {
        let aspect = workingImage.size.width / max(workingImage.size.height, 1)
        var w = available.width
        var h = w / aspect
        if h > available.height { h = available.height; w = h * aspect }
        return CGSize(width: max(w, 1), height: max(h, 1))
    }

    // MARK: Crop overlay

    private var cropOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .overlay {
                    Rectangle().path(in: cropRect).fill(Color.black).blendMode(.destinationOut)
                }
                .compositingGroup()
            if cropRect.width > 1 {
                Rectangle()
                    .strokeBorder(.white, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .frame(width: cropRect.width, height: cropRect.height)
                    .position(x: cropRect.midX, y: cropRect.midY)
            }
        }
    }

    // MARK: Unified drag gesture (draw or crop depending on mode)

    private var unifiedGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if cropping {
                    cropRect = CGRect(origin: value.startLocation, size: .zero)
                        .union(CGRect(origin: value.location, size: .zero))
                    return
                }
                handleDrawChanged(value)
            }
            .onEnded { value in
                if cropping { return }
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
                .multilineTextAlignment(.center)
                .focused($textFocused)
                .fixedSize()
                .position(annotations[idx].start)
                .onSubmit { commitText() }
                .onChange(of: textFocused) { _, focused in if !focused { commitText() } }
        }
    }

    private func handleDrawChanged(_ value: DragGesture.Value) {
        guard tool != .text else { return }   // text is placed on tap (ended)
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
            placeText(at: value.location)
            return
        }
        if let annot = current {
            annotations.append(annot)
            redoStack.removeAll()
        }
        current = nil
    }

    // MARK: Editing operations

    private func placeText(at point: CGPoint) {
        commitText()   // finish any in-progress field first
        var annot = Annotation(tool: .text, colorRGBA: rgba(of: color), width: width)
        annot.start = point
        annotations.append(annot)
        redoStack.removeAll()
        editingTextID = annot.id
        textFocused = true
    }

    private func commitText() {
        guard let id = editingTextID else { return }
        if let idx = annotations.firstIndex(where: { $0.id == id }),
           annotations[idx].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            annotations.remove(at: idx)   // discard empty text boxes
        }
        editingTextID = nil
    }

    private func undo() {
        guard let last = annotations.popLast() else { return }
        redoStack.append(last)
    }

    private func redo() {
        guard let last = redoStack.popLast() else { return }
        annotations.append(last)
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
        guard cropRect.width >= 4, cropRect.height >= 4 else { cropping = false; return }
        guard let flat = renderFlattened(), let cg = flat.cgImage else { cropping = false; return }
        // Map crop rect (canvas points, top-left) into image pixels. CGImage cropping uses
        // an upper-left origin, matching the canvas coordinate space.
        let scale = CGFloat(cg.width) / max(canvasSize.width, 1)
        let pxRect = CGRect(x: cropRect.minX * scale, y: cropRect.minY * scale,
                            width: cropRect.width * scale, height: cropRect.height * scale)
            .integral
        if let cropped = cg.cropping(to: pxRect) {
            let pointSize = NSSize(width: pxRect.width / scale, height: pxRect.height / scale)
            workingImage = NSImage(cgImage: cropped, size: pointSize)
            annotations.removeAll()
            redoStack.removeAll()
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
            ctx.draw(text, at: annot.start, anchor: .center)
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
