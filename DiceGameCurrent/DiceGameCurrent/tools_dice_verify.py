"""Checks how the dice are shaded, against the model that can be looked at.

Same job as tools_smoke_verify does for the floor and tools_wood_verify for
the timber, and the same reason: the shading exists twice, as Swift in
`DieMaterialFactory` and as Python in `tools_dice_preview.py`, and only the
Python one can be looked at in this container.

A die body is FLAT COLOUR with no texture on any channel, banded into five
tone steps by a fragment shader. An ordered Bayer dither used to sit in the
multiply channel and this file used to be mostly about it; it was deleted
because it had no counterpart in the reference art AND because it was the
source of a real bug — an 8x8 tile sampled `.nearest` with no mipmaps
aliased badly once a face went oblique, which read as the texture popping in
and out as dice tumbled.

What is guarded now, each of which is invisible until it is wrong and then
unmissable:

    the numerals are unreachable   the body material must be set on the die
                                   body ALONE, with the numerals on their own
                                   nodes. The cel band is a fragment modifier
                                   on this material, so a shared one would
                                   band and darken the numerals too.
    flat body                      no texture on any channel, so a stipple
                                   cannot creep back in and bring its
                                   aliasing with it.
    Metal, not OpenGL              no shader in the tree may use a GLSL-only
                                   spelling. `u_time` once took a whole
                                   material down this way.
    fallback before shader         a modifier that fails to compile does so
                                   asynchronously, so the still appearance
                                   must be assigned first.
    no specular                    a smooth highlight quantised by banding
                                   becomes a hard-edged blob.
    constants match the preview    the bands and their range decide every
                                   face's colour.
    legible on the read face       the contrast check, narrowed to the top
                                   band on purpose — see check_band_contrast.

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


# Large numerals on a die face: WCAG's large-text bar is 3:1, and the
# normal-text bar is 4.5:1. The first is the one that must hold for every
# colourway; the second is reported.
LARGE_TEXT_CONTRAST = 3.0
NORMAL_TEXT_CONTRAST = 4.5


def _luminance(hexcode):
    value = hexcode.lstrip("#")
    channels = []
    for offset in (0, 2, 4):
        raw = int(value[offset:offset + 2], 16) / 255.0
        channels.append(raw / 12.92 if raw <= 0.03928
                        else ((raw + 0.055) / 1.055) ** 2.4)
    return (0.2126 * channels[0] + 0.7152 * channels[1]
            + 0.0722 * channels[2])


def _contrast(one, other):
    a, b = _luminance(one), _luminance(other)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)


def check_numerals(failed):
    """Every die's numeral is readable on its own body.

    `numberHex` was a second hex typed beside `bodyHex` with nothing
    checking the pair, and six of fifteen colourways failed AA — five of
    them backwards, carrying white where the dark ink had twice the
    contrast. Worse, two call sites built their own: Rollbots' seat dice,
    and Baseball's batter die, whose body is WHATEVER SWATCH THE PLAYER
    PICKED. On Onyx that was #1B1B1F on #14140F — 1.08:1, a black numeral
    on a black die.

    So the ink is derived from the body now, and this asserts the two
    things that makes true: that the derivation picks the better ink, and
    that no call site has gone back to typing one.
    """
    source_text = source("DiceGame.swift")

    light = re.search(r'static let lightInk = "(#\w{6})"', source_text)
    dark = re.search(r'static let darkInk = "(#\w{6})"', source_text)
    if not light or not dark:
        failed.append("DiePalette no longer declares lightInk and darkInk, "
                      "so there is no pair to choose a numeral from")
        return
    light, dark = light.group(1), dark.group(1)

    bodies = re.findall(r'DieColorway\(bodyHex: "(#\w{6})"\)', source_text)
    if not bodies:
        failed.append("no colourways found in DiePalette")
        return

    # Baseball's batter die takes the table colour, so every swatch is a
    # die body too and has to clear the same bar.
    bodies += re.findall(r'Swatch\(hex: "(#\w{6})"', source("AppTheme.swift"))
    bodies.append("#0A0A0C")                    # Baseball's pitcher die
    # Rollbots' two seat colours, read rather than copied.
    for pair in re.findall(r'"(#\w{6})" : "(#\w{6})"',
                           source("RollbotsArt.swift")):
        bodies.extend(pair)

    worst = ("", 99.0)
    below_aa = []
    for body in bodies:
        chosen = light if _contrast(body, light) >= _contrast(body, dark) else dark
        ratio = _contrast(body, chosen)
        if ratio < worst[1]:
            worst = (body, ratio)
        if ratio < NORMAL_TEXT_CONTRAST:
            below_aa.append("%s %.2f:1" % (body, ratio))
        if ratio < LARGE_TEXT_CONTRAST:
            failed.append("a %s die's numeral comes out at %.2f:1, under the "
                          "%.1f:1 large-text bar, and neither ink does better"
                          % (body, ratio, LARGE_TEXT_CONTRAST))

    # And nobody types an ink any more.
    for filename in sorted(os.listdir(SWIFT_DIR)):
        if not filename.endswith(".swift"):
            continue
        body = source(filename)
        if re.search(r'DieColorway\([^)]*numberHex:', body):
            failed.append("%s builds a DieColorway with its own numberHex — "
                          "the ink is derived from the body so that a dark "
                          "die always gets a light numeral" % filename)

    note = ""
    if below_aa:
        note = ", under 4.5:1 on %s (fine for large numerals)" % ", ".join(below_aa)
    print("  %-26s ok (%d bodies, worst %s at %.2f:1%s)"
          % ("numeral contrast", len(bodies), worst[0], worst[1], note))


def main():
    text = source(SWIFT)
    failed = []

    # --- 2. The body's shading cannot reach the numerals. --------------
    #
    # Two halves, and both have to hold. The body material must be assigned
    # as the die's WHOLE material list (so it is the body and nothing else),
    # and the numerals must be their own nodes carrying their own geometry.
    #
    # This was written for the ordered dither, which has since been deleted,
    # and it is kept because what it protects did not go away with it: the
    # cel shader is a FRAGMENT modifier on this material, so if a numeral
    # ever shared it, every numeral would be banded and darkened along with
    # the face behind it. The darkest band is 0.172 — a numeral driven to
    # that is gone.
    if "node.geometry?.materials = [material]" not in text:
        failed.append("%s no longer assigns the body material as the node's "
                      "entire material list — if a numeral ever shares this "
                      "material, the cel band is applied straight through "
                      "it, which is the one thing this treatment must never "
                      "do" % SWIFT)
    else:
        print("  %-26s ok (body material only)" % "numerals unreachable")

    labels = source(LABELS)
    if "SCNPlane(" not in labels:
        failed.append("%s no longer builds numerals as their own SCNPlane "
                      "nodes — they may now share the body's material, and "
                      "the cel band would be applied through them" % LABELS)

    # --- 6b. The cel bands agree with the preview, and clear the bar. ---
    #
    # Same contract as the dither's strength and density: a number that ships
    # must be one the preview has modelled, or the figure below is measuring a
    # die that does not exist. These three constants decide every face's
    # colour, so drift here is invisible in the diff and obvious on the glass.
    for const, attr in (("celBands", "CEL_BANDS"),
                        ("celShadeFloor", "CEL_SHADE_FLOOR"),
                        ("celShadeCeiling", "CEL_SHADE_CEILING"),
                        ("celShadeGamma", "CEL_SHADE_GAMMA")):
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

    # --- 6c. The die body carries no texture, in any channel. ----------
    #
    # The reference this look is built from has no texture of any kind: every
    # facet is one flat colour, and the form comes entirely from how the light
    # bands across the facets. A stipple was tried here and removed for two
    # reasons at once, which is why this is a guard and not merely a deletion.
    #
    # It was wrong for the look — it has no counterpart in the reference — and
    # it was the source of a real bug: an 8x8 tile sampled `.nearest` with no
    # mipmaps, so a face going oblique as a die tumbled compressed twenty
    # cells into a few screen pixels and the sampled texel jumped frame to
    # frame. It read as the texture popping in and out, and turning
    # antialiasing off had removed the supersampling that was masking it.
    #
    # ONE EXEMPTION, and it is bounded rather than a hole. The older
    # photographic `grain` path is still in the file behind
    # `applyGrainToDice`, which is false and has been for a long time — it is
    # dead code from before this look existed, and removing it would reach
    # into DiceSceneBuilder's plumbing and two cross-file comments for no
    # gain. So an assignment of `grain` is skipped, but ONLY while that flag
    # reads false, which is asserted right here. Flip the flag and this check
    # fires, which is the correct behaviour: the exemption exists because the
    # branch cannot run, not because grain is allowed.
    if not re.search(r'applyGrainToDice\s*=\s*false', text):
        failed.append("%s no longer pins `applyGrainToDice = false` — the "
                      "flat-body check below exempts the grain branch only "
                      "because it cannot run. Either keep it false or delete "
                      "the branch." % SWIFT)

    texture_bad = 0
    for channel in ("multiply", "diffuse", "normal", "emission"):
        for m in re.finditer(r'material\.%s\.contents\s*=\s*(\w+)' % channel,
                             text):
            assigned = m.group(1)
            if assigned.startswith("UIColor"):
                continue              # a flat colour is the whole point
            if assigned == "grain":
                continue              # bounded exemption, asserted above
            failed.append("%s:%d assigns `%s` to material.%s.contents on the "
                          "die body — the body is flat colour. A texture here "
                          "both misses the look and aliases as the die "
                          "tumbles; see this check's comment."
                          % (SWIFT, text[:m.start()].count("\n") + 1,
                             assigned, channel))
            texture_bad += 1
    if not texture_bad:
        print("  %-26s ok (flat colour, no texture)" % "flat body")

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

    check_numerals(failed)

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
