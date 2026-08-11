import SwiftUI
import UIKit

// MARK: - Tools

enum Tool: String, CaseIterable, Identifiable {
    case pen, eraser, shape, crop

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .pen: return "pencil.tip"
        case .eraser: return "eraser"
        case .shape: return "character.textbox"
        case .crop: return "crop"
        }
    }

    var title: String {
        switch self {
        case .pen: return "Pen"
        case .eraser: return "Eraser"
        case .shape: return "Shape"
        case .crop: return "Crop"
        }
    }
}

// Detented pen sizes, in on-screen points of the original screenshot.
enum PenSize: CGFloat, CaseIterable, Identifiable {
    case small = 3
    case medium = 6
    case large = 10
    case extraLarge = 16

    var id: CGFloat { rawValue }

    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }
}

enum EraserSize: CGFloat, CaseIterable, Identifiable {
    case small = 10
    case medium = 20
    case large = 32
    case extraLarge = 48

    var id: CGFloat { rawValue }

    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }
}

// MARK: - Colors

enum MarkupColor: String, CaseIterable, Identifiable {
    case red, blue, green, yellow

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var uiColor: UIColor {
        switch self {
        case .red: return UIColor(red: 1.00, green: 0.23, blue: 0.19, alpha: 1)
        case .blue: return UIColor(red: 0.04, green: 0.52, blue: 1.00, alpha: 1)
        case .green: return UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1)
        case .yellow: return UIColor(red: 1.00, green: 0.80, blue: 0.00, alpha: 1)
        }
    }

    var color: Color { Color(uiColor: uiColor) }

    // Highest-contrast text color (black or white) against this color,
    // by relative luminance. The app drives this; it is never user-editable.
    var prefersBlackText: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance > 0.5
    }

    var textUIColor: UIColor { prefersBlackText ? .black : .white }
    var textColor: Color { prefersBlackText ? .black : .white }
}

// MARK: - Fill styles

enum ShapeFill: String, CaseIterable, Identifiable {
    case opaque
    case transparent // 50% fill
    case none        // no fill; color becomes a 2pt stroke

    var id: String { rawValue }

    var title: String {
        switch self {
        case .opaque: return "Opaque"
        case .transparent: return "50% Transparent"
        case .none: return "No Fill (Outline)"
        }
    }

    var systemImage: String {
        switch self {
        case .opaque: return "square.fill"
        case .transparent: return "square.lefthalf.filled"
        case .none: return "square"
        }
    }
}

// MARK: - Shapes

enum ShapeKind: String, CaseIterable, Identifiable {
    case roundedRectangle
    case rectangle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .roundedRectangle: return "Rounded Rectangle"
        case .rectangle: return "Rectangle"
        }
    }

    var systemImage: String {
        switch self {
        case .roundedRectangle: return "app"
        case .rectangle: return "square"
        }
    }
}

enum TextAlignmentChoice: String, CaseIterable, Identifiable {
    case left, center

    var id: String { rawValue }
}

// The four detented font styles; sizes can then be nudged in 4pt increments.
enum FontPreset: CGFloat, CaseIterable, Identifiable {
    case small = 12
    case medium = 18
    case large = 24
    case extraLarge = 40

    var id: CGFloat { rawValue }
}

let fontNudgeStep: CGFloat = 4
let fontSizeRange: ClosedRange<CGFloat> = 8...120

// MARK: - Annotations

// All annotation geometry is stored in image space (points of the source image).
struct Stroke: Identifiable {
    let id = UUID()
    var points: [CGPoint]
    var width: CGFloat // image-space width, pointScale already applied
    var color: MarkupColor
    var isEraser: Bool
}

struct ShapeAnnotation: Identifiable {
    let id = UUID()
    var kind: ShapeKind
    var rect: CGRect
    var color: MarkupColor
    var fill: ShapeFill
    var text: String = ""
    var alignment: TextAlignmentChoice = .center
    var fontSize: CGFloat = FontPreset.medium.rawValue

    func cornerRadius(pointScale: CGFloat) -> CGFloat {
        guard kind == .roundedRectangle else { return 0 }
        return min(12 * pointScale, min(rect.width, rect.height) / 4)
    }
}

// MARK: - Document

struct MarkupDocument: Identifiable {
    let id = UUID()
    var image: UIImage
    var assetIdentifier: String?

    var strokes: [Stroke] = []
    var shapes: [ShapeAnnotation] = []
    var cropRect: CGRect? // nil = uncropped

    struct Snapshot {
        var strokes: [Stroke]
        var shapes: [ShapeAnnotation]
        var cropRect: CGRect?
    }

    private(set) var undoStack: [Snapshot] = []
    private(set) var redoStack: [Snapshot] = []

    init(image: UIImage, assetIdentifier: String? = nil) {
        self.image = image
        self.assetIdentifier = assetIdentifier
    }

    var fullRect: CGRect { CGRect(origin: .zero, size: image.size) }

    // Screenshots typically load at scale 1 with pixel dimensions, so a "6pt"
    // pen would be invisibly thin. Normalize sizes so detents read as on-screen
    // points of the original device.
    var pointScale: CGFloat {
        max(1, max(image.size.width, image.size.height) / 844)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private var snapshot: Snapshot {
        Snapshot(strokes: strokes, shapes: shapes, cropRect: cropRect)
    }

    mutating func pushUndoSnapshot() {
        undoStack.append(snapshot)
        redoStack.removeAll()
    }

    mutating func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(snapshot)
        restore(last)
    }

    mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot)
        restore(next)
    }

    private mutating func restore(_ s: Snapshot) {
        strokes = s.strokes
        shapes = s.shapes
        cropRect = s.cropRect
    }
}
