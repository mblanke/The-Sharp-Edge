import Foundation

/// On-disk copy of whatever the app has successfully fetched.
///
/// The premise of the app is that it is the calculator beside a paper notebook
/// (CLAUDE.md §1). A calculator that stops working when the fibre drops is not one —
/// and that is exactly what happened: the gateway went down and the iPad could not
/// read a recipe while sitting three metres from the server holding it.
///
/// The whole corpus is about 51 KB, so there is nothing to be clever about. Every
/// successful fetch is written to Application Support as JSON; every failed fetch
/// falls back to it. Scaling is already entirely client-side
/// (`Domain/ScalingEngine.swift`), so a cached recipe still scales with no network.
actor RecipeCache {
    static let shared = RecipeCache()

    private let directory: URL
    private let listFile: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RecipeCache", isDirectory: true)
        self.directory = base
        self.listFile = base.appendingPathComponent("recipes.json")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // Recipes are re-fetchable from the server; do not consume the user's iCloud
        // quota backing them up, and do not let the system purge them either.
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        var mutable = base
        try? mutable.setResourceValues(resources)
    }

    // MARK: - Recipe list

    func saveList(_ cards: [RecipeCard]) {
        write(cards, to: listFile)
    }

    func loadList() -> [RecipeCard]? {
        read([RecipeCard].self, from: listFile)
    }

    // MARK: - Individual recipes

    private func file(for slug: String) -> URL {
        // Slugs match ^[a-z0-9][a-z0-9-]*$ (CLAUDE.md §5), so they are already safe
        // as filenames — no escaping needed, and no path traversal possible.
        directory.appendingPathComponent("r-\(slug).json")
    }

    func save(_ recipe: RecipeFull) {
        write(recipe, to: file(for: recipe.slug))
    }

    func load(_ slug: String) -> RecipeFull? {
        read(RecipeFull.self, from: file(for: slug))
    }

    /// When the list itself is unavailable, fall back to whatever individual recipes
    /// have been viewed — better a partial kitchen than an empty one.
    func loadAllCached() -> [RecipeCard] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        return names
            .filter { $0.hasPrefix("r-") && $0.hasSuffix(".json") }
            .compactMap { read(RecipeFull.self, from: directory.appendingPathComponent($0)) }
            .map { RecipeCard(slug: $0.slug, title: $0.title, category: $0.category, meta: $0.meta,
                              baseYield: $0.baseYield, yieldWord: $0.yieldWord, gf: $0.gf,
                              noscale: $0.noscale, status: $0.status) }
            .sorted { $0.title < $1.title }
    }

    var lastSaved: Date? {
        try? FileManager.default.attributesOfItem(atPath: listFile.path)[.modificationDate] as? Date
    }

    func clear() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Disk

    private func write<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONCoding.encoder.encode(value) else { return }
        // Atomic, so a crash or a backgrounding mid-write cannot leave a half file
        // that then fails to decode and looks like "no cache".
        try? data.write(to: url, options: .atomic)
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONCoding.decoder.decode(type, from: data)
    }
}
