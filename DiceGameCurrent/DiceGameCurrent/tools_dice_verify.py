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
import math
import os
import re
import sys

from tools_swiftconst import source, RESOURCES, SWIFT as SWIFT_DIR

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


def die_faces(path):
    """Each numbered face's inscribed radius, straight out of the .obj.

    The meshes are triangulated and chamfered, so neither thing a reader
    wants is in the file: a d12's "face" is a dozen triangles, and the
    bevel between faces is dozens more. Triangles are grouped by the plane
    they lie in, the boundary of a group is the edges only one triangle
    owns, and the inscribed radius is the shortest distance from the
    group's centroid to that boundary. The numbered faces are the large
    groups; the chamfer facets fall out as the small ones.

    Returns radii in the mesh's own local units — what labelSize is in.
    """
    verts, tris = [], []
    for line in open(path):
        if line.startswith("v "):
            verts.append(tuple(float(x) for x in line.split()[1:4]))
        elif line.startswith("f "):
            idx = [int(part.split("/")[0]) for part in line.split()[1:]]
            idx = [i - 1 if i > 0 else len(verts) + i for i in idx]
            for k in range(1, len(idx) - 1):
                tris.append((idx[0], idx[k], idx[k + 1]))

    planes = {}
    for tri in tris:
        a, b, c = (verts[i] for i in tri)
        u = [b[i] - a[i] for i in range(3)]
        v = [c[i] - a[i] for i in range(3)]
        n = [u[1] * v[2] - u[2] * v[1],
             u[2] * v[0] - u[0] * v[2],
             u[0] * v[1] - u[1] * v[0]]
        length = math.sqrt(sum(x * x for x in n)) or 1.0
        n = [x / length for x in n]
        key = (round(n[0], 3), round(n[1], 3), round(n[2], 3),
               round(sum(n[i] * a[i] for i in range(3)), 3))
        planes.setdefault(key, []).append(tri)

    radii = []
    for group in planes.values():
        edges = {}
        for tri in group:
            for i in range(3):
                edge = tuple(sorted((tri[i], tri[(i + 1) % 3])))
                edges[edge] = edges.get(edge, 0) + 1
        border = [e for e, count in edges.items() if count == 1]
        points = {i for e in border for i in e}
        if not points:
            continue
        centre = [sum(verts[i][k] for i in points) / len(points)
                  for k in range(3)]
        best = None
        for i, j in border:
            a, b = verts[i], verts[j]
            ab = [b[k] - a[k] for k in range(3)]
            ac = [centre[k] - a[k] for k in range(3)]
            squared = sum(x * x for x in ab)
            t = (sum(ac[k] * ab[k] for k in range(3)) / squared) if squared else 0.0
            t = max(0.0, min(1.0, t))
            near = [a[k] + t * ab[k] for k in range(3)]
            d = math.dist(near, centre)
            best = d if best is None else min(best, d)
        radii.append(best)

    biggest = max(radii)
    return [r for r in radii if r > biggest * 0.6]


def check_numeral_fit(failed):
    """No numeral may run off the face it is printed on.

    This is the check that was missing while the sizes were chosen by eye.
    A numeral that crosses a face edge throws nothing and logs nothing —
    it is simply a die that looks wrong, on one of twenty faces, which is
    why it survived two rounds of "worth a look on device".

    Both halves are measured rather than trusted: the inscribed radii in
    the Swift are checked against the shipped .obj files, and then every
    numeral each die can show is sized the way DieFaceLabels sizes it and
    held inside its face.
    """
    labels = source(LABELS)

    face_use = float(re.search(r'faceUse: CGFloat = ([\d.]+)', labels).group(1))
    fill_six, fill_rest = (float(x) for x in re.search(
        r'sides == 6 \? ([\d.]+) / ([\d.]+) : ([\d.]+)', labels).group(1, 3))
    fill_six = fill_six / float(re.search(
        r'sides == 6 \? [\d.]+ / ([\d.]+)', labels).group(1))
    six_plane = float(re.search(r'if sides == 6 \{ return ([\d.]+) \}',
                                labels).group(1))
    # The half-diagonals the Swift sizes against, and the squeeze it draws
    # two digits at. Read rather than restated, then checked against the
    # font itself below — the pair of them is what makes a numeral fit.
    swift_single = float(re.search(r'number >= 10 \? [\d.]+ : ([\d.]+)',
                                   labels).group(1))
    swift_double = float(re.search(r'number >= 10 \? ([\d.]+) :', labels).group(1))
    squeeze = float(re.search(r'twoDigitSqueeze: CGFloat = ([\d.]+)',
                              labels).group(1))

    def half_diagonal(number):
        return swift_double if number >= 10 else swift_single

    # And those two numbers are checked against the TYPEFACE, which is the
    # whole reason they changed: they used to be worked out from "a digit
    # is about 0.70 em tall and 0.60 wide", and the real ink is 8% wider
    # than that for a single digit and 3% for a pair. A numeral sized
    # against a box smaller than itself does not look wrong — it just has
    # less margin than the code says it has, and the first thing anyone
    # would notice is a glyph touching a chamfer on one die.
    #
    # Measured the way the app draws it: every numeral 1 to 20, two digits
    # narrowed by the squeeze, worst case of each class.
    try:
        from PIL import ImageFont
    except ImportError:
        print("  %-26s skipped (Pillow unavailable)" % "numeral ink")
    else:
        face = os.path.join(RESOURCES, "Poppins-SemiBold.ttf")
        font = ImageFont.truetype(face, 1000)
        measured = {1: 0.0, 2: 0.0}
        for number in range(1, 21):
            text = str(number)
            x0, y0, x1, y1 = font.getbbox(text)
            width = (x1 - x0) / 1000.0
            height = (y1 - y0) / 1000.0
            if len(text) > 1:
                width *= squeeze
            reach = 0.5 * math.sqrt(width * width + height * height)
            digits = 2 if len(text) > 1 else 1
            measured[digits] = max(measured[digits], reach)
        for digits, stated in ((1, swift_single), (2, swift_double)):
            if measured[digits] > stated + 0.0005:
                failed.append("DieFaceLabels sizes a %d-digit numeral "
                              "against %.4f em, and Poppins-SemiBold draws "
                              "one %.4f em across its diagonal — every one "
                              "of them is bigger than the face it was fitted "
                              "to" % (digits, stated, measured[digits]))
        print("  %-26s ok (1 digit %.4f em, 2 at %.0f%% width %.4f em)"
              % ("numeral ink", measured[1], squeeze * 100, measured[2]))

    d4_plane = float(re.search(r'd4TopReadLabelSize: CGFloat = ([\d.]+)',
                               labels).group(1))
    d4_pip = float(re.search(r'd4PipLabelSize: CGFloat = ([\d.]+)',
                             labels).group(1))
    d4_offset = float(re.search(r'd4CornerLabelRadiusFraction: Float = ([\d.]+)',
                                labels).group(1))
    d4_limit = float(re.search(r'd4FaceReachLimit: Float = ([\d.]+)',
                               labels).group(1))
    d4_safety = float(re.search(r'd4CornerLabelSafety: Float = ([\d.]+)',
                                labels).group(1))
    d4_inradius = float(re.search(r'case 4: return ([\d.]+)',
                                  labels[labels.index("func localFaceDistance"):]
                                  ).group(1))

    # Bounded to the function's own body. Read to end-of-file it swept up
    # localFaceDistance's table further down — a different set of numbers
    # about a different thing, which made this report a mesh mismatch that
    # was really a parsing bug.
    body = labels[labels.index("func inscribedRadius"):]
    body = body[: body.index("\n    }")]
    declared = {int(sides): float(radius)
                for sides, radius in re.findall(r'case (\d+):\s*return ([\d.]+)',
                                                body)}

    worst = (0.0, "")
    for sides in (4, 6, 8, 10, 12, 20):
        measured = die_faces(os.path.join(RESOURCES, "d%d.obj" % sides))
        if len(measured) != sides:
            failed.append("d%d.obj merges to %d numbered faces, not %d — the "
                          "mesh changed shape, and every numeral on it is "
                          "sized from a face that is no longer there"
                          % (sides, len(measured), sides))
            continue
        radius = min(measured)
        if abs(radius - declared.get(sides, 0)) > 0.005:
            failed.append("DieFaceLabels says a d%d face holds a circle of "
                          "%.3f; d%d.obj measures %.3f. The numerals are "
                          "sized off that number"
                          % (sides, declared.get(sides, 0), sides, radius))
            continue

        fill = fill_six if sides == 6 else fill_rest

        # A d4 carries TWO layouts and they are bounded differently.
        #
        # Free Roll's and Royal UR's are read at the APEX: three labels
        # share a face, each pushed out toward a corner, so what bounds
        # one is the chamfered face's own reach rather than the circle
        # that fits inside it. Jackpot's is one numeral in the middle,
        # which is the same case as every other die and falls through to
        # the loop below.
        #
        # The corner numerals doubled, which is why this models the
        # Swift's placement rather than approximating it: the offset is
        # pulled in as the label grows, and a model that assumed a fixed
        # fraction would have reported a collision that the code does not
        # have — or missed one it does.
        if sides == 4:
            # The reach limit is a measurement of the same mesh, so it is
            # checked against it rather than trusted: on a triangular face
            # the distance to a corner is twice the distance to an edge,
            # and the chamfer takes both down together.
            if abs(d4_limit - radius * 2) > 0.05:
                failed.append("DieFaceLabels says a d4 face reaches %.3f, "
                              "but d4.obj holds a circle of %.3f and a "
                              "triangle's corner is twice its edge — the "
                              "corner labels are placed against that number"
                              % (d4_limit, radius))
            circumradius = d4_inradius * math.sqrt(8)
            for plane, what in ((d4_plane, "a d4's corner numerals"),
                                (d4_pip, "a Royal UR die's pips")):
                half = 0.461 * fill * plane
                offset = min(circumradius * d4_offset,
                             d4_limit * d4_safety - half)
                reach = offset + half
                if reach > d4_limit:
                    failed.append("%s reach %.3f across a face that stops "
                                  "at %.3f" % (what, reach, d4_limit))
                # Three of them, 120 degrees apart, so the gap between two
                # centres is the offset times root three.
                if offset * math.sqrt(3) < half * 2:
                    failed.append("%s are %.3f apart and %.3f wide — they "
                                  "overlap each other"
                                  % (what, offset * math.sqrt(3), half * 2))
                if reach / d4_limit > worst[0]:
                    worst = (reach / d4_limit, what)

        for number in range(1, sides + 1):
            half_em = half_diagonal(number)
            if sides == 6:
                plane = six_plane
            else:
                plane = face_use * radius / (half_em * fill)
            half = half_em * fill * plane
            if half > radius:
                failed.append("a d%d's %d reaches %.3f from the middle of a "
                              "face that holds %.3f — it runs off the edge"
                              % (sides, number, half, radius))
            if half / radius > worst[0]:
                worst = (half / radius, "a d%d's %d" % (sides, number))

    if not failed:
        print("  %-26s ok (6 meshes measured, worst is %s at %.0f%% of its "
              "face)" % ("numerals fit", worst[1], worst[0] * 100))


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

    # --- 10. Label canvases stay BELOW THE FACE, and filter .nearest. --
    #
    # These ceilings used to be 64 and 128, holding the canvases down so
    # the numerals read as pixel art — the die body being a banded cel
    # shade inside a hard silhouette, a smooth numeral was the one soft
    # thing left on it. That was the right call when a numeral was one
    # digit; it was the wrong one for a two-digit d20 face, where each
    # digit came to about twelve texels and an 8 and a 9 stopped being
    # distinguishable. The canvases went up and the ceilings with them.
    #
    # They are still ceilings, because the reason they exist did not go
    # away — it moved. A texture BIGGER than the face it lands on is
    # minified rather than magnified, and `.nearest` with no mipmaps
    # shimmers under minification as a die tumbles. A die is roughly
    # 100-200pt on screen, which at 3x is 300-600 device pixels; 128 keeps
    # every numeral on the magnifying side of that with room to spare, and
    # the wordmark is one image on one face rather than one of twenty.
    #
    # The filter check below is the half that never moved: a canvas of any
    # size magnified under the default LINEAR filter is a blurry numeral.
    labels = source("DieFaceLabels.swift")
    for const, ceiling in (("labelCanvas", 128), ("wordmarkCanvas", 256)):
        m = re.search(r'static let %s: CGFloat = ([\d.]+)' % const, labels)
        if not m:
            failed.append("DieFaceLabels.swift no longer declares `%s`"
                          % const)
        elif float(m.group(1)) > ceiling:
            failed.append("%s = %s is above %d — bigger than the face it "
                          "lands on, so it arrives MINIFIED, and .nearest "
                          "with no mipmaps shimmers on a tumbling die"
                          % (const, m.group(1), ceiling))
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
    check_numeral_fit(failed)

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
