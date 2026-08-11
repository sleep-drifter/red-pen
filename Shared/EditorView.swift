import SwiftUI

// The full editor. Hosted by the main app (full screen cover) and by the
// share extension (inside the share sheet) — identical experience in both.
//
// All chrome is native: NavigationStack with system top/bottom toolbars,
// a segmented tool picker, and menus for per-tool options.
struct EditorRootView: View {
    @ObservedObject var session: EditorSession
    let onFinished: (_ saved: Bool) -> Void

    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if session.documents.count > 1 {
                    Filmstrip(session: session)
                }
                CanvasView(session: session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(8)
            }
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
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

    // MARK: - Toolbars

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { onFinished(false) }
        }

        ToolbarItem(placement: .confirmationAction) {
            if isSaving {
                ProgressView()
            } else {
                Button("Save") { save() }
                    .fontWeight(.semibold)
            }
        }

        ToolbarItemGroup(placement: .bottomBar) {
            if session.tool == .crop {
                Button("Reset") { session.resetCrop() }
                Spacer()
                toolPicker
                Spacer()
                Button("Apply") { session.applyCrop() }
                    .fontWeight(.semibold)
            } else {
                toolPicker
                Spacer()
                optionsMenu
            }
        }
    }

    private var toolPicker: some View {
        Picker("Tool", selection: $session.tool) {
            ForEach(Tool.allCases) { tool in
                Label(tool.title, systemImage: tool.systemImage)
                    .tag(tool)
            }
        }
        .pickerStyle(.segmented)
    }

    private var optionsMenu: some View {
        Menu {
            switch session.tool {
            case .pen:
                Picker("Size", selection: $session.penSize) {
                    ForEach(PenSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                Picker("Color", selection: colorBinding) {
                    ForEach(MarkupColor.allCases) { color in
                        Text(color.title).tag(color)
                    }
                }
                Toggle("90° Lines Only", isOn: $session.axisLock)
            case .eraser:
                Picker("Size", selection: $session.eraserSize) {
                    ForEach(EraserSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
            case .shape:
                Picker("Shape", selection: shapeKindBinding) {
                    ForEach(ShapeKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.systemImage).tag(kind)
                    }
                }
                Picker("Color", selection: colorBinding) {
                    ForEach(MarkupColor.allCases) { color in
                        Text(color.title).tag(color)
                    }
                }
                Picker("Fill", selection: fillBinding) {
                    ForEach(ShapeFill.allCases) { fill in
                        Label(fill.title, systemImage: fill.systemImage).tag(fill)
                    }
                }
                if session.selectedShapeID != nil {
                    Divider()
                    Button("Edit Text…", systemImage: "textformat") {
                        session.editingShapeText = true
                    }
                    Button("Delete Shape", systemImage: "trash", role: .destructive) {
                        session.deleteSelectedShape()
                    }
                }
            case .crop:
                EmptyView()
            }
        } label: {
            Label("Options", systemImage: "slider.horizontal.3")
        }
    }

    // Option bindings write the session default and, when a shape is
    // selected, restyle that shape too (with an undo snapshot).
    private var colorBinding: Binding<MarkupColor> {
        Binding(
            get: { session.color },
            set: { newValue in
                session.color = newValue
                applyToSelectedShape { $0.color = newValue }
            }
        )
    }

    private var fillBinding: Binding<ShapeFill> {
        Binding(
            get: { session.fillStyle },
            set: { newValue in
                session.fillStyle = newValue
                applyToSelectedShape { $0.fill = newValue }
            }
        )
    }

    private var shapeKindBinding: Binding<ShapeKind> {
        Binding(
            get: { session.shapeKind },
            set: { newValue in
                session.shapeKind = newValue
                applyToSelectedShape { $0.kind = newValue }
            }
        )
    }

    private func applyToSelectedShape(_ transform: @escaping (inout ShapeAnnotation) -> Void) {
        guard session.tool == .shape, let id = session.selectedShapeID else { return }
        session.beginChange()
        session.updateShape(id, transform)
    }

    // MARK: - Saving

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
                                .stroke(index == session.selectedIndex ? Color.accentColor : Color(.separator),
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
