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
            List {
                Section {
                    PhotosPicker(
                        selection: $selection,
                        maxSelectionCount: 10,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label(isLoading ? "Loading…" : "Pick Screenshots",
                              systemImage: "photo.on.rectangle.angled")
                    }
                    .disabled(isLoading)
                } footer: {
                    Text("Edit up to 10 screenshots at once, then save them all back to your photo library.")
                }

                Section {
                    Label("Take a screenshot", systemImage: "1.circle")
                    Label("Tap the thumbnail, then the share icon", systemImage: "2.circle")
                    Label("Pick Red Pen, mark it up, tap Save", systemImage: "3.circle")
                    Label("Close the preview and choose Delete Screenshot", systemImage: "4.circle")
                } header: {
                    Text("Zero-original workflow")
                } footer: {
                    Text("The original never lands in your photo library — only the marked-up copy does.")
                }

                Section {
                    Label("Undo: tap the canvas with two fingers", systemImage: "hand.tap")
                    Label("Redo: tap the canvas with three fingers", systemImage: "hand.tap.fill")
                } header: {
                    Text("Editor gestures")
                }

                Section {
                    Label("Open any share sheet and scroll the app row to the end", systemImage: "1.circle")
                    Label("Tap More, then Edit", systemImage: "2.circle")
                    Label("Add Red Pen to Favorites and drag it to the front", systemImage: "3.circle")
                } header: {
                    Text("Show Red Pen first in the share sheet")
                } footer: {
                    Text("Favorites always appear first — right where Mail sits.")
                }
            }
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
