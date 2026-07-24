import Foundation

/// One parsed Server-Sent Event.
struct SSEEvent: Equatable {
    var event: String
    var data: String
}

/// Streams SSE frames from a URLRequest using URLSession.bytes.
/// The server frames blocks as `event: <name>\ndata: <json>\n\n` (api/app/routers/ask.py _sse).
enum SSEClient {
    static func stream(_ request: URLRequest, session: URLSession = .shared) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        if http.statusCode == 502 { throw APIError.atlasDown }
                        throw APIError.server(status: http.statusCode, detail: nil)
                    }
                    var event = "message"
                    var dataLines: [String] = []
                    for try await line in bytes.lines {
                        if line.isEmpty {
                            if !dataLines.isEmpty {
                                continuation.yield(SSEEvent(event: event, data: dataLines.joined(separator: "\n")))
                            }
                            event = "message"
                            dataLines = []
                        } else if line.hasPrefix("event:") {
                            event = String(line.dropFirst("event:".count)).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            var d = String(line.dropFirst("data:".count))
                            if d.hasPrefix(" ") { d.removeFirst() }
                            dataLines.append(d)
                        }
                    }
                    // flush any trailing block without a final blank line
                    if !dataLines.isEmpty {
                        continuation.yield(SSEEvent(event: event, data: dataLines.joined(separator: "\n")))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
