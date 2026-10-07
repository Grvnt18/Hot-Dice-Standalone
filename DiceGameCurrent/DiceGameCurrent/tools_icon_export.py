"""Builds every app-icon slot from the master artwork.

Why this is a tool and not a folder of PNGs
-------------------------------------------
The icons are derived, not authored: one master at 1024 produces sixteen
files, and every one of them has to be rebuilt the moment the master
changes. A folder of exported PNGs is a set of copies that silently stop
matching their source — the same failure as a number typed into prose.

Three things the export has to get right, none of them obvious:

  * **No alpha.** iOS masks app icons itself. An icon carrying an alpha
    channel does not look wrong, it fails App Store validation.

  * **No rounded corners.** The master has them, and iOS adds its own, so
    shipping the master as-is rounds it twice.

  * **No bevel.** This is the one that cost two attempts. The master's edge
    highlight reaches 73px in at 1024 — well past the corner arc, which is
    only ~54px. Cropping to clear the arc leaves the highlight behind,
    where it reads as a rounded outline ghosted onto a square icon, and as
    notches in the corners once rows are extended sideways for the
    Messages shapes. The crop is sized to the measured depth instead.

The Messages slots are landscape and the artwork is square. The background
is a vertical gradient with no horizontal variation at all, so each row of
the wider canvas is filled with that row's own edge colour: the extension
is exact rather than approximated, and there is no seam to see.

    python3 tools_icon_export.py [outdir]

Dark and Clear masters are deliberately not exported. Dark, tinted and
clear app icons are an iOS 18 feature read by Xcode 16; this project is
pinned to Xcode 14.2 and the iOS 16 SDK (see PLATFORM.txt), whose asset
catalogs have no slot to put them in. They are kept in Icons/ for the day
that changes.
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
MASTER = os.path.join(HERE, "Icons", "Master icon Default.png")

# The flat background green, used only to back the master's own
# anti-aliased edge pixels where they are partly transparent.
BACKDROP = (50, 165, 50)

# Every slot Xcode's catalogs ask for, in pixels.
APP_ICON = ("AppIcon-1024", 1024, 1024)
LADDER = [
    ("iMessage-AppStore-1024x768", 1024, 768),
    ("iMessage-27x20@1x",   27,  20), ("iMessage-27x20@2x",  54,  40),
    ("iMessage-27x20@3x",   81,  60), ("iMessage-32x24@1x",  32,  24),
    ("iMessage-32x24@2x",   64,  48), ("iMessage-32x24@3x",  96,  72),
    ("Settings-29x29@1x",   29,  29), ("Settings-29x29@2x",  58,  58),
    ("Settings-29x29@3x",   87,  87), ("iMessage-60x45@2x", 120,  90),
    ("iMessage-60x45@3x",  180, 135), ("iMessage-67x50@1x",  67,  50),
    ("iMessage-67x50@2x",  134, 100), ("iMessage-74x55@2x", 148, 110),
]


def bevel_depth(master, threshold=185):
    """How far the edge highlight reaches in, measured rather than assumed.

    The background sits near G=165-172 and the bevel is brighter than both,
    so the deepest bright pixel from any edge is the crop this needs.
    """
    px = master.load()
    width, height = master.size
    deepest = 0
    for y in range(height):
        for x in range(width):
            red, green, blue, alpha = px[x, y]
            if alpha > 200 and green > threshold:
                deepest = max(deepest,
                              min(x, y, width - 1 - x, height - 1 - y))
    return deepest


def squared(master):
    """The master as a flat, opaque square with the bevel cropped away."""
    inset = bevel_depth(master) + 11
    width, height = master.size
    inner = master.crop((inset, inset, width - inset, height - inset))
    flat = Image.new("RGB", inner.size, BACKDROP)
    flat.paste(inner, (0, 0), inner)
    return flat.resize((1024, 1024), Image.LANCZOS), inset


def shaped(square, width, height):
    """The square artwork on a canvas of another shape."""
    art = square.resize((height, height), Image.LANCZOS)
    if width == height:
        return art
    canvas = Image.new("RGB", (width, height))
    source, target = art.load(), canvas.load()
    for y in range(height):
        edge = source[0, y]
        for x in range(width):
            target[x, y] = edge
    canvas.paste(art, ((width - height) // 2, 0))
    return canvas


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "Icons", "export")
    os.makedirs(outdir, exist_ok=True)

    master = Image.open(MASTER).convert("RGBA")
    square, inset = squared(master)
    print("master %s, bevel cropped at %dpx" % (master.size, inset))

    name, width, height = APP_ICON
    square.save(os.path.join(outdir, name + ".png"), "PNG")
    print("  %-30s %4d x %-4d %s" % (name, width, height, square.mode))

    for name, width, height in LADDER:
        image = shaped(square, width, height)
        assert image.size == (width, height), (name, image.size)
        assert image.mode == "RGB", (name, image.mode)
        image.save(os.path.join(outdir, name + ".png"), "PNG")
        print("  %-30s %4d x %-4d %s" % (name, width, height, image.mode))

    print("icons: %d slots written to %s, none carrying alpha"
          % (len(LADDER) + 1, outdir))


if __name__ == "__main__":
    main()
