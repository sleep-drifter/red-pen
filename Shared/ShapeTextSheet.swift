import SwiftUI

// Edit the text inside a shape: content, left/center alignment, and the four
// detented font styles (12/18/24/40pt) with ±4pt nudging. Text color is not
// editable — the app picks black or white for contrast.
struct ShapeTextSheet: View {
    @ObservedObject var session: EditorSession
    let shapeID: UUID

    @Environment(\.dismiss) private var dismiss
    @FocusState private var textFocused: Bool
    @State private var didSnapshot = false

    var body: some View {
        if let binding = session.shapeBinding(for: shapeID) {
            NavigationStack {
                Form {
                    Section("Text") {
                        TextField("Label", text: withSnapshot(binding.text), axis: .vertical)
                            .lineLimit(1...5)
                            .focused($textFocused)
                    }

                    Section("Alignment") {
                        Picker("Alignment", selection: withSnapshot(binding.alignment)) {
                            Image(systemName: "text.alignleft").tag(TextAlignmentChoice.left)
                            Image(systemName: "text.aligncenter").tag(TextAlignmentChoice.center)
                        }
                        .pickerStyle(.segmented)
                    }

                    Section("Font Size") {
                        HStack(spacing: 8) {
                            ForEach(FontPreset.allCases) { preset in
                                Button {
                                    snapshotIfNeeded()
                                    binding.wrappedValue.fontSize = preset.rawValue
                                } label: {
                                    Text("\(Int(preset.rawValue))")
                                        .font(.system(size: 15, weight: .semibold))
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                        .background(
                                            binding.wrappedValue.fontSize == preset.rawValue
                                                ? Color.white.opacity(0.25)
                                                : Color.white.opacity(0.08),
                                            in: RoundedRectangle(cornerRadius: 8)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Stepper(
                            "Nudge: \(Int(binding.wrappedValue.fontSize))pt",
                            onIncrement: { nudge(binding, by: fontNudgeStep) },
                            onDecrement: { nudge(binding, by: -fontNudgeStep) }
                        )
                    }
                }
                .navigationTitle("Shape Text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .preferredColorScheme(.dark)
            .onAppear { textFocused = true }
        }
    }

    private func nudge(_ binding: Binding<ShapeAnnotation>, by delta: CGFloat) {
        snapshotIfNeeded()
        let next = binding.wrappedValue.fontSize + delta
        binding.wrappedValue.fontSize = min(max(next, fontSizeRange.lowerBound),
                                            fontSizeRange.upperBound)
    }

    // One undo snapshot per sheet presentation, taken lazily on first edit.
    private func snapshotIfNeeded() {
        guard !didSnapshot else { return }
        didSnapshot = true
        session.beginChange()
    }

    private func withSnapshot<T>(_ binding: Binding<T>) -> Binding<T> {
        Binding(
            get: { binding.wrappedValue },
            set: { newValue in
                snapshotIfNeeded()
                binding.wrappedValue = newValue
            }
        )
    }
}
