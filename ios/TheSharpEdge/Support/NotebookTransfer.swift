import Foundation
import UniformTypeIdentifiers
import CoreTransferable

extension UTType {
    /// `.sharpedge` — a recipe or a whole notebook, as JSON.
    static let sharpEdgeRecipe = UTType(exportedAs: "com.blanke.thesharpedge.recipe")
}

/// The file format for moving recipes between notebooks.
///
/// **One envelope for one recipe and for a whole book**, so the importer has no branch
/// and whole-notebook export costs nothing extra. The inner recipes are `LocalRecipe`,
/// which reuses `VersionOut` verbatim — so the `versions` array is byte-compatible with
/// the API wire format, and a recipe exported from a server-backed app imports into a
/// device-hosted one without translation.
struct NotebookDocument: Codable {
    static let formatName = "sharp-edge-notebook"
    static let currentVersion = 1

    var format: String = NotebookDocument.formatName
    var version: Int = NotebookDocument.currentVersion
    var exportedAt: Date
    var recipes: [LocalRecipe]

    enum CodingKeys: String, CodingKey {
        case format, version, recipes
        case exportedAt = "exported_at"
    }

    enum ImportError: LocalizedError {
        case notANotebook
        case tooNew(Int)
        case empty

        var errorDescription: String? {
            switch self {
            case .notANotebook:
                return "That file isn't a Sharp Edge recipe."
            case let .tooNew(v):
                return "That file was made by a newer version of the app (format \(v)). "
                     + "Update The Sharp Edge and try again."
            case .empty:
                return "That file has no recipes in it."
            }
        }
    }

    /// Decode strictly. A best-effort read of an unknown future format would silently
    /// drop whatever it didn't understand — into somebody's permanent record.
    static func decode(_ data: Data) throws -> NotebookDocument {
        guard let doc = try? JSONCoding.decoder.decode(NotebookDocument.self, from: data),
              doc.format == formatName else {
            throw ImportError.notANotebook
        }
        guard doc.version <= currentVersion else { throw ImportError.tooNew(doc.version) }
        guard !doc.recipes.isEmpty else { throw ImportError.empty }
        return doc
    }

    func encoded() throws -> Data {
        try JSONCoding.encoder.encode(self)
    }

    /// What the file is called when it lands in Files or Messages.
    var suggestedFileName: String {
        if recipes.count == 1, let only = recipes.first {
            return "\(only.slug).sharpedge"
        }
        return "recipes.sharpedge"
    }
}

extension NotebookDocument: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .sharpEdgeRecipe) { doc in
            try doc.encoded()
        }
        .suggestedFileName { $0.suggestedFileName }
    }
}

/// Building an export payload from either kind of notebook.
enum NotebookExport {

    /// A single recipe from what is already on screen — no extra requests.
    ///
    /// Carries the current version only. That is the right default for sharing: the
    /// recipient wants the dish, not the author's six drafts of it, and fetching a
    /// history costs one request per version on every screen open just in case somebody
    /// taps Share.
    static func current(_ full: RecipeFull, now: Date = Date()) -> NotebookDocument {
        let local = LocalRecipe(
            slug: full.slug, title: full.title, category: full.category, meta: full.meta,
            baseYield: full.baseYield, yieldWord: full.yieldWord, gf: full.gf,
            noscale: full.noscale, status: full.status, source: full.source,
            versions: [full.currentVersion], createdAt: now, updatedAt: now)
        return NotebookDocument(exportedAt: now, recipes: [local])
    }

    /// A single recipe, with its full version history.
    ///
    /// Works in **both** modes deliberately: the owner has to be able to send a guest a
    /// recipe, and that is the whole point of the feature. From a server this costs one
    /// version list plus one fetch per version, which is fine for one recipe.
    static func recipe(_ slug: String, from source: DataSource,
                       now: Date = Date()) async throws -> NotebookDocument {
        let full = try await source.recipe(slug)
        var versions: [VersionOut] = []
        // History is a nicety; a recipe that exports without it is still a recipe.
        if let summaries = try? await source.versions(slug) {
            for summary in summaries.sorted(by: { $0.version < $1.version }) {
                if let body = try? await source.version(slug, summary.version) {
                    versions.append(body)
                }
            }
        }
        if versions.isEmpty { versions = [full.currentVersion] }

        let local = LocalRecipe(
            slug: full.slug, title: full.title, category: full.category, meta: full.meta,
            baseYield: full.baseYield, yieldWord: full.yieldWord, gf: full.gf,
            noscale: full.noscale, status: full.status, source: full.source,
            versions: versions, createdAt: now, updatedAt: now)

        return NotebookDocument(exportedAt: now, recipes: [local])
    }

    /// The whole notebook. Local mode only in v1: from a server this is 20×(1+V)
    /// requests, and a partial failure has no good answer — half a notebook that looks
    /// whole is worse than an error.
    static func everything(from store: LocalStore, now: Date = Date()) async -> NotebookDocument {
        NotebookDocument(exportedAt: now, recipes: await store.all())
    }
}
