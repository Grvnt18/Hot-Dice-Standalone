"""Checks the floor the Swift will draw against the floor that was approved.

The field exists three times: as GLSL inside `SmokeFloor.surfaceModifier`, as
Swift beside it (the still fallback needs it on the CPU), and as Python in
`tools_smoke_preview.py`, which is the only one anybody can actually look at in
this container. Three copies of the same arithmetic drift apart. That is not a
worry, it is this project's history — it happened to the rules text, to the
icon loader, to GameHubView and to the baseball field — so this reads all three
and asserts they agree.

It also asserts the two things about the motion that no still frame can show
and that a glance at a loop does not reliably catch either:

    the loop closes    t = 0 and t = LOOP are the same field, exactly
    everything moves   no region of the floor sits on one tone for a cycle

The second one matters more than it sounds. A floor whose large structures are
pinned in space, churning only where the warp gradient happens to be steep,
looks alive at a glance and is half dead. That shipped once.

    python3 tools_smoke_verify.py
"""
import os
import re
import sys

from tools_swiftconst import source

import tools_smoke_preview as preview

SWIFT = "SmokeFloor.swift"

# Swift `static let` name -> the Python module-level constant it must equal.
# Anything in the shader's maths belongs here; anything that only affects how
# the preview presents itself (image sizes, frame counts) does not.
CONSTANTS = {
    "hashX": "HASH_X",
    "hashY": "HASH_Y",
    "hashScale": "HASH_SCALE",
    "octaves": "OCTAVES",
    "lacunarity": "LACUNARITY",
    "gain": "GAIN",
    "originX": "ORIGIN_X",
    "originY": "ORIGIN_Y",
    "fieldScale": "FIELD_SCALE",
    "fieldAspect": "FIELD_ASPECT",
    "contrast": "CONTRAST",
    "levels": "LEVELS",
    "dither": "DITHER",
    "warpA": "WARP_A",
    "warpB": "WARP_B",
    "orbitQ": "ORBIT_Q",
    "orbitR": "ORBIT_R",
    "orbitN": "ORBIT_N",
    "phaseR": "PHASE_R",
    "phaseN": "PHASE_N",
    "loopSeconds": "LOOP_SECONDS",
}

# Lines the GLSL must still contain. Not a transcription of the shader — just
# the handful of places where a plausible-looking edit silently changes what
# the floor is, and which the constant comparison above would not notice.
SHADER_SHAPE = [
    # The dither is added to the value BEFORE quantising. Swapping these two
    # lines still compiles, still dithers, and produces noise sprinkled over
    # flat contour bands instead of a broken-up boundary.
    (r"n \+= \(limit - 0\.5\)", "the dither offset is applied to the value"),
    (r"floor\(n \* ", "...and the quantise happens after it"),
    # The final sample carries its own orbit. Without `onn` here the base
    # field is pinned and only the warp moves it — the half-dead floor.
    # Matched loosely on purpose: the Swift source still holds `\(warpB)`
    # here, not the interpolated number, so pinning the coefficient would only
    # assert how the string is built. What has to be true is that the FINAL
    # sample carries the field's own orbit on both axes.
    (r"rx \+ onn\.x", "the field itself orbits (x)"),
    (r"ry \+ onn\.y", "the field itself orbits (y)"),
    # Time is a point on a circle, never a linear ramp.
    (r"6\.2831853 \* \(u_time /", "time travels a closed path"),
    # Four tones, chosen by step, no interpolation between them.
    (r"_surface\.diffuse = float4\(tone, 1\.0\)", "the four tones are written flat"),
]


def swift_constants(text):
    """Every `static let name: Type = value` in the file, as floats."""
    found = {}
    for m in re.finditer(r'static let (\w+)(?::\s*\w+)? = (-?[\d.]+)', text):
        found[m.group(1)] = float(m.group(2))
    return found


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    text = source(SWIFT)
    failed = []

    # --- 1. The constants agree. -------------------------------------
    swift = swift_constants(text)
    for name, py_name in sorted(CONSTANTS.items()):
        if name not in swift:
            failed.append("%s no longer declares `static let %s` — the Python "
                          "still has %s, so one side has moved"
                          % (SWIFT, name, py_name))
            continue
        want = float(getattr(preview, py_name))
        if abs(swift[name] - want) > 1e-9:
            failed.append("%s %s = %g but tools_smoke_preview.%s = %g — the "
                          "floor you can see and the floor that ships are not "
                          "the same floor"
                          % (SWIFT, name, swift[name], py_name, want))
    if not failed:
        print("  %-24s ok (%d values, Swift and Python agree)"
              % ("constants", len(CONSTANTS)))

    # --- 2. The shader still does the things that matter. ------------
    shader = text[text.index("surfaceModifier"):] if "surfaceModifier" in text else ""
    missing = [why for pattern, why in SHADER_SHAPE
               if not re.search(pattern, shader)]
    for why in missing:
        failed.append("the shader no longer shows that %s" % why)
    if not missing:
        print("  %-24s ok (%d load-bearing lines intact)"
              % ("shader shape", len(SHADER_SHAPE)))

    # --- 3. The motion is what was approved. --------------------------
    # These run the Python, which the constants check has just tied to the
    # Swift, so passing here says something about what ships and not only
    # about the preview.
    if not preview.check_loop():
        failed.append("the field does not return to its start after "
                      "LOOP_SECONDS — it cannot loop")
    if not preview.check_everywhere():
        failed.append("some region of the floor holds one tone for a whole "
                      "cycle — it is static on screen, whatever the numbers "
                      "elsewhere say")

    # --- 4. Nothing paints black behind the tray. ---------------------
    # The colour is one line in two files and reverts easily; the requirement
    # that there be no black margin does not.
    for name in ("DiceGameShell.swift", "DiceTraySceneView.swift"):
        body = source(name)
        for m in re.finditer(r'\.backgroundColor = (.+)', body):
            value = m.group(1).strip()
            if "SmokeFloor" not in value:
                failed.append("%s sets a scene backgroundColor to `%s` — it "
                              "must be SmokeFloor.backdrop(from:), so a "
                              "visible sliver reads as the field rather than "
                              "as a hole in it" % (name, value))
    if not any("backgroundColor" in f for f in failed):
        print("  %-24s ok (no black behind the tray)" % "backdrop")

    if failed:
        print()
        for line in failed:
            print("  FAIL  %s" % line)
        print("\nsmoke: FAIL (%d)" % len(failed))
        return 1

    print("smoke: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
