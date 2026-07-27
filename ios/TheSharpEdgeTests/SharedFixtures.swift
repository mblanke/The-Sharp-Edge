import Foundation
import XCTest

/// Reads the cross-language parity fixtures in `shared/fixtures/`.
///
/// Those files are generated from the Python in `api/app/services/` by
/// `api/scripts/dump_fixtures.py`. On the Python side they are a regression net; here
/// they are the **specification**. That difference is the whole point: in local
/// notebook mode there is no server to defer to, so the Swift answer is the one a cook
/// acts on, and "the server is canonical" (CLAUDE.md §8) stops being a usable rule.
///
/// It is not hypothetical. Before this harness existed the iOS gluten-watch list had
/// drifted to 14 terms against the server's 23, and GF is load-bearing (§1).
///
/// **Fixtures are read from the source tree via `#filePath`, so these tests run on the
/// simulator or a Mac, not on a device.** That is an accepted trade: everything they
/// cover is a pure function, and the alternative — copying the JSON into the test
/// bundle as a resource — reintroduces exactly the stale-duplicate problem the
/// fixtures exist to kill.
enum SharedFixtures {

    /// `<repo>/shared/fixtures`, resolved from this file's location at compile time.
    static var directory: URL {
        URL(fileURLWithPath: #filePath)      // …/ios/TheSharpEdgeTests/SharedFixtures.swift
            .deletingLastPathComponent()     // …/ios/TheSharpEdgeTests
            .deletingLastPathComponent()     // …/ios
            .deletingLastPathComponent()     // …/  (repo root)
            .appendingPathComponent("shared/fixtures", isDirectory: true)
    }

    struct File<Args: Decodable, Expect: Decodable>: Decodable {
        struct Case: Decodable {
            let id: String
            let args: Args
            let expect: Expect
        }
        let version: Int
        let function: String
        let note: String?
        let tolerance: Double?
        let cases: [Case]
    }

    enum FixtureError: LocalizedError {
        case missing(String, URL)
        case unsupportedVersion(String, Int)

        var errorDescription: String? {
            switch self {
            case let .missing(name, url):
                return """
                Missing parity fixture "\(name)" at \(url.path).
                Run: python api/scripts/dump_fixtures.py
                (If this failed on a physical device, that is expected — fixtures are \
                read from the source tree via #filePath. Run on a simulator.)
                """
            case let .unsupportedVersion(name, v):
                return "Fixture \"\(name)\" is version \(v); this test understands version 1."
            }
        }
    }

    static func load<A, E>(_ name: String) throws -> File<A, E> {
        let url = directory.appendingPathComponent("\(name).json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FixtureError.missing(name, url)
        }
        let file = try JSONDecoder().decode(File<A, E>.self, from: Data(contentsOf: url))
        guard file.version == 1 else {
            throw FixtureError.unsupportedVersion(name, file.version)
        }
        return file
    }

    /// Every fixture file on disk. Used to fail loudly on one nothing reads.
    static func allNames() throws -> Set<String> {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
        return Set(urls.filter { $0.pathExtension == "json" }
                       .map { $0.deletingPathExtension().lastPathComponent })
    }
}

// MARK: - Shared argument shapes

struct NameArg: Decodable { let name: String }
struct AisleArg: Decodable { let aisle: String }
struct ValueUnitArg: Decodable { let value: Double; let unit: String }

struct LineSpec: Decodable {
    let name: String
    let amount: Double
    let unit: String
    let recipe: String
}

struct LinesArg: Decodable { let lines: [LineSpec] }
struct LinesTextArg: Decodable {
    let lines: [LineSpec]
    let group_by_aisle: Bool
}

/// One merged line as the server renders it.
struct MergedLineExpect: Decodable {
    let name: String
    let amount: Double
    let unit: String
    let display: String
    let to_taste: Bool
    let recipes: [String]
    let check_gluten: Bool
    let aisle: String
}

// MARK: - Assertion helper

extension XCTestCase {
    /// Runs every case in a fixture, reporting the case id on failure so a red test
    /// names the input that broke rather than an index.
    func forEachCase<A: Decodable, E: Decodable>(
        _ name: String,
        _ body: (String, A, E, Double?) throws -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        do {
            let fixture: SharedFixtures.File<A, E> = try SharedFixtures.load(name)
            XCTAssertFalse(fixture.cases.isEmpty, "\(name) has no cases", file: file, line: line)
            for c in fixture.cases {
                XCTContext.runActivity(named: "\(name)/\(c.id)") { _ in
                    do { try body(c.id, c.args, c.expect, fixture.tolerance) }
                    catch { XCTFail("\(name)/\(c.id): \(error)", file: file, line: line) }
                }
            }
        } catch {
            XCTFail("\(error.localizedDescription)", file: file, line: line)
        }
    }
}
