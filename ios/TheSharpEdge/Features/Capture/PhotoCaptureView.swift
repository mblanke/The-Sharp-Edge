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
                CameraPicker { result in
                    showCamera = false
                    switch result {
                    case .data(let data): Task { await read(data) }
                    case .cancelled: break
                    case .empty:
                        // Seen on iOS betas: the picker returns without a usable
                        // image. Say so — silence here reads as "stuck".
                        error = "The camera returned no photo (an iOS beta quirk). Try again, or shoot with the Camera app and use Choose from library."
                    }
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickedItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await read(data)
                    } else {
                        error = "Could not load that photo."
                    }
                    pickedItem = nil
                }
            }
        }
    }

    @MainActor
    private func read(_ original: Data) async {
        reading = true
        error = nil
        // The read takes a while; if the screen locks, iOS suspends the app and
        // kills the socket ("the network connection was lost"). Keep it awake.
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            UIApplication.shared.isIdleTimerDisabled = false
            reading = false
        }
        do {
            // Downsample off the main thread and during decode: a ProRAW capture is
            // ~40 MB, and turning that into a full UIImage would spike memory for no
            // gain. A recipe page is text — 1400 px reads identically and uploads in
            // a fraction of the time.
            let shrunk = await Task.detached(priority: .userInitiated) {
                downsampledJPEG(from: original, maxPixel: 1400)
            }.value
            guard let jpeg = shrunk else {
                throw APIError.transport("Could not read that image format")
            }
            let draft = try await parseWithRetry(jpeg)
            // Best-effort slug from the title; editable like everything else.
            let slug = (try? await env.dataSource.slug(for: draft.title))?.slug ?? ""
            onDraft(draft.toRecipeCreate(slug: slug))
            dismiss()
        } catch let apiError as APIError {
            error = apiError.errorDescription ?? "Could not read the page."
        } catch {
            self.error = "Could not read the page."
        }
    }

    /// One automatic retry on a dropped connection — the vision model is warm by
    /// then, so the second attempt is fast.
    private func parseWithRetry(_ jpeg: Data) async throws -> PhotoDraft {
        do {
            return try await env.dataSource.parsePhoto(jpeg)
        } catch APIError.transport {
            return try await env.dataSource.parsePhoto(jpeg)
        }
    }
}

/// Minimal camera wrapper — PhotosPicker has no capture mode, so the classic
/// picker does the one job SwiftUI still lacks.
private struct CameraPicker: UIViewControllerRepresentable {
    enum Result {
        /// The captured photo as file data. ProRAW/HEIC are handed over as bytes and
        /// downsampled during decode — a 40 MB RAW must never become a full UIImage.
        case data(Data)
        case cancelled
        case empty
    }

    let onResult: (Result) -> Void

    init(onResult: @escaping (Result) -> Void) { self.onResult = onResult }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onResult: (Result) -> Void
        init(onResult: @escaping (Result) -> Void) { self.onResult = onResult }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            // Prefer the file on disk: reading its bytes avoids decoding a RAW
            // capture into memory. Fall back to the UIImage the picker provides.
            if let url = info[.imageURL] as? URL, let data = try? Data(contentsOf: url) {
                onResult(.data(data))
            } else if let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage,
                      let data = image.jpegData(compressionQuality: 0.9) {
                onResult(.data(data))
            } else {
                onResult(.empty)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onResult(.cancelled)
        }
    }
}
