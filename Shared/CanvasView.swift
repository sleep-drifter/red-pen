import SwiftUI
import UIKit

// Maps between image space (annotation storage) and view space (display).
struct CanvasTransform {
    var visibleRect: CGRect // image-space region currently displayed
    var scale: CGFloat
    var origin: CGPoint // view-space origin of visibleRect

    init(visibleRect: CGRect, viewSize: CGSize) {
        self.visibleRect = visibleRect
        let s = min(viewSize.width / max(visibleRect.width, 1),
                    viewSize.height / max(visibleRect.height, 1))
        self.scale = s
        self.origin = CGPoint(
            x: (viewSize.width - visibleRect.width * s) / 2,
            y: (viewSize.height - visibleRect.height * s) / 2
        )
    }

    func toView(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - visibleRect.minX) * scale + origin.x,
                y: (p.y - visibleRect.minY) * scale + origin.y)
    }

    func toView(_ r: CGRect) -> CGRect {
        let o = toView(r.origin)
        return CGRect(x: o.x, y: o.y, width: r.width * scale, height: r.height * scale)
    }

    func toImage(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - origin.x) / scale + visibleRect.minX,
                y: (p.y - origin.y) / scale + visibleRect.minY)
    }

    var viewBounds: CGRect {
        CGRect(origin: origin,
               size: CGSize(width: visibleRect.width * scale, height: visibleRect.height * scale))
    }
}

struct CanvasView: View {
    @ObservedObject var session: EditorSession

    @State private var draftShapeRect: CGRect?
    @State private var moveStartRect: CGRect?
    @State private var resizeStartRect: CGRect?

    var body: some View {
        GeometryReader { geo in
            let doc = session.current
            let visible = session.tool == .crop ? doc.fullRect : (doc.cropRect ?? doc.fullRect)
            let t = CanvasTransform(visibleRect: visible, viewSize: geo.size)

            ZStack {
                strokesLayer(doc: doc, t: t)
                    .contentShape(Rectangle())
                    .gesture(drawGesture(doc: doc, t: t))
                    .gesture(MultiFingerTapGesture(fingers: 2) { session.undo() })
                    .gesture(MultiFingerTapGesture(fingers: 3) { session.redo() })

                ForEach(doc.shapes) { shape in
                    shapeView(shape, doc: doc, t: t)
                }

                if let draft = draftShapeRect {
                    let preview = ShapeAnnotation(kind: session.shapeKind, rect: draft,
                                                  color: session.color, fill: session.fillStyle)
                    ShapeBody(shape: preview, pointScale: doc.pointScale, t: t)
                        .allowsHitTesting(false)
                }

                if session.tool == .shape, let selected = session.selectedShape {
                    selectionOverlay(for: selected, t: t)
                }

                if session.tool == .crop {
                    CropOverlay(session: session, t: t)
                }
            }
        }
        .clipped()
    }

    // MARK: - Strokes

    private func strokesLayer(doc: MarkupDocument, t: CanvasTransform) -> some View {
        Canvas { context, _ in
            let clip = Path(t.viewBounds)
            context.clip(to: clip)
            context.draw(Image(uiImage: doc.image), in: t.toView(doc.fullRect))

            // Pen and eraser composite inside one layer so the eraser only
            // removes ink, never the screenshot underneath.
            context.drawLayer { layer in
                layer.clip(to: clip)
                var strokes = doc.strokes
                if let active = session.activeStroke { strokes.append(active) }
                for stroke in strokes {
                    draw(stroke, in: &layer, t: t)
                }
            }
        }
    }

    private func draw(_ stroke: Stroke, in layer: inout GraphicsContext, t: CanvasTransform) {
        layer.blendMode = stroke.isEraser ? .clear : .normal
        let width = stroke.width * t.scale
        let color = stroke.isEraser ? Color.black : stroke.color.color

        if stroke.points.count == 1, let p = stroke.points.first {
            let v = t.toView(p)
            let dot = CGRect(x: v.x - width / 2, y: v.y - width / 2, width: width, height: width)
            layer.fill(Path(ellipseIn: dot), with: .color(color))
        } else {
            var path = Path()
            path.addLines(stroke.points.map(t.toView))
            layer.stroke(path, with: .color(color),
                         style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
    }

    private func drawGesture(doc: MarkupDocument, t: CanvasTransform) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = clamp(t.toImage(value.startLocation), to: doc.fullRect)
                let point = clamp(t.toImage(value.location), to: doc.fullRect)

                switch session.tool {
                case .pen:
                    let end = session.axisLock ? snapTo90(point, from: start) : point
                    if session.axisLock {
                        session.activeStroke = Stroke(points: [start, end],
                                                      width: session.penSize.rawValue * doc.pointScale,
                                                      color: session.color, isEraser: false)
                    } else if session.activeStroke == nil {
                        session.activeStroke = Stroke(points: [start, end],
                                                      width: session.penSize.rawValue * doc.pointScale,
                                                      color: session.color, isEraser: false)
                    } else {
                        session.activeStroke?.points.append(end)
                    }
                case .eraser:
                    if session.activeStroke == nil {
                        session.activeStroke = Stroke(points: [start, point],
                                                      width: session.eraserSize.rawValue * doc.pointScale,
                                                      color: .red, isEraser: true)
                    } else {
                        session.activeStroke?.points.append(point)
                    }
                case .shape:
                    draftShapeRect = normalizedRect(from: start, to: point)
                case .crop:
                    break
                }
            }
            .onEnded { value in
                switch session.tool {
                case .pen, .eraser:
                    session.commitActiveStroke()
                case .shape:
                    defer { draftShapeRect = nil }
                    let minSide = 24 * doc.pointScale
                    if let draft = draftShapeRect, draft.width > minSide / 2 || draft.height > minSide / 2 {
                        var rect = draft
                        rect.size.width = max(rect.width, minSide)
                        rect.size.height = max(rect.height, minSide)
                        session.addShape(rect: rect)
                    } else {
                        session.selectedShapeID = nil // tap on empty canvas deselects
                    }
                case .crop:
                    break
                }
            }
    }

    // MARK: - Shapes

    @ViewBuilder
    private func shapeView(_ shape: ShapeAnnotation, doc: MarkupDocument, t: CanvasTransform) -> some View {
        ShapeBody(shape: shape, pointScale: doc.pointScale, t: t)
            .contentShape(Rectangle())
            .allowsHitTesting(session.tool == .shape)
            .onTapGesture(count: 2) {
                session.selectedShapeID = shape.id
                session.editingShapeText = true
            }
            .onTapGesture {
                session.selectedShapeID = shape.id
            }
            .gesture(moveGesture(for: shape.id, doc: doc, t: t))
    }

    private func moveGesture(for id: UUID, doc: MarkupDocument, t: CanvasTransform) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if moveStartRect == nil {
                    session.selectedShapeID = id
                    session.beginChange()
                    moveStartRect = session.selectedShape?.rect
                }
                guard let start = moveStartRect else { return }
                let dx = value.translation.width / t.scale
                let dy = value.translation.height / t.scale
                let moved = start.offsetBy(dx: dx, dy: dy)
                session.updateShape(id) { $0.rect = clamp(rect: moved, within: doc.fullRect) }
            }
            .onEnded { _ in moveStartRect = nil }
    }

    @ViewBuilder
    private func selectionOverlay(for shape: ShapeAnnotation, t: CanvasTransform) -> some View {
        let r = t.toView(shape.rect)

        Rectangle()
            .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            .frame(width: r.width, height: r.height)
            .position(x: r.midX, y: r.midY)
            .allowsHitTesting(false)

        Circle()
            .fill(Color.white)
            .frame(width: 18, height: 18)
            .shadow(radius: 2)
            .position(x: r.maxX, y: r.maxY)
            .gesture(resizeGesture(for: shape.id, t: t))
    }

    private func resizeGesture(for id: UUID, t: CanvasTransform) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if resizeStartRect == nil {
                    session.beginChange()
                    resizeStartRect = session.selectedShape?.rect
                }
                guard let start = resizeStartRect else { return }
                let doc = session.current
                let minSide = 24 * doc.pointScale
                let corner = clamp(t.toImage(value.location), to: doc.fullRect)
                session.updateShape(id) {
                    $0.rect = CGRect(
                        x: start.minX,
                        y: start.minY,
                        width: max(minSide, corner.x - start.minX),
                        height: max(minSide, corner.y - start.minY)
                    )
                }
            }
            .onEnded { _ in resizeStartRect = nil }
    }

    // MARK: - Geometry helpers

    private func snapTo90(_ p: CGPoint, from start: CGPoint) -> CGPoint {
        abs(p.x - start.x) >= abs(p.y - start.y)
            ? CGPoint(x: p.x, y: start.y)
            : CGPoint(x: start.x, y: p.y)
    }

    private func normalizedRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func clamp(_ p: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, rect.minX), rect.maxX),
                y: min(max(p.y, rect.minY), rect.maxY))
    }

    private func clamp(rect: CGRect, within bounds: CGRect) -> CGRect {
        var r = rect
        r.origin.x = min(max(r.origin.x, bounds.minX - r.width / 2), bounds.maxX - r.width / 2)
        r.origin.y = min(max(r.origin.y, bounds.minY - r.height / 2), bounds.maxY - r.height / 2)
        return r
    }
}

// Undo/redo are gesture-driven: two-finger tap = undo, three-finger tap = redo.
// UIGestureRecognizerRepresentable bridges a real multi-touch tap recognizer
// into SwiftUI, which single-touch SwiftUI gestures can't express.
struct MultiFingerTapGesture: UIGestureRecognizerRepresentable {
    let fingers: Int
    let action: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UITapGestureRecognizer {
        let recognizer = UITapGestureRecognizer()
        recognizer.numberOfTapsRequired = 1
        recognizer.numberOfTouchesRequired = fingers
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UITapGestureRecognizer, context: Context) {
        if recognizer.state == .ended {
            action()
        }
    }
}

// Renders a shape annotation (fill/stroke + auto-contrast text) in view space.
struct ShapeBody: View {
    let shape: ShapeAnnotation
    let pointScale: CGFloat
    let t: CanvasTransform

    var body: some View {
        let r = t.toView(shape.rect)
        let radius = shape.cornerRadius(pointScale: pointScale) * t.scale
        let base = RoundedRectangle(cornerRadius: radius, style: .continuous)

        ZStack {
            switch shape.fill {
            case .opaque:
                base.fill(shape.color.color)
            case .transparent:
                base.fill(shape.color.color.opacity(0.5))
            case .none:
                base.strokeBorder(shape.color.color, lineWidth: 2 * pointScale * t.scale)
            }

            if !shape.text.isEmpty {
                Text(shape.text)
                    .font(.system(size: shape.fontSize * pointScale * t.scale, weight: .semibold))
                    .foregroundColor(shape.textColor)
                    .multilineTextAlignment(shape.alignment == .left ? .leading : .center)
                    .frame(maxWidth: .infinity,
                           alignment: shape.alignment == .left ? .leading : .center)
                    .padding(8 * pointScale * t.scale)
            }
        }
        .frame(width: r.width, height: r.height)
        .position(x: r.midX, y: r.midY)
    }
}

private extension ShapeAnnotation {
    var textColor: Color { color.textColor }
}
