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

// MARK: - What a turn actually carries

/// The body of every turn: the bookkeeping and the game's own state.
///
/// These were always going to travel together and never had a type saying
/// so. `TurnMatch` holds who is playing, whose turn it is and every score;
/// `State` holds whatever that game needs on top. Sending one without the
/// other is not a thing any game wants, so the pair is the unit.
///
/// Keys are one letter for the same reason everything else here is: this
/// rides in an `MSMessage` URL against a 4 KB budget.
struct MatchPayload<State: Codable & Equatable>: Codable, Equatable {
    var match: TurnMatch
    var state: State

    private enum CodingKeys: String, CodingKey {
        case match = "m"
        case state = "d"
    }

    init(match: TurnMatch, state: State) {
        self.match = match
        self.state = state
    }
}

// MARK: - Sending and receiving a turn

extension GameTransport {

    /// Packs a turn for sending.
    ///
    /// The one call a game makes. Everything underneath — the envelope, the
    /// version, the JSON, the base64url, the query item — is this file's
    /// business and no screen's.
    static func send<State: Codable & Equatable>(
        game: String,
        version: Int,
        seed: UInt64,
        match: TurnMatch,
        state: State
    ) throws -> URL {
        let body = MatchPayload(match: match, state: state)
        return try url(for: GameEnvelope(game: game, version: version,
                                         seed: seed, state: body))
    }

    /// Unpacks a received turn.
    ///
    /// Routes through `decode`, so an unknown game and a newer schema both
    /// come back as a `GamePayloadError` the receiver can show rather than
    /// as a decoding failure it cannot explain.
    static func receive<State: Codable & Equatable>(
        _ type: State.Type,
        from url: URL,
        expecting game: String,
        supportedVersion: Int
    ) throws -> (seed: UInt64, match: TurnMatch, state: State) {
        let envelope = try decode(MatchPayload<State>.self, from: url,
                                  expecting: game,
                                  supportedVersion: supportedVersion)
        return (envelope.seed, envelope.state.match, envelope.state.state)
    }
}

// MARK: - Proving it on the device

/// A round trip per game, run on the iPad.
///
/// The transport was written, documented and budgeted long before anything
/// used it, and nothing had ever encoded a real turn — the whole of it was
/// correct by inspection. This is what makes it correct by demonstration,
/// and it runs in Swift Playgrounds, where the Messages extension itself
/// cannot be built at all.
///
/// Each probe packs a representative turn, sends it through the real URL
/// path, reads it back, and compares. A payload that does not survive its
/// own round trip is a turn that would arrive wrong; a payload over budget
/// is one that might not arrive.
enum GameWireCheck {

    struct Result: Identifiable {
        let game: String
        let bytes: Int
        let fits: Bool
        /// Nil when the turn came back equal to the one that was sent.
        let failure: String?

        var id: String { game }
        var ok: Bool { failure == nil && fits }
    }

    /// Packs, sends, reads back and compares one game.
    ///
    /// Generic rather than existential: Swift 5.7 cannot hold a protocol
    /// with an associated type in an array without ceremony that buys
    /// nothing here, so the games are listed explicitly in `runAll` and
    /// each one calls this.
    static func probe<State: Codable & Equatable>(
        game: String,
        version: Int,
        seed: UInt64 = 0xD1CE_D1CE,
        match: TurnMatch,
        state: State
    ) -> Result {
        do {
            let url = try GameTransport.send(game: game, version: version,
                                             seed: seed, match: match,
                                             state: state)
            let bytes = url.absoluteString.utf8.count
            let back = try GameTransport.receive(State.self, from: url,
                                                 expecting: game,
                                                 supportedVersion: version)
            var problem: String?
            if back.seed != seed {
                problem = "seed came back \(back.seed), sent \(seed)"
            } else if back.match != match {
                problem = "the match did not survive the round trip"
            } else if back.state != state {
                problem = "the game state did not survive the round trip"
            }
            return Result(game: game, bytes: bytes,
                          fits: bytes <= GameTransport.safeByteBudget,
                          failure: problem)
        } catch {
            return Result(game: game, bytes: 0, fits: false,
                          failure: "\(error)")
        }
    }

    /// Every sendable game, each with a turn shaped like a real one.
    ///
    /// Free Roll is absent on purpose: it is solo and `isSendable` is false,
    /// so it has no turn to send and no state to carry.
    static func runAll() -> [Result] {
        let two = TurnMatch.localTwoPlayer()
        let group = TurnMatch.local(playerCount: 6)

        var results: [Result] = []

        // Rolls: the biggest payload in the suite by a distance — fifteen
        // landed faces per player, and no turn order, so a whole group chat
        // can be mid-round at once. If anything breaks the budget it is this.
        results.append(probe(game: RollsGameState.gameID, version: 1,
                             match: group,
                             state: RollsGameState(startedBy: "local.1")))

        results.append(probe(game: "generals", version: 1,
                             match: two, state: GeneralsState()))
        results.append(probe(game: "three_thousand", version: 1,
                             match: group, state: ThreeThousandState(
                                turnTotal: 850, turnsLeftAfterTarget: 2,
                                firstToTarget: "local.1")))
        results.append(probe(game: "hog", version: 1,
                             match: group, state: HogState(turnTotal: 23)))
        results.append(probe(game: "fyd", version: 1,
                             match: group, state: FreighterYachtDinghyState()))
        results.append(probe(game: "jackpot", version: 1,
                             match: two, state: JackpotState(
                                jackpotsThisRound: ["local.1"])))
        results.append(probe(game: "boneheads", version: 1,
                             match: two, state: filledBoneheads()))
        results.append(probe(game: "royal_ur", version: 1,
                             match: two, state: RoyalUrState()))
        results.append(probe(game: "rollbots", version: 1,
                             match: two,
                             state: RollbotsState(
                                weapons: [.monoBlade, .railRifle],
                                ware: [.neuralOverclock, .quantumPhase])))
        // Nine innings: the longest match the game offers, and so the
        // most base state a turn can carry.
        results.append(probe(game: "baseball_dice", version: 1,
                             match: two, state: BaseballDiceState(innings: 9)))

        return results
    }

    /// A Boneheads board with every slot taken, which is its largest state
    /// — eighteen placements, each a face and an ink. Measuring an empty
    /// board would measure nothing.
    private static func filledBoneheads() -> BoneheadsState {
        var state = BoneheadsState()
        for slot in 0..<BoneheadsRules.slotsPerColumn {
            for column in 0..<BoneheadsRules.columns {
                for seat in 0...1 {
                    state.place(seat: seat, column: column,
                                die: (slot + column + seat) % 6 + 1,
                                ink: (slot * 3 + column + seat) % 15)
                }
            }
        }
        return state
    }
}
