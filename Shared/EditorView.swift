import SwiftUI

// The full editor. Hosted by the main app (full screen cover) and by the
// share extension (inside the share sheet) — identical experience in both.
struct EditorRootView: View {
    @ObservedObject var session: EditorSession
    let onFinished: (_ saved: Bool) -> Void

    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if session.documents.count > 1 {
                Filmstrip(session: session)
            }
            CanvasView(session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)
            EditorToolbar(session: session)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $session.editingShapeText) {
            if let id = session.selectedShapeID {
                ShapeTextSheet(session: session, shapeID: id)
                    .presentationDetents([.medium])
            }
        }
        .alert("Couldn't Save", isPresented: .init(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Button {
                onFinished(false)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.1), in: Circle())
            }

            Spacer()

            Button { session.undo() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .disabled(!session.canUndo)

            Button { session.redo() } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .disabled(!session.canRedo)

            Spacer()

            Button {
                save()
            } label: {
                Group {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .frame(minWidth: 64, minHeight: 40)
                .background(Color.white, in: Capsule())
                .foregroundColor(.black)
            }
            .disabled(isSaving)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func save() {
        isSaving = true
        session.commitActiveStroke()
        let documents = session.documents
        Task {
            do {
                let rendered = documents.map(Renderer.render)
                try await SaveService.save(rendered)
                isSaving = false
                onFinished(true)
            } catch {
                isSaving = false
                saveError = error.localizedDescription
            }
        }
    }
}

// MARK: - Filmstrip

struct Filmstrip: View {
    @ObservedObject var session: EditorSession

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(session.documents.enumerated()), id: \.element.id) { index, doc in
                    Image(uiImage: doc.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(index == session.selectedIndex ? Color.white : Color.white.opacity(0.2),
                                        lineWidth: index == session.selectedIndex ? 2 : 1)
                        )
                        .onTapGesture { session.selectDocument(index) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Toolbar

struct EditorToolbar: View {
    @ObservedObject var session: EditorSession

    var body: some View {
        VStack(spacing: 10) {
            contextualRow
                .frame(minHeight: 44)
            toolRow
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Color.white.opacity(0.06))
    }

    private var toolRow: some View {
        HStack {
            ForEach(Tool.allCases) { tool in
                Button {
                    session.tool = tool
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tool.systemImage)
                            .font(.system(size: 18, weight: .medium))
                        Text(tool.title)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        session.tool == tool ? Color.white.opacity(0.15) : .clear,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .foregroundColor(session.tool == tool ? .white : .white.opacity(0.55))
                }
            }
        }
    }

    @ViewBuilder
    private var contextualRow: some View {
        switch session.tool {
        case .pen:
            HStack(spacing: 14) {
                sizeDots(values: PenSize.allCases.map(\.rawValue),
                         selected: session.penSize.rawValue) { value in
                    if let size = PenSize(rawValue: value) { session.penSize = size }
                }
                divider
                colorDots
                divider
                Button {
                    session.axisLock.toggle()
                } label: {
                    Text("90°")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 44, height: 32)
                        .background(
                            session.axisLock ? Color.white : Color.white.opacity(0.1),
                            in: Capsule()
                        )
                        .foregroundColor(session.axisLock ? .black : .white)
                }
            }
        case .eraser:
            sizeDots(values: EraserSize.allCases.map(\.rawValue),
                     selected: session.eraserSize.rawValue) { value in
                if let size = EraserSize(rawValue: value) { session.eraserSize = size }
            }
        case .shape:
            HStack(spacing: 14) {
                ForEach(ShapeKind.allCases) { kind in
                    Button {
                        session.shapeKind = kind
                        if let id = session.selectedShapeID {
                            session.beginChange()
                            session.updateShape(id) { $0.kind = kind }
                        }
                    } label: {
                        Image(systemName: kind.systemImage)
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 36, height: 32)
                            .background(
                                session.shapeKind == kind ? Color.white.opacity(0.2) : .clear,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .foregroundColor(.white)
                    }
                }
                divider
                colorDots
                divider
                fillStyleButtons
                if session.selectedShapeID != nil {
                    divider
                    Button {
                        session.editingShapeText = true
                    } label: {
                        Image(systemName: "textformat")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 36, height: 32)
                            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundColor(.white)
                    }
                    Button(role: .destructive) {
                        session.deleteSelectedShape()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 36, height: 32)
                            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundColor(.red)
                    }
                }
            }
        case .crop:
            HStack(spacing: 16) {
                Button("Reset") { session.resetCrop() }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                Button {
                    session.applyCrop()
                } label: {
                    Text("Apply Crop")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                        .background(Color.white, in: Capsule())
                        .foregroundColor(.black)
                }
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(width: 1, height: 24)
    }

    private var colorDots: some View {
        HStack(spacing: 10) {
            ForEach(MarkupColor.allCases) { markupColor in
                Button {
                    session.color = markupColor
                    if session.tool == .shape, let id = session.selectedShapeID {
                        session.beginChange()
                        session.updateShape(id) { $0.color = markupColor }
                    }
                } label: {
                    Circle()
                        .fill(markupColor.color)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: session.color == markupColor ? 2.5 : 0)
                                .padding(-4)
                        )
                }
            }
        }
    }

    private var fillStyleButtons: some View {
        HStack(spacing: 8) {
            ForEach(ShapeFill.allCases) { style in
                Button {
                    session.fillStyle = style
                    if let id = session.selectedShapeID {
                        session.beginChange()
                        session.updateShape(id) { $0.fill = style }
                    }
                } label: {
                    fillPreview(style)
                        .frame(width: 26, height: 26)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white, lineWidth: session.fillStyle == style ? 2 : 0)
                                .padding(-3)
                        )
                }
            }
        }
    }

    @ViewBuilder
    private func fillPreview(_ style: ShapeFill) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        switch style {
        case .opaque:
            shape.fill(session.color.color)
        case .transparent:
            shape.fill(session.color.color.opacity(0.5))
        case .none:
            shape.strokeBorder(session.color.color, lineWidth: 2)
        }
    }

    private func sizeDots(values: [CGFloat], selected: CGFloat,
                          onSelect: @escaping (CGFloat) -> Void) -> some View {
        HStack(spacing: 12) {
            ForEach(values, id: \.self) { value in
                let maxValue = values.max() ?? 1
                let diameter = 8 + 16 * (value / maxValue)
                Button {
                    onSelect(value)
                } label: {
                    Circle()
                        .fill(Color.white)
                        .frame(width: diameter, height: diameter)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: selected == value ? 2 : 0)
                        )
                        .opacity(selected == value ? 1 : 0.5)
                }
            }
        }
    }
}
