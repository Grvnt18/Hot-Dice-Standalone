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


def main():
    failed = []
    audio = source("GameAudio.swift")

    # --- 1. Every set named in the code has files. --------------------
    sets = dict(re.findall(r'static let (\w+)\s*=\s*"(sfx_[a-z_]+)"', audio))
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

    # --- 7. The sets are actually reached from the screens. -----------
    for screen, call in (("BaseballDiceScreen.swift", "BaseballAudio.play("),
                         ("BaseballDiceScreen.swift", "BaseballAudio.playIntro()"),
                         ("RollbotsScreen.swift", "RollbotsAudio.fire("),
                         ("RollbotsScreen.swift", "RollbotsAudio.activate(")):
        if call not in source(screen):
            failed.append("%s never calls %s" % (screen, call))

    if failed:
        for line in failed:
            print("  %-22s FAILED  %s" % ("audio", line))
        sys.exit("audio: FAILED (%d problem(s))" % len(failed))

    total = sum(os.path.getsize(os.path.join(RES, f)) for f in shipped)
    print("audio: PASS (%d sets, %d files, %.1f MB)"
          % (len(sets) + len(IMPACT_TIERS), len(shipped), total / 1048576.0))


if __name__ == "__main__":
    main()
