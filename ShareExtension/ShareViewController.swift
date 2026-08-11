import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Hosts the full editor directly inside the share sheet — no bounce to the
// main app, so markup starts the moment the extension appears.
final class ShareViewController: UIViewController {
    private var didLoadContent = false
    private var session: EditorSession?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        overrideUserInterfaceStyle = .dark

        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = .white
        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didLoadContent else { return }
        didLoadContent = true
        loadImagesAndPresentEditor()
    }

    private func loadImagesAndPresentEditor() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }

        guard !providers.isEmpty else {
            cancel()
            return
        }

        Task { @MainActor in
            var images = [UIImage?](repeating: nil, count: providers.count)
            await withTaskGroup(of: (Int, UIImage?).self) { group in
                for (index, provider) in providers.enumerated() {
                    group.addTask {
                        (index, await Self.loadImage(from: provider))
                    }
                }
                for await (index, image) in group {
                    images[index] = image
                }
            }

            let loaded = images.compactMap { $0 }
            guard !loaded.isEmpty else {
                self.cancel()
                return
            }
            self.presentEditor(with: loaded)
        }
    }

    private func presentEditor(with images: [UIImage]) {
        let session = EditorSession(images: images.map { (image: $0, assetIdentifier: nil) })
        self.session = session

        let editor = EditorRootView(session: session) { [weak self] _ in
            self?.finish()
        }

        let host = UIHostingController(rootView: editor)
        host.view.backgroundColor = .systemBackground
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(
            domain: "com.example.redpen.share",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "No images to edit."]
        ))
    }

    private static func loadImage(from provider: NSItemProvider) async -> UIImage? {
        if provider.canLoadObject(ofClass: UIImage.self) {
            let image: UIImage? = await withCheckedContinuation { continuation in
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    continuation.resume(returning: object as? UIImage)
                }
            }
            if let image { return image }
        }

        return await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data.flatMap(UIImage.init(data:)))
            }
        }
    }
}
