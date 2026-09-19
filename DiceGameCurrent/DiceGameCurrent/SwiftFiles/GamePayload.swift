import Foundation

/// How a turn travels between devices.
///
/// A Messages extension moves state by writing it into the `MSMessage`'s
/// URL. That gives a practical budget of a few kilobytes, so everything
/// here optimises for compactness: short coding keys, palette indices
/// instead of hex strings, and seeds instead of enumerated roll results
/// wherever the game is replayable.
///
/// The envelope is versioned so a client that receives a game it does not
/// understand — a newer schema, or a game it has not shipped yet — can say
/// so instead of crashing or silently mis-decoding. `GameEnvelopeHeader`
/// exists for exactly that: read the header first, decide whether this
/// build can handle the payload, and only then decode the body.

// MARK: - Header

/// The parts of an envelope every client can read, whatever version wrote
/// it. Decoding this never fails on unknown games or future fields, because
/// it ignores everything else in the JSON.
struct GameEnvelopeHeader: Decodable {
    let game: String
    let version: Int

    private enum CodingKeys: String, CodingKey {
        case game = "g"
        case version = "v"
    }
}

// MARK: - Envelope

/// A turn: which game, which schema, the seed the game was built from, and
/// the game's own state.
///
/// Generic over the payload rather than carrying `Data`, because nesting
/// encoded `Data` inside JSON base64s it and costs ~33% for nothing.
struct GameEnvelope<State: Codable>: Codable {
    let game: String
    let version: Int
    let seed: UInt64
    let state: State

    private enum CodingKeys: String, CodingKey {
        case game = "g"
        case version = "v"
        case seed = "s"
        case state = "d"
    }

    init(game: String, version: Int, seed: UInt64, state: State) {
        self.game = game
        self.version = version
        self.seed = seed
        self.state = state
    }
}

// MARK: - Errors

enum GamePayloadError: Error, CustomStringConvertible {
    case notAGamePayload
    case unknownGame(String)
    /// The sender is running a newer schema than this build understands.
    case unsupportedVersion(game: String, received: Int, supported: Int)

    var description: String {
        switch self {
        case .notAGamePayload:
            return "This message doesn't contain a game."
        case .unknownGame(let id):
            return "This message is for \"\(id)\", which this version doesn't have yet."
        case .unsupportedVersion(let game, let received, let supported):
            return "This \(game) game was sent by a newer version (\(received) vs \(supported)). Update to play it."
        }
    }
}

// MARK: - Transport

/// Encodes and decodes envelopes to and from the compact text form that
/// rides in an `MSMessage` URL.
enum GameTransport {

    /// The query item the payload lives under.
    static let queryKey = "s"

    /// What Apple's documentation treats as a safe `MSMessage.url` size.
    /// Not a hard API limit — messages larger than this are accepted but
    /// increasingly likely to be rejected or truncated in transit, so it is
    /// treated as a budget to stay inside rather than a cliff to approach.
    static let safeByteBudget = 4096

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        // Stable key order makes encoded output reproducible, which is what
        // lets the round-trip tests compare bytes rather than re-decoding.
        e.outputFormatting = [.sortedKeys]
        return e
    }

    static func encodeToJSON<State: Codable>(_ envelope: GameEnvelope<State>) throws -> Data {
        try encoder.encode(envelope)
    }

    /// Builds the URL a turn is sent as.
    static func url<State: Codable>(for envelope: GameEnvelope<State>) throws -> URL {
        let json = try encodeToJSON(envelope)
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: queryKey, value: base64URL(json))]
        guard let url = components.url else {
            throw GamePayloadError.notAGamePayload
        }
        return url
    }

    /// Reads the header without committing to a payload type, so the caller
    /// can route to the right game (and reject ones it doesn't have).
    static func header(from url: URL) throws -> GameEnvelopeHeader {
        let json = try jsonData(from: url)
        return try JSONDecoder().decode(GameEnvelopeHeader.self, from: json)
    }

    /// Full decode, once the game is known. Verifies the schema version
    /// before touching the body so a future payload fails with a message the
    /// user can act on rather than a decoding error they can't.
    static func decode<State: Codable>(
        _ type: State.Type,
        from url: URL,
        expecting game: String,
        supportedVersion: Int
    ) throws -> GameEnvelope<State> {
        let json = try jsonData(from: url)
        let head = try JSONDecoder().decode(GameEnvelopeHeader.self, from: json)
        guard head.game == game else {
            throw GamePayloadError.unknownGame(head.game)
        }
        guard head.version <= supportedVersion else {
            throw GamePayloadError.unsupportedVersion(
                game: head.game, received: head.version, supported: supportedVersion
            )
        }
        return try JSONDecoder().decode(GameEnvelope<State>.self, from: json)
    }

    private static func jsonData(from url: URL) throws -> Data {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let encoded = components.queryItems?.first(where: { $0.name == queryKey })?.value,
            let json = dataFromBase64URL(encoded)
        else {
            throw GamePayloadError.notAGamePayload
        }
        return json
    }

    // MARK: base64url

    // Plain base64 uses `+` and `/`, which have to be percent-escaped inside
    // a query and so grow the URL. base64url swaps them for `-` and `_` and
    // drops the `=` padding, which is URL-safe as-is.

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func dataFromBase64URL(_ string: String) -> Data? {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Restore the padding base64url dropped.
        let remainder = s.count % 4
        if remainder > 0 {
            s += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: s)
    }
}

// MARK: - Size reporting

extension GameTransport {

    /// What a turn actually costs on the wire, and whether that fits.
    struct SizeReport: CustomStringConvertible {
        let jsonBytes: Int
        let urlBytes: Int
        var fitsBudget: Bool { urlBytes <= GameTransport.safeByteBudget }

        var description: String {
            let verdict = fitsBudget ? "OK" : "OVER BUDGET"
            let percent = Int((Double(urlBytes) / Double(GameTransport.safeByteBudget)) * 100)
            return "\(jsonBytes) B JSON -> \(urlBytes) B URL "
                 + "(\(percent)% of \(GameTransport.safeByteBudget) B budget) — \(verdict)"
        }
    }

    /// Measures an envelope. Used by the round-trip checks, and worth
    /// keeping callable at runtime so a payload that grows past the budget
    /// during development is noticed immediately rather than in the field.
    static func measure<State: Codable>(_ envelope: GameEnvelope<State>) throws -> SizeReport {
        let json = try encodeToJSON(envelope)
        let url = try url(for: envelope)
        return SizeReport(
            jsonBytes: json.count,
            urlBytes: url.absoluteString.utf8.count
        )
    }
}
