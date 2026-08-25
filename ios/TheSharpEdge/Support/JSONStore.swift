import Foundation

/// Atomic JSON files in a directory.
///
/// Extracted from `RecipeCache` so the local notebook can reuse the storage without
/// inheriting the one setting that must differ between them:
///
/// * A **cache** is excluded from backup — it is re-fetchable from the server, and it
///   should not eat the user's iCloud quota.
/// * A **notebook** is the only copy that exists. Excluding it from backup would mean a
///   lost or replaced iPad takes somebody's recipes with it.
///
/// That is a one-line difference with a large consequence, so it is a required parameter
/// rather than a default: `excludedFromBackup` has to be stated at every call site.
struct JSONStore {

    let directory: URL
    private let fm = FileManager.default

    init(directory: URL, excludedFromBackup: Bool) {
        self.directory = directory
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = excludedFromBackup
        var mutable = directory
        try? mutable.setResourceValues(resources)
    }

    func url(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    func write<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? JSONCoding.encoder.encode(value) else { return }
        // Atomic, so a crash or a backgrounding mid-write cannot leave a half file that
        // then fails to decode and looks like "no data".
        try? data.write(to: url(name), options: .atomic)
    }

    func read<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? JSONCoding.decoder.decode(type, from: data)
    }

    func exists(_ name: String) -> Bool {
        fm.fileExists(atPath: url(name).path)
    }

    func remove(_ name: String) {
        try? fm.removeItem(at: url(name))
    }

    /// File names in the directory matching a prefix and `.json`, sorted for determinism.
    func names(prefix: String) -> [String] {
        let all = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
        return all.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".json") }.sorted()
    }

    func modified(_ name: String) -> Date? {
        try? fm.attributesOfItem(atPath: url(name).path)[.modificationDate] as? Date
    }

    func removeAll() {
        try? fm.removeItem(at: directory)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
