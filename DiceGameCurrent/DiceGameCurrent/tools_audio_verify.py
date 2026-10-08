"""Checks the sound effects: every set the code plays is in Resources,
every file shipped is played by something, and the at-bat sequence covers
every result the game can produce.

A missing sound is SILENT. That is the whole reason this exists — a set
named `sfx_bb_bat` against files called `sfx_bb_hit` looks exactly like a
game with no sound design, and `DiceAudioEngine` is deliberately tolerant
of missing files so the game keeps playing. Tolerance at runtime is right;
silence at review time is not.
"""
import os
import re
import sys

from tools_swiftconst import source, SWIFT

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, "Resources")

AUDIO = ("wav", "mp3", "m4a", "caf", "aiff")

# Sets that are not named in GameAudio: the dice impacts, which
# DiceAudioEngine builds from the ImpactTier cases.
IMPACT_TIERS = ("soft", "medium", "hard")

# Named in SoundEngine's SFX enum and played through AVAudioPlayer rather
# than the sample engine. No variants: one file each.
def sound_engine_effects(text):
    return re.findall(r'case \w+\s*=\s*"(sfx_[a-z_]+)"', text)


def files_for(name):
    """Every file belonging to a set: numbered variants, or the bare name."""
    out = []
    for entry in sorted(os.listdir(RES)):
        base, ext = os.path.splitext(entry)
        if ext[1:].lower() not in AUDIO:
            continue
        if base == name or re.fullmatch(re.escape(name) + r"_\d{2}", base):
            out.append(entry)
    return out


# The four audio values one switch has to cover, and the scope accessor
# each must go through.
AUDIO_KEYS = ("musicEnabled", "musicVolume", "sfxEnabled", "sfxVolume")


def check_scope(failed):
    """One switch covers all of the audio, and the colour has its own.

    The toggle read "Music Per Game" and moved half the audio: the track
    and its volume went through `GameScope`, while `sfxEnabled` and
    `sfxVolume` were written straight to `UserDefaults` and so stayed
    global whatever the switch said. A player who turned it off found their
    track followed them from game to game and their effects volume did not,
    and nothing anywhere said that was the design.

    So: every one of the four goes through the audio accessors, the reload
    picks up all four, and the switch is named for what it governs. The
    table colour gets the same treatment, by its own switch.
    """
    engine = source("SoundEngine.swift")
    scope = source("GameScope.swift")
    settings = source("SettingsView.swift")
    theme = source("AppTheme.swift")

    # 1. Nothing in SoundEngine writes a setting behind GameScope's back.
    for match in re.finditer(r'defaults\.set\((\w+), forKey: Keys\.(\w+)\)',
                             engine):
        failed.append("SoundEngine writes %s straight to UserDefaults — it "
                      "has to go through GameScope.setAudio, or the Audio "
                      "Per Game switch does not reach it" % match.group(2))

    # 2. All four are written and read through the audio accessors...
    for key in AUDIO_KEYS:
        if "GameScope.setAudio(%s, Keys.%s)" % (key, key) not in engine:
            failed.append("SoundEngine does not store %s through "
                          "GameScope.setAudio" % key)
        if not re.search(r'GameScope\.audio(?:Bool|Double|Int)\(Keys\.%s\)'
                         % key, engine):
            failed.append("SoundEngine does not read %s through a "
                          "GameScope.audio accessor" % key)

    # 3. ...and all four are picked up when the scope changes, or entering
    #     a game would leave the previous one's effects playing.
    reload_body = engine.split("func reloadForScope()", 1)[-1]
    reload_body = reload_body.split("\n    }", 1)[0]
    for key in AUDIO_KEYS:
        if "Keys.%s" % key not in reload_body:
            failed.append("SoundEngine.reloadForScope does not re-read %s — "
                          "it would keep the previous game's value" % key)

    # 4. The switch is one switch, and it is named for all of it.
    if "audioIsPerGame" not in scope:
        failed.append("GameScope no longer has audioIsPerGame")
    if "musicIsPerGame" in scope or "musicIsPerGame" in settings:
        failed.append("GameScope still exposes musicIsPerGame — the switch "
                      "covers the effects too and the name has to say so")
    if 'Toggle("Audio Per Game"' not in settings:
        failed.append('Settings no longer offers "Audio Per Game"')

    # 5. The colour has the same switch, through its own accessors.
    if "colorIsPerGame" not in scope:
        failed.append("GameScope has no colorIsPerGame — the table colour is "
                      "per game with no way to say otherwise")
    if 'Toggle("Color Per Game"' not in settings:
        failed.append('Settings no longer offers "Color Per Game"')
    if "GameScope.setColor(colorwayIndex" not in theme:
        failed.append("AppTheme does not store the colorway through "
                      "GameScope.setColor, so Color Per Game cannot reach it")
    if "GameScope.colorInt(Keys.colorwayIndex)" not in theme:
        failed.append("AppTheme does not read the colorway through "
                      "GameScope.colorInt")

    # 6. Both switches are on the hub only. Inside a game either would be a
    #    control that changes what every OTHER game does.
    hub_only = settings.split("if gameName == nil {", 1)
    if len(hub_only) < 2:
        failed.append("SettingsView no longer gates anything on the hub")
    else:
        for label in ('Toggle("Audio Per Game"', 'Toggle("Color Per Game"'):
            if label not in hub_only[1]:
                failed.append("%s is outside the `gameName == nil` branch — "
                              "it would appear inside a game" % label)

    # 7. And the scope note says nothing when the scope is off.
    if "The same in every game." in settings:
        failed.append('SettingsView still prints "The same in every game." — '
                      "that line only ever appears once the player has just "
                      "said that is what they want")
    note = settings.split("func scopeNote(perGame: Bool)", 1)[-1]
    note = note.split("\n    }", 1)[0]
    if "if let gameName, perGame {" not in note:
        failed.append("scopeNote no longer drops out when the scope is off")

    if not failed:
        print("  %-22s ok (one switch over %s; colour on its own)"
              % ("audio scope", ", ".join(AUDIO_KEYS)))


def main():
    failed = []
    audio = source("GameAudio.swift")

    # --- 1. Every set named in the code has files. --------------------
    # [a-z0-9_], not [a-z_]: "sfx_3k_bust" has a digit in it, and with the
    # narrower class the set simply did not register — so its seven files
    # were reported as shipped-but-unplayed while the call site existed all
    # along. A check that silently stops seeing a whole set is worse than no
    # check, so this is deliberately permissive.
    sets = dict(re.findall(r'static let (\w+)\s*=\s*"(sfx_[a-z0-9_]+)"', audio))
    if not sets:
        sys.exit("audio: FAILED (no sample sets found in GameAudio.swift)")

    print("sample sets:")
    for label, name in sorted(sets.items(), key=lambda kv: kv[1]):
        found = files_for(name)
        if not found:
            failed.append("%s (%s) has no files in Resources — it would play "
                          "silently, which is indistinguishable from no sound "
                          "design at all" % (name, label))
        print("  %-22s %-2d file(s)%s" % (name, len(found),
                                          "" if found else "   MISSING"))

    for tier in IMPACT_TIERS:
        name = "sfx_impact_" + tier
        found = files_for(name)
        if not found:
            failed.append("%s has no files — the dice themselves are silent"
                          % name)
        print("  %-22s %-2d file(s)" % (name, len(found)))

    # --- 2. Nothing shipped that nothing plays. -----------------------
    #
    # The same check `tools_icons_verify.py` runs, and for the same reason:
    # a file nobody asks for is worth a line of output rather than a silent
    # 50KB.
    claimed = set()
    for name in list(sets.values()) + ["sfx_impact_" + t for t in IMPACT_TIERS]:
        claimed.update(files_for(name))
    for effect in sound_engine_effects(source("SoundEngine.swift")):
        claimed.update(files_for(effect))

    shipped = {f for f in os.listdir(RES)
               if f.startswith("sfx_")
               and os.path.splitext(f)[1][1:].lower() in AUDIO}
    for extra in sorted(shipped - claimed):
        print("  %-22s shipped but nothing plays it" % extra)

    # --- 3. Every at-bat result has a sound. --------------------------
    #
    # The sequence is a switch over AtBatResult, and Swift would catch a
    # missing case — but only if the switch stays exhaustive rather than
    # growing a `default`, which would silently swallow a new result.
    play = audio.split("static func play(_ result: AtBatResult)", 1)
    if len(play) < 2:
        failed.append("BaseballAudio has no at-bat sequence")
    else:
        body = play[1].split("\n    }", 1)[0]
        if "default" in body:
            failed.append("the at-bat switch has a `default`, so a new "
                          "result would be silent instead of failing to "
                          "compile")
        results = set(re.findall(r'case (\w+)',
                                 source("BaseballDice.swift").split(
                                     "enum AtBatResult", 1)[1].split("}", 1)[0]))
        results = set(re.split(r",\s*", ", ".join(results)))
        for result in sorted(results):
            if result and result not in body:
                failed.append("the at-bat sequence never mentions .%s" % result)

    # --- 4. The walk has no swing in it. ------------------------------
    #
    # Asserted because it is the one deliberate exception, and the kind of
    # thing a later tidy-up would "fix" by making every result uniform.
    if not re.search(r'if result == \.walk\s*\{', audio):
        failed.append("the walk is no longer handled apart — ball four is "
                      "the one at-bat where the batter never swung")

    # --- 5. The delays are the ones that were chosen. -----------------
    delays = dict(re.findall(r'static let (\w+): TimeInterval = ([\d.]+)', audio))
    wanted = {"contactDelay": 0.12, "fieldOutCatch": 0.45,
              "deepOutCatch": 1.2, "missedPitch": 0.25}
    for key, value in sorted(wanted.items()):
        got = float(delays.get(key, -1))
        if abs(got - value) > 1e-9:
            failed.append("%s is %s, not %s" % (key, delays.get(key), value))
    print("  %-22s bat +%ss, infield catch +%ss, deep catch +%ss"
          % ("at-bat timing", delays.get("contactDelay"),
             delays.get("fieldOutCatch"), delays.get("deepOutCatch")))

    # --- 6. Every call's labels are in the declared order. ------------
    #
    # Swift requires argument labels in declaration order, and this file's
    # calls pass four of five with one defaulted — which is exactly the
    # shape where a swapped pair compiles in the author's head and not on
    # the device. Caught here because this project has no compiler.
    engine = source("DiceAudioEngine.swift")
    decl = re.search(r'func play\(set name: String,([^)]*)\)', engine)
    if not decl:
        failed.append("DiceAudioEngine has no play(set:) to check calls against")
    else:
        order = ["set"] + re.findall(r'(\w+):', decl.group(1))
        for call in re.finditer(r'play\(set:(.*?)\)', audio, re.S):
            labels = ["set"] + re.findall(r'(\w+):', call.group(1))
            ranks = [order.index(l) for l in labels if l in order]
            if ranks != sorted(ranks):
                failed.append("a play(set:) call passes %s — the declaration "
                              "is %s, and Swift wants them in that order"
                              % (labels, order))
        print("  %-22s ok (%s)" % ("call order", ", ".join(order)))

    # --- 6b. Every SFX cue has a file. --------------------------------
    #
    # The check whose absence let all SEVEN UI cues ship with no audio at
    # all — including buttonTap, which 37 call sites play. SoundEngine
    # resolves a cue by trying each extension and silently skips the ones it
    # cannot find, by design, so a missing file is not an error anywhere:
    # it is simply a button that never clicks. Nothing else was ever going
    # to catch that.
    cues = re.findall(r'case \w+\s*=\s*"(sfx_[a-z_]+)"', source("SoundEngine.swift"))
    if not cues:
        failed.append("no SFX cases found in SoundEngine.swift — the cue "
                      "list moved and this check is now blind")
    extensions = ("mp3", "m4a", "wav", "caf", "aiff")
    print("\nUI cues:")
    for cue in cues:
        found = [e for e in extensions if os.path.exists(RES + "/%s.%s" % (cue, e))]
        print("  %-24s %s" % (cue, found[0] if found else "MISSING"))
        if not found:
            failed.append("%s has no audio file — the cue is declared, every "
                          "call to it is silent, and nothing reports it"
                          % cue)

    # --- 7. The sets are actually reached from the screens. -----------
    for screen, call in (("BaseballDiceScreen.swift", "BaseballAudio.play("),
                         ("BaseballDiceScreen.swift", "BaseballAudio.playIntro()"),
                         ("RollbotsScreen.swift", "RollbotsAudio.fire("),
                         ("RollbotsScreen.swift", "RollbotsAudio.activate("),
                         ("ThreeThousandScreen.swift", "AudioSet.bust"),
                         ("HogScreen.swift", "AudioSet.oink"),
                         ("BoneheadsScreen.swift", "AudioSet.remove"),
                         ("RoyalUrScreen.swift", "AudioSet.urMove"),
                         ("FreighterYachtDinghyScreen.swift", "SeaAudio.start()"),
                         ("FreighterYachtDinghyScreen.swift", "SeaAudio.stop()"),
                         ("PassAndPlayHost.swift", "VictoryAudio.start()"),
                         ("RollbotsArt.swift", "VictoryAudio.start()")):
        if call not in source(screen):
            failed.append("%s never calls %s" % (screen, call))

    print()
    print("scope:")
    check_scope(failed)

    if failed:
        for line in failed:
            print("  %-22s FAILED  %s" % ("audio", line))
        sys.exit("audio: FAILED (%d problem(s))" % len(failed))

    total = sum(os.path.getsize(os.path.join(RES, f)) for f in shipped)
    print("audio: PASS (%d sets, %d files, %.1f MB)"
          % (len(sets) + len(IMPACT_TIERS), len(shipped), total / 1048576.0))


if __name__ == "__main__":
    main()
