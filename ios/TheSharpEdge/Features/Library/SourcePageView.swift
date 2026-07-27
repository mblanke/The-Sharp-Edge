import SwiftUI
import PDFKit

/// The actual page of the actual book.
///
/// Search only has to be good enough to *find* the page. Reading happens here, in the
/// publisher's own layout — two columns intact, photographs, nothing reconstructed and,
/// more to the point, nothing quietly missing. Extracted text is a fine index and a poor
/// recipe: a line dropped by a text layer is a step you never cook.
struct SourcePageView: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let title: String
    let path: String
    let page: Int

    @State private var data: Data?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let data {
                    PDFPage(data: data)
                        .ignoresSafeArea(edges: .bottom)
                } else if let error {
                    ContentUnavailableView {
                        Label("Can't open that page", systemImage: "book.closed")
                    } description: {
                        Text(error)
                    }
                } else {
                    ProgressView().tint(Theme.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(title).font(Typography.body(14, weight: .semibold))
                            .lineLimit(1)
                        Text("page \(page)").font(Typography.mono(11))
                            .foregroundStyle(Theme.faint)
                    }
                }
            }
            .task {
                do {
                    data = try await env.dataSource.sourcePage(path: path, page: page)
                } catch {
                    self.error = (error as? APIError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
        }
    }
}

/// Minimal PDFKit host. One page, so no navigation chrome — just fit and let it zoom.
private struct PDFPage: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.backgroundColor = .clear
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document == nil { view.document = PDFDocument(data: data) }
    }
}
