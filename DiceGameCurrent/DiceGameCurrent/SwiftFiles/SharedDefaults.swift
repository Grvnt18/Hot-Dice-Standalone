import Foundation

/// Where the player's settings live, so the app and the Messages extension
/// see the same ones.
///
/// **This exists because `UserDefaults.standard` is not shared.** An app
/// extension has its own container, so `.standard` inside the Messages
/// extension is a different store from `.standard` in the app. Three types
/// persist through it — `AppTheme` (the dice colourway), `GameScope`
/// (whether audio and colour are per-game or suite-wide) and `SoundEngine`
/// (music and effect volumes, the chosen track) — which means without this
/// a player would set their colours in Hot Dice, open a game in a thread,
/// and find none of it had travelled. Then set it again there, and find
/// THAT had not travelled back. Two sets of preferences for one product,
/// and the kind of thing testers report as five separate bugs.
///
/// **An App Group is the fix, and half of it is not in the repo.** The
/// group has to be registered with Apple and enabled as a capability on
/// both targets; `project.yml` names it in the entitlements it generates.
/// Until that is done on the Mac, `UserDefaults(suiteName:)` returns nil,
/// and this falls back to `.standard` — which is exactly today's behaviour,
/// so nothing breaks while the capability is missing and everything starts
/// sharing the moment it is added.
///
/// Reading it back as nil is not an error worth shouting about: it means
/// "not configured yet", and the app works perfectly well with per-process
/// settings. It is only the two-places-at-once case that needs the group.
enum SharedDefaults {

    /// The App Group identifier.
    ///
    /// Must match the one registered with Apple and the one in
    /// `project.yml`'s entitlements for both targets. The `group.` prefix
    /// is required by Apple; the rest mirrors the bundle id, which is the
    /// convention and keeps it obvious which app owns it.
    ///
    /// Change this in exactly the same breath as the bundle identifiers —
    /// see YOUR_STEPS.txt. A group id that does not match the entitlement
    /// does not fail loudly; it just quietly stops sharing.
    static let appGroupID = "group.com.example.hotdice"

    /// The store every setting goes through.
    ///
    /// Resolved once: `UserDefaults(suiteName:)` touches the filesystem,
    /// and this is read from property observers that fire on every change
    /// of a volume slider.
    static let store: UserDefaults = {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }()

    /// Whether the group is actually configured.
    ///
    /// For the diagnostic panel to report, rather than for any behaviour to
    /// branch on — a missing group is a setup step not yet taken, not a
    /// fault. `BundleCheck` is the precedent: say what is absent, keep
    /// running.
    static var isSharing: Bool {
        UserDefaults(suiteName: appGroupID) != nil
    }
}
