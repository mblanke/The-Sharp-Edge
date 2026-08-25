import PhotosUI
import SwiftUI

/// Photograph a recipe page (or pick one from the library) and let the local
/// vision model on the server transcribe it. Same contract as dictation: the
/// result seeds the editor for review — nothing here saves.
///
/// Server mode only; the menu entry that presents this sheet is hidden on a
/// device-hosted notebook.
struct PhotoCaptureView: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let onDraft: (RecipeCreate) -> Void

    @State private var showCamera = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var reading = false
    @State private var error: String?

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if reading {
                    Spacer()
                    ProgressView().tint(Theme.primary).scaleEffect(1.4)
                    Text("Reading the page…")
                        .font(Typography.body(16, weight: .semibold))
                    Text("The first read after a quiet spell can take a minute while the vision model loads.")
                        .font(Typography.body(13))
                        .foregroundStyle(Theme.faint)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Spacer()
                } else {
                    Spacer()
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.primary)
                    Text("Photograph a recipe page")
                        .font(Typography.body(18, weight: .semibold))
                    Text("Handwritten or printed — English, Français, Deutsch, Română. You review everything before it saves.")
                        .font(Typography.body(13))
                        .foregroundStyle(Theme.faint)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    if let error {
                        Text(error)
                            .font(Typography.body(13))
                            .foregroundStyle(Theme.accent)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    if cameraAvailable {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Take a photo", systemImage: "camera")
                                .font(Typography.body(16, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 30)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.primaryDeep)
                        .padding(.horizontal, 24)
                    }

                    PhotosPicker(selection: $pickedItem, matching: .images) {
                        Label("Choose from library", systemImage: "photo.on.rectangle")
                            .font(Typography.body(16, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.primary)
                    .padding(.horizontal, 24)
                    Spacer()
                }
            }
            .navigationTitle("From a photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(reading)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    showCamera = false
                    if let image { Task { await read(image) } }
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickedItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await read(image)
                    } else {
                        error = "Could not load that photo."
                    }
                    pickedItem = nil
                }
            }
        }
    }

    @MainActor
    private func read(_ image: UIImage) async {
        reading = true
        error = nil
        do {
            guard let jpeg = image.downscaledJPEG(maxDimension: 2048) else {
                throw APIError.transport("Could not encode the photo")
            }
            let draft = try await env.dataSource.parsePhoto(jpeg)
            // Best-effort slug from the title; editable like everything else.
            let slug = (try? await env.dataSource.slug(for: draft.title))?.slug ?? ""
            onDraft(draft.toRecipeCreate(slug: slug))
            dismiss()
        } catch let apiError as APIError {
            error = apiError.errorDescription ?? "Could not read the page."
        } catch {
            self.error = "Could not read the page."
        }
        reading = false
    }
}

/// Minimal camera wrapper — PhotosPicker has no capture mode, so the classic
/// picker does the one job SwiftUI still lacks.
private struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage?) -> Void
        init(onImage: @escaping (UIImage?) -> Void) { self.onImage = onImage }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onImage(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onImage(nil)
        }
    }
}

private extension UIImage {
    /// Recipe pages don't need 48 MP — a bounded JPEG keeps upload and vision fast.
    func downscaledJPEG(maxDimension: CGFloat) -> Data? {
        let largest = max(size.width, size.height)
        guard largest > maxDimension else { return jpegData(compressionQuality: 0.85) }
        let scale = maxDimension / largest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: 0.85)
    }
}
