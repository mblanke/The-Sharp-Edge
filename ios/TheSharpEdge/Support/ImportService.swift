import Foundation

/// Reading a `.sharpedge` file into a notebook.
///
/// **Nothing is ever imported silently.** An "open with" that instantly mutates the
/// notebook is how people lose recipes: you tap a file to see what it is, and it has
/// already overwritten something. Every path produces a plan first, which a person
/// confirms.
enum ImportService {

    /// What will happen to one incoming recipe.
    enum Resolution: String, CaseIterable, Identifiable {
        /// No collision — it just goes in.
        case add
        /// Same slug, identical content. Importing again would achieve nothing.
        case skip
        /// Same slug, different content. Import under a free slug.
        case rename
        /// Same slug — append the incoming body as a new version of what's there.
        case addVersion

        var id: String { rawValue }

        var label: String {
            switch self {
            case .add: return "Add"
            case .skip: return "Skip"
            case .rename: return "Add as a copy"
            case .addVersion: return "Add as a new version"
            }
        }
    }

    struct Row: Identifiable {
        var id: String { incoming.slug }
        let incoming: LocalRecipe
        /// Nil when there is no collision.
        let existingTitle: String?
        /// The slug that will actually be written when `resolution == .rename`.
        let freeSlug: String
        var resolution: Resolution
        /// Choices that make sense for this row.
        var options: [Resolution]
    }

    struct Plan {
        var rows: [Row]
        var exportedAt: Date

        var willWrite: Int { rows.filter { $0.resolution != .skip }.count }
    }

    /// Read a file and work out what importing it would do. Reads only.
    static func plan(for url: URL, into store: LocalStore) async throws -> Plan {
        // Files-app and iCloud URLs are security-scoped; without this the read fails with
        // a permissions error that reads like a corrupt file.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let doc = try NotebookDocument.decode(data)

        var rows: [Row] = []
        var claimed: Set<String> = []
        for incoming in doc.recipes {
            let existing = try? await store.recipe(incoming.slug)
            let free = await freeSlug(for: incoming.slug, store: store, alsoTaken: claimed)
            claimed.insert(free)

            if let existing {
                let identical = existing.current?.ingredients == incoming.current?.ingredients
                    && existing.current?.steps == incoming.current?.steps
                    && existing.title == incoming.title
                rows.append(Row(
                    incoming: incoming,
                    existingTitle: existing.title,
                    freeSlug: free,
                    // Rename is the default: slugs are a QR contract (CLAUDE.md §5), and a
                    // recipe from somebody else's notebook is a different dish that happens
                    // to share a name. "New version" is offered because append-only makes
                    // it lossless, and "they sent me a fixed goulash" is a real case.
                    resolution: identical ? .skip : .rename,
                    options: identical ? [.skip, .rename] : [.rename, .addVersion, .skip]))
            } else {
                rows.append(Row(incoming: incoming, existingTitle: nil, freeSlug: incoming.slug,
                                resolution: .add, options: [.add, .skip]))
            }
        }
        return Plan(rows: rows, exportedAt: doc.exportedAt)
    }

    /// `goulash` → `goulash-2` → `goulash-3`. Never reuses a slug the plan already claimed.
    private static func freeSlug(for slug: String, store: LocalStore,
                                 alsoTaken: Set<String>) async -> String {
        guard await store.has(slug) || alsoTaken.contains(slug) else { return slug }
        var n = 2
        while true {
            let candidate = "\(slug)-\(n)"
            if await !store.has(candidate), !alsoTaken.contains(candidate) { return candidate }
            n += 1
        }
    }

    @discardableResult
    static func apply(_ plan: Plan, to store: LocalStore) async -> Int {
        var written = 0
        for row in plan.rows {
            switch row.resolution {
            case .skip:
                continue

            case .add, .rename:
                var copy = row.incoming
                copy.slug = row.resolution == .rename ? row.freeSlug : row.incoming.slug
                // Renumber from 1 so the imported history is self-consistent, and mark
                // only the last one current.
                copy.versions = renumbered(row.incoming.versions)
                copy.createdAt = Date()
                copy.updatedAt = Date()
                await store.save(copy)
                written += 1

            case .addVersion:
                // Append-only, like every other write: nothing existing is touched, so an
                // unwanted import is undone by restoring the previous version.
                guard let body = row.incoming.current else { continue }
                _ = try? await store.update(row.incoming.slug, RecipeUpdate(
                    label: body.label ?? "imported",
                    ingredients: body.ingredients, steps: body.steps, notes: body.notes))
                written += 1
            }
        }
        return written
    }

    private static func renumbered(_ versions: [VersionOut]) -> [VersionOut] {
        let ordered = versions.sorted { $0.version < $1.version }
        return ordered.enumerated().map { index, v in
            VersionOut(id: UUID(), version: index + 1, label: v.label,
                       ingredients: v.ingredients, steps: v.steps, notes: v.notes,
                       isCurrent: index == ordered.count - 1, createdAt: v.createdAt)
        }
    }
}
