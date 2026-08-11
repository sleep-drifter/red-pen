import SwiftUI
import UIKit

@MainActor
final class EditorSession: ObservableObject, Identifiable {
    let id = UUID()

    @Published var documents: [MarkupDocument]
    @Published var selectedIndex: Int = 0

    // Tool state is shared across all documents in the session.
    @Published var tool: Tool = .pen {
        didSet {
            if tool != .shape { selectedShapeID = nil }
            if tool == .crop { prepareCropDraft() }
        }
    }
    @Published var penSize: PenSize = .medium
    @Published var eraserSize: EraserSize = .medium
    @Published var color: MarkupColor = .red
    @Published var fillStyle: ShapeFill = .opaque
    @Published var shapeKind: ShapeKind = .roundedRectangle
    @Published var axisLock: Bool = false // draw at 90° only

    @Published var selectedShapeID: UUID?
    @Published var editingShapeText = false
    @Published var activeStroke: Stroke?
    @Published var cropDraft: CGRect?

    init(images: [(image: UIImage, assetIdentifier: String?)]) {
        self.documents = images.map {
            MarkupDocument(image: $0.image, assetIdentifier: $0.assetIdentifier)
        }
    }

    var current: MarkupDocument {
        get { documents[selectedIndex] }
        set { documents[selectedIndex] = newValue }
    }

    var selectedShape: ShapeAnnotation? {
        guard let id = selectedShapeID else { return nil }
        return current.shapes.first { $0.id == id }
    }

    func selectDocument(_ index: Int) {
        guard index != selectedIndex, documents.indices.contains(index) else { return }
        activeStroke = nil
        selectedShapeID = nil
        selectedIndex = index
        if tool == .crop { prepareCropDraft() }
    }

    // MARK: - Undo / redo

    func beginChange() {
        current.pushUndoSnapshot()
    }

    func undo() {
        activeStroke = nil // a multi-finger tap can leave a half-started stroke; discard it
        current.undo()
        selectedShapeID = nil
        if tool == .crop { prepareCropDraft() }
    }

    func redo() {
        activeStroke = nil
        current.redo()
        selectedShapeID = nil
        if tool == .crop { prepareCropDraft() }
    }

    var canUndo: Bool { current.canUndo }
    var canRedo: Bool { current.canRedo }

    // MARK: - Strokes

    func commitActiveStroke() {
        defer { activeStroke = nil }
        guard let stroke = activeStroke, !stroke.points.isEmpty else { return }
        beginChange()
        current.strokes.append(stroke)
    }

    // MARK: - Shapes

    func addShape(rect: CGRect) {
        beginChange()
        let shape = ShapeAnnotation(kind: shapeKind, rect: rect, color: color, fill: fillStyle)
        current.shapes.append(shape)
        selectedShapeID = shape.id
    }

    func updateShape(_ id: UUID, _ transform: (inout ShapeAnnotation) -> Void) {
        guard let index = current.shapes.firstIndex(where: { $0.id == id }) else { return }
        transform(&current.shapes[index])
    }

    func deleteSelectedShape() {
        guard let id = selectedShapeID else { return }
        beginChange()
        current.shapes.removeAll { $0.id == id }
        selectedShapeID = nil
    }

    func shapeBinding(for id: UUID) -> Binding<ShapeAnnotation>? {
        guard current.shapes.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { [weak self] in
                self?.current.shapes.first { $0.id == id }
                    ?? ShapeAnnotation(kind: .rectangle, rect: .zero, color: .red, fill: .opaque)
            },
            set: { [weak self] newValue in
                self?.updateShape(id) { $0 = newValue }
            }
        )
    }

    // MARK: - Crop

    func prepareCropDraft() {
        cropDraft = current.cropRect ?? current.fullRect
    }

    func applyCrop() {
        guard let draft = cropDraft else { return }
        beginChange()
        let full = current.fullRect
        let clamped = draft.intersection(full)
        current.cropRect = clamped.isAlmostEqual(to: full) ? nil : clamped
        tool = .pen
    }

    func resetCrop() {
        cropDraft = current.fullRect
    }
}

extension CGRect {
    func isAlmostEqual(to other: CGRect, tolerance: CGFloat = 1) -> Bool {
        abs(minX - other.minX) < tolerance &&
        abs(minY - other.minY) < tolerance &&
        abs(width - other.width) < tolerance &&
        abs(height - other.height) < tolerance
    }
}
