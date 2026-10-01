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
