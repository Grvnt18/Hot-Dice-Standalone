"""A TrueType rasteriser, because there is no other way to see the type.

There is no PIL in this container, no ImageMagick, no Swift and no device.
Every other preview here draws its own shapes, which is fine for a plank or a
noise field and useless for a typeface: the whole question about Poppins and
Lobster is what the letterforms look like at the sizes the app uses them, and
no amount of rectangles answers that.

Both faces are TrueType `glyf` outlines with format-4 cmaps — the simplest
case there is — so this parses them directly: cmap for character to glyph,
loca for where the glyph lives, glyf for its contours, hmtx for how far to
advance. Quadratic curves are flattened, contours are filled by scanline with
the nonzero winding rule, and the result is an alpha coverage map the previews
composite like any other layer.

Deliberately not a text engine. No kerning (the `kern` and GPOS tables are
ignored), no shaping, no bidi, no hinting, no subpixel positioning. It renders
left-to-right Latin at a size, which is exactly what the previews need and
nothing more.

    python3 tools_type.py        # a specimen sheet of both faces
"""
import os
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
RESOURCES = os.path.join(HERE, "Resources")

# 3x3 supersampling. Type is the one thing in these previews that is NOT
# pixel art — the panels and the floor want hard edges, the letterforms want
# to be readable — so this is the one place a preview antialiases.
SUPERSAMPLE = 3


class Face:
    """One font file, parsed far enough to draw with."""

    def __init__(self, path):
        self.data = d = open(path, "rb").read()
        self.tables = {}
        for i in range(struct.unpack(">H", d[4:6])[0]):
            o = 12 + i * 16
            tag = d[o:o + 4].decode("latin-1")
            self.tables[tag] = struct.unpack(">II", d[o + 8:o + 16])

        head = self.tables["head"][0]
        self.upem = struct.unpack(">H", d[head + 18:head + 20])[0]
        self.long_loca = struct.unpack(">h", d[head + 50:head + 52])[0]

        hhea = self.tables["hhea"][0]
        self.ascent = struct.unpack(">h", d[hhea + 4:hhea + 6])[0]
        self.descent = struct.unpack(">h", d[hhea + 6:hhea + 8])[0]
        self.num_hmetrics = struct.unpack(">H", d[hhea + 34:hhea + 36])[0]

        self._cmap = self._parse_cmap()
        self._glyph_cache = {}

    # --- tables ----------------------------------------------------------

    def _parse_cmap(self):
        d = self.data
        base = self.tables["cmap"][0]
        chosen = None
        for i in range(struct.unpack(">H", d[base + 2:base + 4])[0]):
            r = base + 4 + i * 8
            _pid, _eid, off = struct.unpack(">HHI", d[r:r + 8])
            if struct.unpack(">H", d[base + off:base + off + 2])[0] == 4:
                chosen = base + off
        if chosen is None:
            raise ValueError("no format-4 cmap subtable")

        seg2 = struct.unpack(">H", d[chosen + 6:chosen + 8])[0]
        n = seg2 // 2
        ends = chosen + 14
        starts = ends + seg2 + 2
        deltas = starts + seg2
        ranges = deltas + seg2
        return (n, ends, starts, deltas, ranges)

    def glyph_id(self, ch):
        d = self.data
        n, ends, starts, deltas, ranges = self._cmap
        c = ord(ch)
        for i in range(n):
            end = struct.unpack(">H", d[ends + i * 2:ends + i * 2 + 2])[0]
            if end < c:
                continue
            start = struct.unpack(">H", d[starts + i * 2:starts + i * 2 + 2])[0]
            if start > c:
                return 0
            delta = struct.unpack(">h", d[deltas + i * 2:deltas + i * 2 + 2])[0]
            rng = struct.unpack(">H", d[ranges + i * 2:ranges + i * 2 + 2])[0]
            if rng == 0:
                return (c + delta) & 0xFFFF
            p = ranges + i * 2 + rng + (c - start) * 2
            g = struct.unpack(">H", d[p:p + 2])[0]
            return 0 if g == 0 else (g + delta) & 0xFFFF
        return 0

    def advance(self, gid):
        d = self.data
        hmtx = self.tables["hmtx"][0]
        gid = min(gid, self.num_hmetrics - 1)
        return struct.unpack(">H", d[hmtx + gid * 4:hmtx + gid * 4 + 2])[0]

    def _glyph_range(self, gid):
        d = self.data
        loca = self.tables["loca"][0]
        if self.long_loca:
            s = struct.unpack(">I", d[loca + gid * 4:loca + gid * 4 + 4])[0]
            e = struct.unpack(">I", d[loca + gid * 4 + 4:loca + gid * 4 + 8])[0]
        else:
            s = struct.unpack(">H", d[loca + gid * 2:loca + gid * 2 + 2])[0] * 2
            e = struct.unpack(">H", d[loca + gid * 2 + 2:loca + gid * 2 + 4])[0] * 2
        return s, e

    # --- outlines --------------------------------------------------------

    def contours(self, gid, depth=0):
        """Closed contours in font units, quadratics already flattened."""
        if gid in self._glyph_cache:
            return self._glyph_cache[gid]

        d = self.data
        glyf = self.tables["glyf"][0]
        s, e = self._glyph_range(gid)
        if e <= s or depth > 4:
            self._glyph_cache[gid] = []
            return []

        p = glyf + s
        n_contours = struct.unpack(">h", d[p:p + 2])[0]
        p += 10

        if n_contours < 0:
            out = self._composite(p, depth)
            self._glyph_cache[gid] = out
            return out

        ends = [struct.unpack(">H", d[p + i * 2:p + i * 2 + 2])[0]
                for i in range(n_contours)]
        p += n_contours * 2
        n_points = (ends[-1] + 1) if ends else 0
        p += 2 + struct.unpack(">H", d[p:p + 2])[0]     # skip instructions

        flags = []
        while len(flags) < n_points:
            f = d[p]; p += 1
            flags.append(f)
            if f & 8:                                    # repeat
                r = d[p]; p += 1
                flags.extend([f] * r)
        flags = flags[:n_points]

        def coords(short_bit, same_bit):
            vals, v = [], 0
            nonlocal p
            for f in flags:
                if f & short_bit:
                    delta = d[p]; p += 1
                    v += delta if (f & same_bit) else -delta
                elif not (f & same_bit):
                    v += struct.unpack(">h", d[p:p + 2])[0]; p += 2
                vals.append(v)
            return vals

        xs = coords(2, 16)
        ys = coords(4, 32)

        out, start = [], 0
        for end in ends:
            pts = [(xs[i], ys[i], bool(flags[i] & 1))
                   for i in range(start, end + 1)]
            start = end + 1
            if pts:
                out.append(self._flatten(pts))
        self._glyph_cache[gid] = out
        return out

    def _composite(self, p, depth):
        """Accented and built-up glyphs, which reference other glyphs."""
        d = self.data
        out = []
        while True:
            flags, index = struct.unpack(">HH", d[p:p + 4]); p += 4
            if flags & 1:                                # ARG_1_AND_2_ARE_WORDS
                a1, a2 = struct.unpack(">hh", d[p:p + 4]); p += 4
            else:
                a1, a2 = struct.unpack(">bb", d[p:p + 2]); p += 2
            sx = sy = 1.0
            if flags & 8:                                # WE_HAVE_A_SCALE
                sx = sy = struct.unpack(">h", d[p:p + 2])[0] / 16384.0; p += 2
            elif flags & 64:                             # X_AND_Y_SCALE
                sx, sy = [v / 16384.0 for v in struct.unpack(">hh", d[p:p + 4])]
                p += 4
            elif flags & 128:                            # TWO_BY_TWO
                p += 8                                   # rare; treat as identity
            dx, dy = (a1, a2) if (flags & 2) else (0, 0)  # ARGS_ARE_XY_VALUES
            for c in self.contours(index, depth + 1):
                out.append([(x * sx + dx, y * sy + dy) for x, y in c])
            if not (flags & 32):                         # MORE_COMPONENTS
                break
        return out

    @staticmethod
    def _flatten(pts, steps=8):
        """TrueType quadratics to a polyline.

        On-curve and off-curve points alternate, but not reliably: two
        consecutive off-curve points imply an on-curve point midway between
        them, which is the format's own compression and the thing that makes
        a naive reader draw garbage.
        """
        # Rotate so the contour starts on-curve, inserting the implied
        # midpoint if every point is off-curve.
        first_on = next((i for i, p in enumerate(pts) if p[2]), None)
        if first_on is None:
            x0 = (pts[0][0] + pts[-1][0]) / 2.0
            y0 = (pts[0][1] + pts[-1][1]) / 2.0
            pts = [(x0, y0, True)] + pts
            first_on = 0
        pts = pts[first_on:] + pts[:first_on]

        poly = [(pts[0][0], pts[0][1])]
        i, n = 1, len(pts)
        while i <= n:
            cur = pts[i % n]
            if cur[2]:
                poly.append((cur[0], cur[1]))
                i += 1
                continue
            nxt = pts[(i + 1) % n]
            if nxt[2]:
                end = (nxt[0], nxt[1])
                i += 2
            else:
                end = ((cur[0] + nxt[0]) / 2.0, (cur[1] + nxt[1]) / 2.0)
                i += 1
            sx, sy = poly[-1]
            for s in range(1, steps + 1):
                t = s / steps
                u = 1 - t
                poly.append((u * u * sx + 2 * u * t * cur[0] + t * t * end[0],
                             u * u * sy + 2 * u * t * cur[1] + t * t * end[1]))
        return poly

    # --- rendering -------------------------------------------------------

    def measure(self, text, size):
        scale = size / self.upem
        return sum(self.advance(self.glyph_id(c)) for c in text) * scale

    def coverage(self, text, size):
        """Render to an alpha map: (width, height, baseline, rows of 0..255).

        Nonzero winding, scanline, supersampled vertically and horizontally.
        Slow and obvious rather than clever — it runs a handful of times per
        preview, not per frame.
        """
        scale = size / self.upem
        ss = SUPERSAMPLE

        pad = int(size * 0.35) + 2          # room for overhang; Lobster needs it
        w = int(self.measure(text, size)) + pad * 2
        asc = self.ascent * scale
        desc = -self.descent * scale
        h = int(asc + desc) + pad * 2
        baseline = int(asc) + pad

        edges = []                           # (x0, y0, x1, y1) in device px
        pen = float(pad)
        for ch in text:
            gid = self.glyph_id(ch)
            for contour in self.contours(gid):
                n = len(contour)
                for i in range(n):
                    ax, ay = contour[i]
                    bx, by = contour[(i + 1) % n]
                    x0 = pen + ax * scale
                    y0 = baseline - ay * scale
                    x1 = pen + bx * scale
                    y1 = baseline - by * scale
                    if y0 != y1:
                        edges.append((x0, y0, x1, y1))
            pen += self.advance(gid) * scale

        rows = [bytearray(w) for _ in range(h)]
        if not edges:
            return w, h, baseline, rows

        ymin = max(0, int(min(min(e[1], e[3]) for e in edges)))
        ymax = min(h - 1, int(max(max(e[1], e[3]) for e in edges)) + 1)

        acc = [0] * w
        for y in range(ymin, ymax + 1):
            for k in range(w):
                acc[k] = 0
            for sub in range(ss):
                sy = y + (sub + 0.5) / ss
                xs = []
                for x0, y0, x1, y1 in edges:
                    if (y0 <= sy < y1) or (y1 <= sy < y0):
                        t = (sy - y0) / (y1 - y0)
                        xs.append((x0 + t * (x1 - x0), 1 if y1 > y0 else -1))
                if not xs:
                    continue
                xs.sort()
                wind = 0
                spans = []
                for i in range(len(xs) - 1):
                    wind += xs[i][1]
                    if wind != 0:
                        spans.append((xs[i][0], xs[i + 1][0]))
                for sx, ex in spans:
                    # Horizontal coverage, so stems land softly instead of
                    # snapping a whole pixel wide.
                    a = max(0.0, sx)
                    b = min(float(w), ex)
                    if b <= a:
                        continue
                    ia, ib = int(a), int(b)
                    if ia == ib:
                        acc[ia] += int(255 * (b - a)) // ss
                    else:
                        acc[ia] += int(255 * (ia + 1 - a)) // ss
                        for k in range(ia + 1, min(ib, w)):
                            acc[k] += 255 // ss
                        if ib < w:
                            acc[ib] += int(255 * (b - ib)) // ss
            row = rows[y]
            for k in range(w):
                v = acc[k]
                row[k] = 255 if v > 255 else v
        return w, h, baseline, rows


_cache = {}


def face(name):
    """`name` is a PostScript name: Poppins-SemiBold, Lobster-Regular, ..."""
    if name not in _cache:
        _cache[name] = Face(os.path.join(RESOURCES, name + ".ttf"))
    return _cache[name]


def blit(target, cov, x, y, colour, palette):
    """Composite a coverage map onto an indexed-colour image.

    The previews are palette images, so there is no blending to do — a pixel
    is the text colour or it is not. Thresholded at half coverage, which for
    type at these sizes is the difference between crisp and mush.
    """
    w, h, _baseline, rows = cov
    idx = palette.index(colour) if colour in palette else len(palette)
    if idx == len(palette):
        palette.append(colour)
    for ry in range(h):
        ty = y + ry
        if ty < 0 or ty >= len(target):
            continue
        row = rows[ry]
        trow = target[ty]
        for rx in range(w):
            if row[rx] >= 128:
                tx = x + rx
                if 0 <= tx < len(trow):
                    trow[tx] = idx


def draw(target, palette, text, postscript, size, x, y, colour, centre=False):
    """Draw `text` with its BASELINE at `y`; `x` is left edge, or centre."""
    f = face(postscript)
    cov = f.coverage(text, size)
    w, _h, baseline, _rows = cov
    ox = x - w // 2 if centre else x
    blit(target, cov, int(ox), int(y - baseline), colour, palette)
    return f.measure(text, size)


def screen(swatch="36F422", size=560, out_name="screen.png"):
    """The whole thing: timber, the flowing floor, pixel panels, real type.

    This is what all of it is for — every preview so far showed one layer in
    isolation, and the only question that matters is whether they agree with
    each other at the proportions the app actually uses.
    """
    import tools_wood_preview as wood
    import tools_smoke_preview as smoke

    tile = wood.render_tile()
    wood_pal = wood.palette()
    th, tw = len(tile), len(tile[0])

    header = int(size * 0.15 / 0.72)
    footer = int(size * 0.15 / 0.72)
    total = header + size + footer
    rim = max(6, size // 26)

    smoke_pal = smoke.ramp(swatch)
    pal = [tuple(c) for c in wood_pal] + [tuple(c) for c in smoke_pal]
    SMOKE0 = len(wood_pal)
    OUT, SHD, BSE, HIL = 0, 1, 2, 3

    img = [bytearray([BSE]) * size for _ in range(total)]

    tile_w = max(1, int(size * wood.TILE_FRACTION))
    tile_h = max(1, int(tile_w * th / tw))
    for y in range(total):
        for x in range(size):
            img[y][x] = tile[int((y % tile_h) * th / tile_h) % th][
                            int((x % tile_w) * tw / tile_w) % tw]

    # The field, inset by the rim.
    inner = size - 2 * rim
    cells = max(8, inner // 4)
    for cy in range(cells):
        v = (cy + 0.5) / cells
        row = [smoke.tone((cx + 0.5) / cells, v, 0.0, cx, cy) for cx in range(cells)]
        for dy in range(inner * cy // cells, inner * (cy + 1) // cells):
            ty = header + rim + dy
            for dx in range(inner):
                img[ty][rim + dx] = SMOKE0 + row[dx * cells // inner]

    def rect(x0, y0, x1, y1, tone):
        for y in range(max(0, y0), min(total, y1)):
            for x in range(max(0, x0), min(size, x1)):
                img[y][x] = tone

    def panel(x0, y0, x1, y1, fill):
        """A PixelPanel: hard outline, one-step bevel, flat fill, hard shadow."""
        rect(x0 + 2, y0 + 2, x1 + 2, y1 + 2, OUT)        # zero-blur shadow
        rect(x0, y0, x1, y1, OUT)                        # 2px outline
        rect(x0 + 2, y0 + 2, x1 - 2, y1 - 2, fill)
        rect(x0 + 2, y0 + 2, x1 - 2, y0 + 4, HIL)        # lit edge
        rect(x0 + 2, y1 - 4, x1 - 2, y1 - 2, SHD)        # shadowed edge

    # Hard line where the rim meets the field.
    for i in range(rim - 2, rim):
        for x in range(rim - 2, size - rim + 2):
            img[header + i][x] = OUT
            img[header + size - 1 - i][x] = OUT
        for y in range(header + rim - 2, header + size - rim + 2):
            img[y][i] = OUT
            img[y][size - 1 - i] = OUT

    ink = (250, 248, 244)
    dim = (196, 188, 178)

    # --- header: the score panel -------------------------------------
    draw(img, pal, "SCORE", "Poppins-Regular", 13, 22, 34, dim)
    draw(img, pal, "312", "Poppins-Black", 46, 22, 84, ink)

    # Banked-die cells, 8 across, filled then empty.
    cw, ch, gap = 30, 30, 5
    x0 = 150
    for i in range(8):
        x = x0 + i * (cw + gap)
        if x + cw > size - 16:
            break
        if i < 5:
            panel(x, 24, x + cw, 24 + ch, SHD)
            draw(img, pal, str((i * 2) % 6 + 1), "Poppins-SemiBold", 16,
                 x + cw // 2, 24 + ch - 9, ink, centre=True)
        else:
            rect(x, 24, x + cw, 24 + ch, OUT)            # a pixelWell
            rect(x + 2, 24 + 2, x + cw - 2, 24 + ch - 2, BSE)

    # --- the floor wordmark, in Lobster ------------------------------
    draw(img, pal, "Rolls", "Lobster-Regular", int(size * 0.17),
         size // 2, header + size // 2 + int(size * 0.05),
         tuple(smoke_pal[0]), centre=True)

    # --- the two corner buttons --------------------------------------
    for cx, glyph in ((rim + 16, "<"), (size - rim - 46, "=")):
        panel(cx, header + rim + 10, cx + 30, header + rim + 40,
              SMOKE0)                                    # field's darkest tone
        draw(img, pal, glyph, "Poppins-SemiBold", 16,
             cx + 15, header + rim + 32, ink, centre=True)

    # --- footer: the roll button -------------------------------------
    by0 = header + size + 14
    panel(16, by0, size - 16, by0 + 48, SMOKE0 + 2)
    draw(img, pal, "ROLL", "Poppins-Bold", 20, size // 2, by0 + 32, ink,
         centre=True)
    draw(img, pal, "Tap a die to keep it", "Poppins-Regular", 12,
         size // 2, by0 + 68, dim, centre=True)

    p = os.path.join(os.environ.get("TYPE_OUT", "."), out_name)
    wood.write_png(p, img, pal)
    return p


if __name__ == "__main__":
    import sys
    import tools_wood_preview as wood

    out_dir = os.environ.get("TYPE_OUT", ".")

    if "--screen" in sys.argv:
        for swatch, name in (("36F422", "green"), ("7A1F3D", "wine"),
                             ("14140F", "onyx"), ("1E6FFF", "electric")):
            print("wrote", screen(swatch=swatch, out_name="screen-%s.png" % name))
        raise SystemExit

    W, H = 940, 620
    pal = [(24, 20, 18), (240, 236, 230)]
    img = [bytearray([0]) * W for _ in range(H)]

    rows = [
        ("Poppins-Black", 44, "ROLLS"),
        ("Poppins-Bold", 34, "Three Thousand"),
        ("Poppins-SemiBold", 28, "OUTS  1 2 3 4 5 6 7 8 9"),
        ("Poppins-Medium", 22, "Caught at the wall — third out."),
        ("Poppins-Regular", 17, "Changes the playing surface and this menu."),
        ("Poppins-Regular", 11, "Music   Sound Effects   Table Color"),
        ("Lobster-Regular", 54, "Rolls"),
        ("Lobster-Regular", 34, "Excellent"),
    ]
    # Advance by the NEXT row's height, not this one's — stepping by the
    # current size collides whenever a large row follows a small one, which
    # is exactly what the 11pt row followed by 54pt Lobster did.
    y = 60
    for i, (ps, size, text) in enumerate(rows):
        draw(img, pal, text, ps, size, 40, y, (240, 236, 230))
        draw(img, pal, "%s %dpt" % (ps.replace("-", " "), size),
             "Poppins-Regular", 11, W - 230, y, (150, 145, 138))
        nxt = rows[i + 1][1] if i + 1 < len(rows) else size
        y += int(size * 0.35) + int(nxt * 1.0) + 14

    wood.write_png(os.path.join(out_dir, "type-specimen.png"), img, pal)
    print("wrote type-specimen.png")
