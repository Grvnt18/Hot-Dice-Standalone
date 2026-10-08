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
import math
import os
import re
import sys

from tools_swiftconst import source

import tools_smoke_preview as preview

SWIFT = "LowPolyTextures.swift"   # SmokeFloor folded in; see that file's note

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
    # The ramp was mirrored in both files and compared in neither, which is
    # exactly the drift this map exists to stop. It is also the half that
    # decides the floor's COLOUR rather than its shape, so a difference here
    # is the most visible kind there is.
    "rampSpread": "RAMP_SPREAD",
    "rampSpreadMin": "RAMP_SPREAD_MIN",
    "rampFloor": "RAMP_FLOOR",
    "rampCeil": "RAMP_CEIL",
    "rampSatLift": "RAMP_SAT_LIFT",
    "rampBias": "RAMP_BIAS",
    "rampMeanLevel": "RAMP_MEAN_LEVEL",
    "rampLift": "RAMP_LIFT",
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
    (r"6\.2831853 \* \(scn_frame\.time /", "time travels a closed path"),
    # Four tones, chosen by step, no interpolation between them.
    (r"_surface\.diffuse = float4\(tone, 1\.0\)", "the four tones are written flat"),
]


# Spellings that belong to OpenGL ES, not Metal.
#
# SceneKit stopped rendering with OpenGL on iOS years ago: a shader
# modifier string is translated and compiled as METAL. Most of this shader
# was already written that way — float2/float3/float4 rather than
# vec2/vec3/vec4 — and that is precisely what made the one OpenGL-only
# identifier in it invisible for a whole release. `u_time` compiled
# nowhere, and because SceneKit reports a shader failure asynchronously on
# the render thread there was nothing to catch:
#
#   [SceneKit] Error: FATAL ERROR : failed compiling shader:
#   error: use of undeclared identifier 'u_time'
#
# There is no Metal compiler in this container, so this cannot prove a
# shader compiles. What it can do is refuse the handful of names that are
# guaranteed not to, which is the whole of what went wrong here.
OPENGL_ONLY = [
    (r"\bu_time\b", "scn_frame.time"),
    (r"\bu_inverseResolution\b", "a #pragma arguments uniform"),
    (r"\bgl_\w+", "the Metal equivalent"),
    (r"\bvec[234]\b", "float2 / float3 / float4"),
    (r"\bmat[234]\b", "float2x2 / float3x3 / float4x4"),
    (r"\btexture2D\s*\(", "texture.sample(...)"),
    (r"\bgl_FragColor\b", "_output.color"),
]


# The floor's band must average within this of the swatch, in CIE dE76.
#
# Measured over all twenty-four swatches after the lift: eighteen come in
# under 3, and the worst that the lift can reach at all is Royal Blue at
# 4.9. The four it cannot reach are excluded by computation, not by name —
# see `pinned` in check_swatch_match.
MATCH_TOLERANCE = 5.5

# ...and the lift may not pay for that match by closing the band up. It is
# meant to SLIDE the band. Measured BEFORE the lift, over the same
# twenty-four: the narrowest band was 10.6 of L* (Espresso) and the
# tightest step 1.25 (Deep Indigo). After it, 11.2 and 1.24 — so these are
# the old figures, and the lift has to keep clearing them.
MIN_SPAN = 10.5
MIN_STEP = 1.20


def shader_source(text):
    """Just the shader string, with its comments removed.

    Both halves matter. Reading to end-of-file swept up the Swift below
    it, and the shader's own `//` comments legitimately NAME the OpenGL
    spellings while explaining why they are not used — a check that fails
    on the note explaining itself is worse than no check.
    """
    start = text.index('static let surfaceModifier: String = """')
    body = text[start:]
    body = body[body.index('"""') + 3:]
    body = body[: body.index('"""')]
    return re.sub(r"//[^\n]*", "", body)


def check_metal_only(shader, failed):
    """No OpenGL-only spelling survives in a shader Metal has to compile."""
    for pattern, instead in OPENGL_ONLY:
        for m in re.finditer(pattern, shader):
            failed.append("the shader uses %r, which is OpenGL ES — "
                          "SceneKit compiles this as Metal. Use %s."
                          % (m.group(0), instead))


def swift_constants(text):
    """Every `static let name: Type = value` in the file, as floats."""
    found = {}
    for m in re.finditer(r'static let (\w+)(?::\s*\w+)? = (-?[\d.]+)', text):
        found[m.group(1)] = float(m.group(2))
    return found


def check_swatch_match(failed):
    """The floor reads as the colour that was picked.

    The band used to hang straight down from the swatch, so every tone on
    screen was darker than it and the floor read duller than the picker
    promised — #006B38 came back as #045D33, which is a dE of 7.3 and a
    visibly different green. `RAMP_LIFT` slides the band up until its mean
    lands on the swatch instead of its ceiling.

    Two things are asserted, because fixing the first by sacrificing the
    second would be no fix at all:

    1. Every swatch the lift can MOVE averages within `MATCH_TOLERANCE` of
       it. Four cannot be moved, and they are found by asking whether the
       lift changed the band's top rather than by listing them: `RAMP_FLOOR`
       pins Onyx at the dark end — which is also what stops the olive-grey
       regression recorded in `ramp()` from coming back — and `RAMP_CEIL`
       pins Electric Blue, Hot Rose and Spring Green, which are already at
       full brightness. Those are printed with their dE rather than hidden.
    2. No swatch may end up FURTHER from its colour than it was with no
       lift at all.
    3. The L* span of each band, and its tightest step, are no smaller than
       they were before the lift. The lift SLIDES the band; a change that
       squeezed it would match the swatch by flattening the posterised look
       the six levels exist for.
    """
    swatches = re.findall(r'Swatch\(hex: "(#[0-9A-Fa-f]{6})", name: "([^"]+)"',
                          source("AppTheme.swift"))
    if not swatches:
        failed.append("AppTheme.swift lists no swatches to check the floor "
                      "against")
        return

    def lab(rgb):
        def linear(u):
            return u / 12.92 if u <= 0.04045 else ((u + 0.055) / 1.055) ** 2.4
        r, g, b = (linear(c) for c in rgb)
        x = 0.4124 * r + 0.3576 * g + 0.1805 * b
        y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        z = 0.0193 * r + 0.1192 * g + 0.9505 * b
        def cube(t):
            return t ** (1 / 3.0) if t > 0.008856 else 7.787 * t + 16 / 116.0
        fx, fy, fz = cube(x / 0.95047), cube(y), cube(z / 1.08883)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))

    def distance(a, b):
        return math.sqrt(sum((p - q) ** 2 for p, q in zip(lab(a), lab(b))))

    def band(hexcode, lift):
        """The band's tones and the mean the lift is aiming at."""
        keep = preview.RAMP_LIFT
        preview.RAMP_LIFT = lift
        try:
            tones = [tuple(c / 255.0 for c in t) for t in preview.ramp(hexcode)]
        finally:
            preview.RAMP_LIFT = keep
        want = tuple(int(hexcode.lstrip("#")[i:i + 2], 16) / 255.0
                     for i in (0, 2, 4))
        hue, sat, _ = preview.rgb_to_hsb(*want)
        lo = preview.rgb_to_hsb(*tones[0])[2]
        hi = preview.rgb_to_hsb(*tones[-1])[2]
        # The band's mean tone, straight from the constant that defines
        # where the mean sits rather than by re-rendering the field.
        mean = preview.hsb_to_rgb(
            hue,
            max(0.0, sat - preview.RAMP_SAT_LIFT * preview.RAMP_MEAN_LEVEL),
            lo + (hi - lo) * preview.RAMP_MEAN_LEVEL)
        return tones, mean, want, hi

    worst, tightest, narrowest = ("", 0.0), ("", 99.0), ("", 99.0)
    pinned, regressed = [], []
    if preview.RAMP_LIFT <= 0.0:
        failed.append("RAMP_LIFT is %g — the band hangs straight down from "
                      "the swatch again, so every tone on screen is darker "
                      "than the colour the player picked"
                      % preview.RAMP_LIFT)
    for hexcode, name in swatches:
        tones, mean, want, _ = band(hexcode, preview.RAMP_LIFT)
        _, was, _, flat = band(hexcode, 0.0)
        # Pinned is a property of the SWATCH, judged at a full lift — not
        # of whatever RAMP_LIFT happens to be. Asking whether the current
        # lift moved the band would call every swatch pinned the moment the
        # lift went back to zero, and pass on a floor with the fault still
        # in it.
        _, _, _, reachable = band(hexcode, 1.0)

        off = distance(mean, want)
        before = distance(was, want)
        if off > before + 0.05:
            regressed.append("%s (%s) dE %.1f -> %.1f"
                             % (name, hexcode, before, off))

        # A swatch the clamps hold cannot be lifted at all: RAMP_FLOOR
        # pins the dark end (Onyx) and RAMP_CEIL pins anything already at
        # full brightness (Electric Blue, Hot Rose, Spring Green). Those
        # are reported, not failed — and derived here rather than listed,
        # so adding a swatch to the picker cannot quietly skip the check.
        if reachable <= flat + 1e-9:
            pinned.append("%s dE %.1f" % (name, off))
        elif off > worst[1]:
            worst = ("%s (%s)" % (name, hexcode), off)

        lightness = [lab(t)[0] for t in tones]
        span = max(lightness) - min(lightness)
        step = min(abs(lightness[i + 1] - lightness[i])
                   for i in range(len(lightness) - 1))
        if span < narrowest[1]:
            narrowest = (hexcode, span)
        if step < tightest[1]:
            tightest = (hexcode, step)

    for line in regressed:
        failed.append("the lift moved %s FURTHER from its swatch — it is "
                      "meant to close that gap, not open it" % line)

    if worst[1] > MATCH_TOLERANCE:
        failed.append("the floor averages dE %.1f from %s — the band is not "
                      "centred on the colour the player picked"
                      % (worst[1], worst[0]))
    if narrowest[1] < MIN_SPAN:
        failed.append("%s's band spans only %.1f of L* — the lift is meant "
                      "to SLIDE the band, and squeezing it flattens the "
                      "posterised look" % (narrowest[0], narrowest[1]))
    if tightest[1] < MIN_STEP:
        failed.append("%s's tightest step is %.2f of L* — two of its six "
                      "tones will not read apart"
                      % (tightest[0], tightest[1]))
    else:
        print("  %-24s ok (%d swatches, worst dE %.1f at %s, narrowest band "
              "%.1f L*, tightest step %.2f)"
              % ("swatch match", len(swatches), worst[1], worst[0],
                 narrowest[1], tightest[1]))
        print("  %-24s %s" % ("clamp-pinned", ", ".join(pinned) or "none"))


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
    check_metal_only(shader_source(text), failed)
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

    # --- 3b. And it is the colour that was picked. --------------------
    check_swatch_match(failed)

    # --- 4. Nothing paints black behind the tray. ---------------------
    #
    # This check shipped looking only at UIKit `.backgroundColor =`, in two
    # named files. It passed cleanly while TEN game screens each carried their
    # own SwiftUI `.background(Color.black)` behind their tray — because the
    # shell those two files belong to is not where most screens set it. A
    # requirement stated as very high priority was half-delivered under a
    # green check, which is worse than no check.
    #
    # So: every Swift file, both spellings, no allowlist.
    for path in sorted(os.listdir(os.path.join(here, "SwiftFiles"))):
        if not path.endswith(".swift"):
            continue
        body = source(path)
        for m in re.finditer(r'\.backgroundColor = (.+)', body):
            value = m.group(1).strip()
            if "SmokeFloor" not in value:
                failed.append("%s sets a scene backgroundColor to `%s` — it "
                              "must be SmokeFloor.backdrop(from:), so a "
                              "visible sliver reads as the field rather than "
                              "as a hole in it" % (path, value))
        for m in re.finditer(r'\.background\(\s*(Color\.black|\.black)\s*\)', body):
            failed.append("%s puts Color.black behind a view — use "
                          "SmokeFloor.backdropColor. Black margins were "
                          "called out as a very high priority; every game "
                          "screen sets this for itself." % path)
    if not any("backgroundColor" in f or "Color.black" in f for f in failed):
        print("  %-24s ok (%d files, no black behind any tray)"
              % ("backdrop", len([p for p in os.listdir(os.path.join(here, "SwiftFiles"))
                                  if p.endswith(".swift")])))

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
