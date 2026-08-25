import Foundation

/// Mirrors LibraryStatus / BookOut from api/app/schemas/chat.py.

struct BookOut: Codable, Hashable, Identifiable {
    var name: String
    var kind: String            // file | folder
    var sizeBytes: Int?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, kind
        case sizeBytes = "size_bytes"
    }
}

/// rag_health is a free-form dict server-side; we read the fields we care about leniently.
struct RagHealth: Codable, Hashable {
    var ok: Bool
    var count: Int?

    init(ok: Bool, count: Int? = nil) {
        self.ok = ok
        self.count = count
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? c.decode(Bool.self, forKey: .ok)) ?? false
        count = try? c.decode(Int.self, forKey: .count)
    }

    enum CodingKeys: String, CodingKey { case ok, count }
}

struct LibraryStatus: Codable, Hashable {
    var mounted: Bool
    var libraryDir: String?
    var books: [BookOut]
    var ragHealth: RagHealth

    enum CodingKeys: String, CodingKey {
        case mounted
        case libraryDir = "library_dir"
        case books
        case ragHealth = "rag_health"
    }

    init(mounted: Bool, libraryDir: String?, books: [BookOut], ragHealth: RagHealth) {
        self.mounted = mounted
        self.libraryDir = libraryDir
        self.books = books
        self.ragHealth = ragHealth
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mounted = (try? c.decode(Bool.self, forKey: .mounted)) ?? false
        libraryDir = try? c.decode(String.self, forKey: .libraryDir)
        books = (try? c.decode([BookOut].self, forKey: .books)) ?? []
        ragHealth = (try? c.decode(RagHealth.self, forKey: .ragHealth)) ?? RagHealth(ok: false)
    }
}
