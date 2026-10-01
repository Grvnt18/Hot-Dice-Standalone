"""Checks the dice dither the Swift will draw against the one that was seen.

Same job as tools_smoke_verify does for the floor and tools_wood_verify for
the timber, and the same reason: the dither exists twice, as Swift in
`DieMaterialFactory` and as Python in `tools_dice_preview.py`, and only the
Python one can be looked at in this container.

It also guards the three things about this that are invisible until they are
wrong, and then unmissable:

    the numerals are unreachable   the body material must be set on the die
                                   body ALONE, with the numerals on their own
                                   nodes. This is the entire reason the
                                   dither is safe, and it is one edit away
                                   from not being true.
    nearest-neighbour filtering    the tile is 8x8 texels magnified across a
                                   whole face. With the default linear filter
                                   SceneKit interpolates between them and the
                                   dither arrives as a soft grey wash — which
                                   looks worse than no dither, and looks like
                                   a rendering bug rather than a setting.
    multiply, not diffuse          in the multiply channel the body colour
                                   survives and all fifteen colourways stay
                                   distinguishable. Moved to diffuse it would
                                   REPLACE the body colour, which is the one
                                   thing that was explicitly not wanted.

    python3 tools_dice_verify.py
"""
import glob
import os
import re
import sys

from tools_swiftconst import source, SWIFT as SWIFT_DIR

import tools_dice_preview as preview

SWIFT = "DieMaterialFactory.swift"
LABELS = "DieFaceLabels.swift"


def main():
    text = source(SWIFT)
    failed = []

    # --- 1. The strength agrees with what was previewed. ---------------
    match = re.search(r'static let ditherStrength: CGFloat = ([\d.]+)', text)
    if not match:
        failed.append("%s no longer declares `ditherStrength`" % SWIFT)
    else:
        strength = float(match.group(1))
        if strength not in preview.STRENGTHS:
            failed.append("ditherStrength = %g is not one of the strengths "
                          "tools_dice_preview renders (%s) — the value that "
                          "ships is one nobody has looked at"
                          % (strength, preview.STRENGTHS))
        else:
            print("  %-26s ok (%.2f, previewed)" % ("strength", strength))

    cells = re.search(r'static let ditherCellsPerFace: CGFloat = ([\d.]+)', text)
    if not cells:
        failed.append("%s no longer declares `ditherCellsPerFace`" % SWIFT)
    else:
        shipped = float(cells.group(1))
        previewed = preview.SWATCH // preview.CELL
        if abs(shipped - previewed) > 1e-9:
            failed.append("ditherCellsPerFace = %g but tools_dice_preview "
                          "renders %d cells across a face (SWATCH %d / CELL "
                          "%d) — the density on the sheet is not the density "
                          "that ships, and cell size is the one thing here "
                          "that can only be judged by looking"
                          % (shipped, previewed, preview.SWATCH, preview.CELL))
        else:
            print("  %-26s ok (%g across a face, previewed)"
                  % ("cell density", shipped))

    # --- 2. The dither cannot reach the numerals. ----------------------
    #
    # Two halves, and both have to hold. The body material must be assigned
    # as the die's WHOLE material list (so it is the body and nothing else),
    # and the numerals must be their own nodes carrying their own geometry.
    if "node.geometry?.materials = [material]" not in text:
        failed.append("%s no longer assigns the body material as the node's "
                      "entire material list — if a numeral ever shares this "
                      "material, the dither is drawn straight through it, "
                      "which is the one thing this treatment must never do"
                      % SWIFT)
    elif "material.multiply.contents = dither" not in text:
        failed.append("%s no longer puts the dither in the multiply channel"
                      % SWIFT)
    else:
        print("  %-26s ok (body material only)" % "numerals unreachable")

    labels = source(LABELS)
    if "SCNPlane(" not in labels:
        failed.append("%s no longer builds numerals as their own SCNPlane "
                      "nodes — they may now share the body's material, and "
                      "the dither would be drawn through them" % LABELS)

    # --- 3. Nearest-neighbour, or the whole thing is a grey wash. ------
    for setting in ("material.multiply.magnificationFilter = .nearest",
                    "material.multiply.minificationFilter = .nearest"):
        if setting not in text:
            failed.append("%s does not set `%s` — an 8x8 tile magnified "
                          "across a face under the default linear filter "
                          "arrives as a soft grey wash, not a dither"
                          % (SWIFT, setting.split(" = ")[0].split(".")[-1]))
    if not any("filter" in f for f in failed):
        print("  %-26s ok (hard texels, no interpolation)" % "filtering")

    # --- 4. Multiply, never diffuse. -----------------------------------
    if re.search(r'material\.diffuse\.contents = dither', text):
        failed.append("%s puts the dither in the DIFFUSE channel — that "
                      "replaces the body colour instead of shading it, and "
                      "collapses the fifteen colourways the dice are told "
                      "apart by. It belongs in multiply." % SWIFT)
    else:
        print("  %-26s ok (body colour survives)" % "multiply channel")

    # --- 5. The Bayer matrix is the real one. --------------------------
    #
    # A transposed or mis-typed matrix still dithers and still looks broadly
    # plausible, while producing visible diagonal banding rather than an even
    # stipple. Checked against the arithmetic definition the floor's shader
    # uses, so the two cannot drift into different patterns.
    rows = re.search(r'private static let bayer8: \[\[Int\]\] = \[(.+?)\n    \]',
                     text, re.S)
    if not rows:
        failed.append("%s no longer declares the bayer8 matrix" % SWIFT)
    else:
        values = [int(v) for v in re.findall(r'-?\d+', rows.group(1))]
        if len(values) != 64 or sorted(values) != list(range(64)):
            failed.append("the bayer8 matrix is not a permutation of 0..63 — "
                          "it dithers unevenly, which reads as banding")
        else:
            worst = 0.0
            for y in range(8):
                for x in range(8):
                    want = preview.smoke.bayer8(x, y) * 64
                    worst = max(worst, abs(values[y * 8 + x] - want))
            if worst > 1e-6:
                failed.append("the bayer8 literal disagrees with the "
                              "arithmetic Bayer the floor's shader uses "
                              "(worst cell off by %g) — the dice and the "
                              "floor would stipple on different patterns"
                              % worst)
            else:
                print("  %-26s ok (matches the floor's, exactly)" % "bayer matrix")

    # --- 6. The numerals still clear the bar. --------------------------
    if preview.check_contrast() != 0:
        failed.append("some colourway's numeral drops below 3:1 under the "
                      "dither that was not already there")

    # --- 6b. The cel bands agree with the preview, and clear the bar. ---
    #
    # Same contract as the dither's strength and density: a number that ships
    # must be one the preview has modelled, or the figure below is measuring a
    # die that does not exist. These three constants decide every face's
    # colour, so drift here is invisible in the diff and obvious on the glass.
    for const, attr in (("celBands", "CEL_BANDS"),
                        ("celShadeFloor", "CEL_SHADE_FLOOR"),
                        ("celShadeCeiling", "CEL_SHADE_CEILING")):
        m = re.search(r'static let %s: Float = ([\d.]+)' % const, text)
        if not m:
            failed.append("%s no longer declares `%s`" % (SWIFT, const))
            continue
        shipped = float(m.group(1))
        previewed = float(getattr(preview, attr))
        if abs(shipped - previewed) > 1e-9:
            failed.append("%s = %g but tools_dice_preview models %g (%s) — "
                          "the contrast figures below would be measuring a "
                          "die that does not ship"
                          % (const, shipped, previewed, attr))
        else:
            print("  %-26s ok (%g, previewed)" % (const, shipped))

    if preview.check_band_contrast() != 0:
        failed.append("the cel shade pushes some colourway's numeral below "
                      "3:1 that cleared it flat — see the table above")

    # --- 7. No OpenGL-only spellings in ANY shader in this tree. -------
    #
    # The single most valuable check in this file, and it exists because the
    # exact bug it catches already happened: `u_time` in SmokeFloor's
    # modifier. SceneKit has not rendered with OpenGL on iOS for years — a
    # shader modifier is translated into Metal — so `u_time` compiled nowhere
    # and took the WHOLE MATERIAL with it:
    #
    #   [SceneKit] Error: FATAL ERROR : failed compiling shader:
    #   error: use of undeclared identifier 'u_time'
    #
    # Everything else in that shader was already Metal (float2/float3/float4
    # rather than vec2/vec3/vec4), which is exactly why one OpenGL-only
    # identifier was easy to miss — and why a list is worth more than care.
    # Nothing guarded this before.
    #
    # Scanned across every Swift file rather than just this one, since the
    # dice are now the second material in the tree carrying a modifier and
    # there is no reason to let the third be unguarded.
    glsl = {
        "u_time": "scn_frame.time",
        "u_inverseViewTransform": "scn_frame.inverseViewTransform",
        "texture2D(": "texture.sample(sampler, ...)",
        "gl_FragColor": "_output.color",
        "gl_Position": "_geometry.position",
    }
    for n in (2, 3, 4):
        glsl["vec%d" % n] = "float%d" % n
        glsl["mat%d" % n] = "float%dx%d" % (n, n)

    # Comments are stripped before scanning, and that is not fussiness: the
    # comment in SmokeFloor's shader that EXPLAINS the u_time bug names every
    # spelling in the table above, so an unstripped scan reports seven hits on
    # the very documentation that prevents the bug. The line count is
    # preserved so reported line numbers still point at real lines.
    def decomment(src):
        return "\n".join(line.split("//")[0] for line in src.split("\n"))

    shader_files = []
    for path in sorted(glob.glob(os.path.join(SWIFT_DIR, "*.swift"))):
        raw = open(path).read()
        if "shaderModifiers" in raw or "#pragma body" in raw:
            shader_files.append((path, decomment(raw)))
    if not shader_files:
        failed.append("no file in the tree carries a shader modifier any "
                      "more — this check has nothing left to guard, which "
                      "means the floor's or the dice's shading was removed")
    gl_hits = 0
    for path, body in shader_files:
        for bad, instead in glsl.items():
            # `vec3` must not match `float3`/`half3`, so require a boundary
            # before it. A trailing boundary would reject `vec3(` so is not
            # used; the opening paren and the declaration form both end in
            # something the pattern already covers.
            pattern = r'(?<![A-Za-z0-9_])' + re.escape(bad)
            for m in re.finditer(pattern, body):
                line = body[:m.start()].count("\n") + 1
                failed.append("%s:%d uses the OpenGL spelling `%s` — a "
                              "SceneKit shader modifier is compiled as "
                              "METAL, where this does not exist and takes "
                              "the whole material down with it. Use `%s`."
                              % (os.path.basename(path), line, bad, instead))
                gl_hits += 1
    if not gl_hits:
        print("  %-26s ok (Metal spellings only, %d file(s) carrying one)"
              % ("shader dialect", len(shader_files)))

    # --- 8. The fallback goes on BEFORE the shader. --------------------
    #
    # A shader modifier that fails to compile does so ASYNCHRONOUSLY, on the
    # render thread, rather than throwing — there is nothing to catch and
    # nothing to test for. SmokeFloor.apply documents the only workable
    # answer: put a working still appearance on first and layer the shader
    # over it. If it compiles it overwrites the result and the still is never
    # seen; if it does not, the still is already there.
    #
    # So the order of these two lines is load-bearing, and it is invisible as
    # a bug: get it wrong and the dice are fine on every device whose shader
    # compiles and black on the one where it does not.
    diffuse_at = text.find("material.diffuse.contents")
    shader_at = text.find("material.shaderModifiers")
    if shader_at == -1:
        failed.append("%s no longer sets `shaderModifiers` — the cel-shading "
                      "band is what makes a die read as pixel art rather "
                      "than smoothly shaded resin" % SWIFT)
    elif diffuse_at == -1 or diffuse_at > shader_at:
        failed.append("%s sets `shaderModifiers` before `diffuse.contents` — "
                      "a modifier that fails to compile would leave a BLACK "
                      "die rather than today's flat one. The fallback goes "
                      "on first; see SmokeFloor.apply." % SWIFT)
    else:
        print("  %-26s ok (still image, then shader)" % "compile fallback")

    # --- 9. No specular on the die body. -------------------------------
    #
    # A specular highlight is a continuous gradient, and banded lighting
    # turns a continuous gradient into a hard-edged bright blob — which reads
    # as a rendering fault rather than as a style. Lambert has no specular
    # term at all, so it physically cannot produce one.
    if "material.lightingModel = .lambert" not in text:
        failed.append("%s no longer sets the die body to `.lambert` — any "
                      "lighting model with a specular term puts a smooth "
                      "highlight back on a banded face" % SWIFT)
    elif re.search(r'material\.(specular\.contents|shininess)\s*=', text):
        failed.append("%s still sets specular or shininess on the die body — "
                      "harmless under .lambert, but it is a trap for the "
                      "next reader and it survives a lighting-model change"
                      % SWIFT)
    else:
        print("  %-26s ok (lambert, no highlight)" % "no specular")

    # --- 10. Label canvases stay small, and filter .nearest. -----------
    #
    # The numerals were 256px minified onto a ~100-200pt face with the
    # DEFAULT LINEAR filter, which made them the one perfectly smooth thing
    # on an otherwise banded, stippled, hard-edged die. Both halves matter:
    # a small canvas with linear filtering is a blurry numeral, and a large
    # canvas with .nearest is a crisp anti-aliased one.
    labels = source("DieFaceLabels.swift")
    for const, ceiling in (("labelCanvas", 64), ("wordmarkCanvas", 128)):
        m = re.search(r'static let %s: CGFloat = ([\d.]+)' % const, labels)
        if not m:
            failed.append("DieFaceLabels.swift no longer declares `%s`"
                          % const)
        elif float(m.group(1)) > ceiling:
            failed.append("%s = %s is above %d — at that size the glyph is "
                          "oversampled for the face it lands on and arrives "
                          "ANTI-ALIASED, which is the one smooth thing left "
                          "on a banded die" % (const, m.group(1), ceiling))
        else:
            print("  %-26s ok (%s px)" % (const, m.group(1)))

    if not re.search(r'material\.diffuse\.magnificationFilter\s*=\s*\.nearest',
                     labels):
        failed.append("DieFaceLabels.artworkMaterial does not set "
                      "`diffuse.magnificationFilter = .nearest` — a small "
                      "canvas magnified under the default linear filter is a "
                      "BLURRY numeral, which is worse than a crisp one")
    elif not re.search(r'material\.diffuse\.minificationFilter\s*=\s*\.nearest',
                       labels):
        failed.append("DieFaceLabels.artworkMaterial sets magnification but "
                      "not minification to .nearest — a die tumbling away "
                      "from the camera would soften as it shrank")
    else:
        print("  %-26s ok (hard texels both ways)" % "label filtering")

    if failed:
        print()
        for line in failed:
            print("  FAIL  %s" % line)
        print("\ndice: FAIL (%d)" % len(failed))
        return 1
    print("\ndice: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
