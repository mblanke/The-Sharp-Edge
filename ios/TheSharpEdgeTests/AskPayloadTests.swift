import XCTest
@testable import TheSharpEdge

/// The SSE `done` event grew two fields the app was ignoring, and chunks grew a
/// `file_type`. Decoding is the whole contract with the server here, so it is worth
/// pinning: a silent decode failure would show a cook the wrong thing rather than crash.
final class AskPayloadTests: XCTestCase {

    private func decode<T: Decodable>(_ json: String, as _: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: attribution

    func testDoneCarriesShelfNoteForAnAbsentAuthority() throws {
        // The real failure: six identical asks about Escoffier, each answered in his
        // name from books that are not his.
        let json = """
        {"citations": [], "sources": [], "ungrounded": false,
         "attribution": {"absent": ["Escoffier"], "unretrieved": [], "sources": ["The Professional Chef"],
                         "note": "There is no Escoffier on this shelf. The excerpts below are from The Professional Chef."}}
        """
        let done = try decode(json, as: AskDone.self)
        XCTAssertEqual(done.attribution?.absent, ["Escoffier"])
        XCTAssertTrue(done.attribution?.note.contains("no Escoffier on this shelf") == true)
        XCTAssertEqual(done.ungrounded, false)
    }

    func testDoneWithoutAttributionStaysSilent() throws {
        let done = try decode(#"{"citations": [], "sources": []}"#, as: AskDone.self)
        XCTAssertNil(done.attribution)
        XCTAssertNil(done.ungrounded)   // absent means "old server", not "grounded"
    }

    // MARK: media sources never claim a page

    func testVideoSourceIsRecognisedAsMedia() throws {
        let json = """
        {"n": 1, "title": "Keller MasterClass", "source_path": "/x/11.Sous Vide - Turbot.mkv",
         "page": 2, "text": "…", "file_type": "mkv"}
        """
        let src = try decode(json, as: Source.self)
        XCTAssertTrue(src.isMedia, "a transcript must not offer to open page 2 of an .mkv")
    }

    func testPdfSourceKeepsItsPage() throws {
        let json = #"{"n": 1, "title": "The Professional Chef", "page": 358, "file_type": "pdf"}"#
        let src = try decode(json, as: Source.self)
        XCTAssertFalse(src.isMedia)
        XCTAssertEqual(src.page, 358)
    }

    func testMediaDetectionIsCaseAndDotInsensitive() {
        XCTAssertTrue(MediaKinds.contains("MKV"))
        XCTAssertTrue(MediaKinds.contains(".mp4"))
        XCTAssertFalse(MediaKinds.contains("pdf"))
        XCTAssertFalse(MediaKinds.contains(nil))
    }

    // MARK: shelf coverage

    func testBookCoverageDecodesAndUnknownIsNotMissing() throws {
        let indexed = try decode(
            #"{"name": "The Food Lab", "kind": "folder", "size_bytes": 1, "status": "indexed", "chunks": 3520, "note": "…"}"#,
            as: BookOut.self)
        XCTAssertEqual(indexed.chunks, 3520)
        XCTAssertEqual(indexed.isSearchable, true)

        let missing = try decode(#"{"name": "Under Pressure", "kind": "folder", "status": "missing", "chunks": 0}"#,
                                 as: BookOut.self)
        XCTAssertEqual(missing.isSearchable, false)

        // No coverage fields: the lookup was unavailable. That is "unknown" — showing it
        // as missing would mark the whole shelf broken the first time the tailnet blinked.
        let unknown = try decode(#"{"name": "Larousse", "kind": "folder"}"#, as: BookOut.self)
        XCTAssertNil(unknown.status)
        XCTAssertNil(unknown.isSearchable)
    }
}

// MARK: book scope — the phone could never say "just the CIA"

extension AskPayloadTests {

    func testAskRequestEncodesBookScope() throws {
        let req = AskRequest(question: "how is the onion soup made",
                             scope: AskScope(recipeSlug: nil, books: ["Culinary Institute of America.pdf"]))
        let json = try JSONEncoder().encode(req)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let scope = try XCTUnwrap(obj["scope"] as? [String: Any])
        XCTAssertEqual(scope["books"] as? [String], ["Culinary Institute of America.pdf"])
    }

    func testAskRequestOmitsBooksWhenUnscoped() throws {
        let req = AskRequest(question: "what is a beurre blanc")
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(req)) as? [String: Any])
        let scope = try XCTUnwrap(obj["scope"] as? [String: Any])
        // nil, not [] — an empty list would be a scope matching no book at all
        XCTAssertNil(scope["books"])
    }

    func testRecipeAndBookScopeCoexist() throws {
        let req = AskRequest(question: "can I use tamari",
                             scope: AskScope(recipeSlug: "goulash", books: ["The Food Lab"]))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(req)) as? [String: Any])
        let scope = try XCTUnwrap(obj["scope"] as? [String: Any])
        XCTAssertEqual(scope["recipe_slug"] as? String, "goulash")
        XCTAssertEqual(scope["books"] as? [String], ["The Food Lab"])
    }
}
