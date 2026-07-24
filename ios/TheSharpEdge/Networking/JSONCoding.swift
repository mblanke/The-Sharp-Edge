import Foundation

/// Shared JSON coders. The API emits ISO-8601 datetimes (FastAPI default).
enum JSONCoding {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        // FastAPI/pydantic emit fractional-second ISO-8601; use a tolerant formatter.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = formatter.date(from: str) ?? plain.date(from: str) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container,
                debugDescription: "Unrecognised date: \(str)")
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
