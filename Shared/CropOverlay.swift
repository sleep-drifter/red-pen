import SwiftUI

struct CropOverlay: View {
    @ObservedObject var session: EditorSession
    let t: CanvasTransform

    private enum Handle: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    @State private var dragStartRect: CGRect?

    var body: some View {
        let doc = session.current
        let draft = session.cropDraft ?? doc.fullRect
        let r = t.toView(draft)

        ZStack {
            // Dim everything outside the crop rect.
            Path { path in
                path.addRect(t.viewBounds)
                path.addRect(r)
            }
            .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            Rectangle()
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
                .contentShape(Rectangle())
                .gesture(moveGesture(doc: doc, draft: draft))

            ForEach(Array(Handle.allCases.enumerated()), id: \.offset) { _, handle in
                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                    .shadow(radius: 2)
                    .position(position(of: handle, in: r))
                    .gesture(resizeGesture(handle, doc: doc))
            }
        }
    }

    private func position(of handle: Handle, in r: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: r.minX, y: r.minY)
        case .topRight: return CGPoint(x: r.maxX, y: r.minY)
        case .bottomLeft: return CGPoint(x: r.minX, y: r.maxY)
        case .bottomRight: return CGPoint(x: r.maxX, y: r.maxY)
        }
    }

    private func moveGesture(doc: MarkupDocument, draft: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartRect == nil { dragStartRect = draft }
                guard let start = dragStartRect else { return }
                var moved = start.offsetBy(dx: value.translation.width / t.scale,
                                           dy: value.translation.height / t.scale)
                moved.origin.x = min(max(moved.origin.x, 0), doc.fullRect.maxX - moved.width)
                moved.origin.y = min(max(moved.origin.y, 0), doc.fullRect.maxY - moved.height)
                session.cropDraft = moved
            }
            .onEnded { _ in dragStartRect = nil }
    }

    private func resizeGesture(_ handle: Handle, doc: MarkupDocument) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartRect == nil { dragStartRect = session.cropDraft ?? doc.fullRect }
                guard let start = dragStartRect else { return }
                let p = clamp(t.toImage(value.location), to: doc.fullRect)
                let minSide = 40 * doc.pointScale

                var minX = start.minX, minY = start.minY
                var maxX = start.maxX, maxY = start.maxY
                switch handle {
                case .topLeft:
                    minX = min(p.x, maxX - minSide); minY = min(p.y, maxY - minSide)
                case .topRight:
                    maxX = max(p.x, minX + minSide); minY = min(p.y, maxY - minSide)
                case .bottomLeft:
                    minX = min(p.x, maxX - minSide); maxY = max(p.y, minY + minSide)
                case .bottomRight:
                    maxX = max(p.x, minX + minSide); maxY = max(p.y, minY + minSide)
                }
                session.cropDraft = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            }
            .onEnded { _ in dragStartRect = nil }
    }

    private func clamp(_ p: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, rect.minX), rect.maxX),
                y: min(max(p.y, rect.minY), rect.maxY))
    }
}
