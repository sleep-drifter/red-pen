import SwiftUI
import PhotosUI

struct HomeView: View {
    @State private var selection: [PhotosPickerItem] = []
    @State private var session: EditorSession?
    @State private var isLoading = false

    @State private var deleteCandidates: [String] = []
    @State private var showDeleteOffer = false
    @State private var deleteError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    pickerButton
                    workflowCard
                    pinCard
                }
                .padding(20)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Red Pen")
        }
        .fullScreenCover(item: $session) { activeSession in
            EditorRootView(session: activeSession) { saved in
                let identifiers = activeSession.documents.compactMap(\.assetIdentifier)
                session = nil
                if saved, !identifiers.isEmpty {
                    deleteCandidates = identifiers
                    showDeleteOffer = true
                }
            }
        }
        .confirmationDialog(
            "Edited copies saved. Delete the \(deleteCandidates.count) original screenshot\(deleteCandidates.count == 1 ? "" : "s")?",
            isPresented: $showDeleteOffer,
            titleVisibility: .visible
        ) {
            Button("Delete Originals", role: .destructive) {
                let identifiers = deleteCandidates
                Task {
                    do {
                        try await SaveService.deleteOriginals(identifiers: identifiers)
                    } catch {
                        deleteError = error.localizedDescription
                    }
                }
            }
            Button("Keep Originals", role: .cancel) {}
        }
        .alert("Couldn't Delete", isPresented: .init(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
        .onChange(of: selection) { _, items in
            guard !items.isEmpty else { return }
            loadSelection(items)
        }
    }

    private var header: some View {
        Text("Mark up screenshots fast. Pen, shapes, crop — then save and move on.")
            .font(.system(size: 17))
            .foregroundColor(.white.opacity(0.7))
    }

    private var pickerButton: some View {
        PhotosPicker(
            selection: $selection,
            maxSelectionCount: 10,
            matching: .images,
            photoLibrary: .shared()
        ) {
            HStack {
                Image(systemName: "photo.on.rectangle.angled")
                Text(isLoading ? "Loading…" : "Pick Screenshots")
                    .font(.system(size: 17, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .foregroundColor(.black)
        }
        .disabled(isLoading)
    }

    private var workflowCard: some View {
        card(
            title: "The zero-original workflow",
            icon: "bolt.fill",
            lines: [
                "1. Take a screenshot.",
                "2. Tap the screenshot thumbnail, then the share icon.",
                "3. Pick Red Pen, mark it up, hit Save.",
                "4. Close the preview and choose Delete Screenshot.",
            ],
            footnote: "The original never lands in your photo library — only the marked-up copy does."
        )
    }

    private var pinCard: some View {
        card(
            title: "Put Red Pen up front in the share sheet",
            icon: "square.and.arrow.up",
            lines: [
                "1. Open any share sheet and scroll the app row to the end.",
                "2. Tap More, then Edit.",
                "3. Add Red Pen to Favorites and drag it to the front.",
            ],
            footnote: "iOS controls share sheet order, but favorites always show first — right where Mail sits."
        )
    }

    private func card(title: String, icon: String, lines: [String], footnote: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.75))
            }
            Text(footnote)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.45))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }

    private func loadSelection(_ items: [PhotosPickerItem]) {
        isLoading = true
        Task {
            var loaded: [(image: UIImage, assetIdentifier: String?)] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    loaded.append((image, item.itemIdentifier))
                }
            }
            selection = []
            isLoading = false
            if !loaded.isEmpty {
                session = EditorSession(images: loaded)
            }
        }
    }
}
