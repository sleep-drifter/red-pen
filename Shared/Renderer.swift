import UIKit

// Renders a document (image + strokes + shapes, cropped) into a final UIImage
// with CoreGraphics, matching the on-screen SwiftUI presentation.
enum Renderer {
    static func render(_ doc: MarkupDocument) -> UIImage {
        let full = doc.fullRect
        let crop = doc.cropRect ?? full

        let format = UIGraphicsImageRendererFormat()
        format.scale = doc.image.scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: crop.size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: -crop.minX, y: -crop.minY)

            doc.image.draw(in: full)
            drawStrokes(doc.strokes, in: cg)
            for shape in doc.shapes {
                draw(shape, pointScale: doc.pointScale, in: cg)
            }
        }
    }

    // Pen + eraser composite in a transparency layer so .clear erases ink only.
    private static func drawStrokes(_ strokes: [Stroke], in cg: CGContext) {
        guard !strokes.isEmpty else { return }
        cg.saveGState()
        cg.beginTransparencyLayer(auxiliaryInfo: nil)
        for stroke in strokes {
            cg.setBlendMode(stroke.isEraser ? .clear : .normal)
            let color = stroke.isEraser ? UIColor.black : stroke.color.uiColor

            if stroke.points.count == 1, let p = stroke.points.first {
                cg.setFillColor(color.cgColor)
                cg.fillEllipse(in: CGRect(x: p.x - stroke.width / 2, y: p.y - stroke.width / 2,
                                          width: stroke.width, height: stroke.width))
            } else {
                cg.setStrokeColor(color.cgColor)
                cg.setLineWidth(stroke.width)
                cg.setLineCap(.round)
                cg.setLineJoin(.round)
                cg.beginPath()
                cg.addLines(between: stroke.points)
                cg.strokePath()
            }
        }
        cg.setBlendMode(.normal)
        cg.endTransparencyLayer()
        cg.restoreGState()
    }

    private static func draw(_ shape: ShapeAnnotation, pointScale: CGFloat, in cg: CGContext) {
        let radius = shape.cornerRadius(pointScale: pointScale)
        let strokeWidth = 2 * pointScale

        switch shape.fill {
        case .opaque:
            let path = UIBezierPath(roundedRect: shape.rect, cornerRadius: radius)
            shape.color.uiColor.setFill()
            path.fill()
        case .transparent:
            let path = UIBezierPath(roundedRect: shape.rect, cornerRadius: radius)
            shape.color.uiColor.withAlphaComponent(0.5).setFill()
            path.fill()
        case .none:
            let inset = shape.rect.insetBy(dx: strokeWidth / 2, dy: strokeWidth / 2)
            let path = UIBezierPath(roundedRect: inset,
                                    cornerRadius: max(0, radius - strokeWidth / 2))
            path.lineWidth = strokeWidth
            shape.color.uiColor.setStroke()
            path.stroke()
        }

        guard !shape.text.isEmpty else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = shape.alignment == .left ? .left : .center
        paragraph.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: shape.fontSize * pointScale, weight: .semibold),
            .foregroundColor: shape.color.textUIColor,
            .paragraphStyle: paragraph,
        ]
        let attributed = NSAttributedString(string: shape.text, attributes: attributes)

        let inset = shape.rect.insetBy(dx: 8 * pointScale, dy: 8 * pointScale)
        guard inset.width > 0, inset.height > 0 else { return }

        let bounding = attributed.boundingRect(
            with: CGSize(width: inset.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            context: nil
        )
        let textRect = CGRect(
            x: inset.minX,
            y: inset.minY + max(0, (inset.height - bounding.height) / 2),
            width: inset.width,
            height: min(bounding.height, inset.height)
        )
        attributed.draw(with: textRect, options: [.usesLineFragmentOrigin], context: nil)
    }
}
