import XCTest
@testable import TheSharpEdge

/// Live-server exercise of the exact client path the app uses for photo import.
/// Skipped unless INTEGRATION_BASE is set (TEST_RUNNER_INTEGRATION_BASE via
/// xcodebuild), so CI and offline runs stay hermetic.
final class PhotoUploadIntegrationTests: XCTestCase {
    func testParsePhotoAgainstLiveServer() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let base = env["INTEGRATION_BASE"], let token = env["INTEGRATION_TOKEN"] else {
            throw XCTSkip("set INTEGRATION_BASE / INTEGRATION_TOKEN to run")
        }
        let url = try XCTUnwrap(URL(string: base))
        let client = APIClient(base: url, tokenProvider: { token })

        let fixturePath = try XCTUnwrap(env["INTEGRATION_FIXTURE"])
        let jpeg = try Data(contentsOf: URL(fileURLWithPath: fixturePath))

        let draft = try await client.parsePhoto(jpeg)
        XCTAssertFalse(draft.title.isEmpty)
        XCTAssertFalse(draft.ingredients.isEmpty)
    }
}
