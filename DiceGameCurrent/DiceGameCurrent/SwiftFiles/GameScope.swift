import Foundation

/// Which game's settings are in force.
///
/// The table colour and the music were one global choice, so picking a
/// steel-grey table for Rollbots made every other game steel grey too. Each
/// game now keeps its own, and this is the one place that decides whose
/// settings `AppTheme` and `SoundEngine` are currently reading and writing.
///
/// **Falling back is the whole design.** A game that has never been
/// configured does not start from a hardcoded default — it inherits
/// whatever the global value is, so a player who sets a colour on the hub
/// and never opens Settings again sees it everywhere, exactly as before.
/// Only a deliberate change inside a game writes a per-game value, and only
/// that game is affected by it.
enum GameScope {

    /// The game whose settings are in force, or nil for the hub.
    private(set) static var activeGameID: String?

    private static let defaults = UserDefaults.standard

    /// Called as a game is opened, BEFORE its view is built — the scene
    /// reads `AppTheme.floorBaseColor` while assembling, so a scope entered
    /// afterwards would build the floor in the previous game's colour.
    static func enter(_ gameID: String) {
        guard activeGameID != gameID else { return }
        activeGameID = gameID
        reload()
    }

    /// Back to the hub's global settings.
    static func leave() {
        guard activeGameID != nil else { return }
        activeGameID = nil
        reload()
    }

    private static func reload() {
        AppTheme.shared.reloadForScope()
        SoundEngine.shared.reloadForScope()
    }

    // MARK: Reading and writing

    /// Whether music follows the game or the app.
    ///
    /// Global by necessity: a setting that decides what gets scoped cannot
    /// itself be scoped, or turning it off in one game would leave it on
    /// in the next. Defaults to true, which is the behaviour this shipped
    /// with.
    ///
    /// The table colour is deliberately NOT covered — it is per game
    /// either way, because that is what was asked for and because a floor
    /// is part of a game's look in a way a backing track is not.
    private static let musicScopeKey = "scope.musicPerGame"

    static var musicIsPerGame: Bool {
        get {
            defaults.object(forKey: musicScopeKey) as? Bool ?? true
        }
        set {
            guard newValue != musicIsPerGame else { return }
            defaults.set(newValue, forKey: musicScopeKey)
            // Applied now rather than at the next handover: a track that
            // changes two minutes later reads as broken, which is the same
            // reason selectedTrackIndex restarts playback on assignment.
            SoundEngine.shared.reloadForScope()
        }
    }

    /// The per-game key for a setting, or the global one on the hub.
    static func key(_ base: String) -> String {
        guard let id = activeGameID else { return base }
        return "\(base).\(id)"
    }

    /// The key for a music setting, which honours `musicIsPerGame`.
    ///
    /// Separate from `key` rather than a flag on it, so a caller has to
    /// say which kind of setting it is holding rather than getting the
    /// scoping rule by accident.
    static func musicKey(_ base: String) -> String {
        musicIsPerGame ? key(base) : base
    }

    /// Whether this scope has ever stored a value of its own.
    ///
    /// `object(forKey:)` rather than a typed read: the typed accessors
    /// return 0 / false for a missing key, which is indistinguishable from
    /// a stored 0 / false and would make "never set" look like "set to
    /// off". That is the same failure `SoundEngine`'s own
    /// `register(defaults:)` comment describes.
    private static func hasOwnValue(_ key: String) -> Bool {
        defaults.object(forKey: key) != nil
    }

    /// The key to read from: this scope's own if it has ever been set,
    /// otherwise the global one it inherits from.
    private static func readKey(_ base: String, scoped: String) -> String {
        hasOwnValue(scoped) ? scoped : base
    }

    static func int(_ base: String) -> Int {
        defaults.integer(forKey: readKey(base, scoped: key(base)))
    }

    static func double(_ base: String) -> Double {
        defaults.double(forKey: readKey(base, scoped: key(base)))
    }

    static func bool(_ base: String) -> Bool {
        defaults.bool(forKey: readKey(base, scoped: key(base)))
    }

    static func set(_ value: Any, _ base: String) {
        defaults.set(value, forKey: key(base))
    }

    // MARK: Music, which may or may not be scoped

    static func musicInt(_ base: String) -> Int {
        defaults.integer(forKey: readKey(base, scoped: musicKey(base)))
    }

    static func musicDouble(_ base: String) -> Double {
        defaults.double(forKey: readKey(base, scoped: musicKey(base)))
    }

    static func musicBool(_ base: String) -> Bool {
        defaults.bool(forKey: readKey(base, scoped: musicKey(base)))
    }

    static func setMusic(_ value: Any, _ base: String) {
        defaults.set(value, forKey: musicKey(base))
    }
}
