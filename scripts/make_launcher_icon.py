"""Rebuild the launcher-icon source assets from the SafeHer lock-up.

    python scripts/make_launcher_icon.py
    cd mobile && dart run flutter_launcher_icons

Run this after replacing SafeHer_logo.png. It writes mobile/assets/branding/
icon.png and icon_foreground.png; flutter_launcher_icons then fans those out to
every Android density and iOS size.

Only the mark is used, never the full lock-up: at a 48dp launcher size the
"SafeHer" wordmark renders as illegible mush, which reads as a broken image
rather than a brand.

The constants below are measured against the current lock-up. A new logo with a
different layout needs CROP re-measured -- the printout at the end reports the
mark size and corner radius it found, which is the quickest way to tell whether
it latched onto the right thing.
"""

import math
from collections import deque
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "SafeHer_logo.png"
BRANDING = ROOT / "mobile" / "assets" / "branding"
CANVAS = 1024

# The mark, measured off the lock-up: it sits above y=690 and the wordmark
# below. Generous margins -- everything outside the artwork is paper, and the
# flood fill finds the real edges from here.
CROP = (200, 180, 800, 690)

# The lock-up's paper is a soft grey vignette (227-252), not white. Lift it to
# true white so the asset sits seamlessly on the #FFFFFF adaptive background,
# leaving everything below the knee -- the gold, the charcoal, the glow -- alone.
KNEE, WHITE_POINT = 200, 224

# The mark's own body, excluding its soft drop shadow. The shadow rides along in
# the artwork but must not drive centring or sizing, or the icon comes out
# shoved up-right and smaller than it needs to be.
SOLID = 150

# Android insets the adaptive foreground by 16%, scaling it to 68% of the canvas
# before the launcher's mask applies. Keeping the farthest ink at 0.315 of the
# canvas puts it past the 0.305 guaranteed safe zone but inside the 0.333 circle
# the mask actually cuts -- which is where the previously shipped icon sat.
INSET_SCALE = 0.68
TARGET_RADIUS = 0.315

# The legacy icon has no adaptive mask to dodge, so it is sized to look right
# beside other icons rather than to survive a circle.
LEGACY_WIDTH = 0.80


def whiten_paper(img):
    """Scale near-white pixels up to white, preserving hue.

    The gain comes from the pixel's darkest channel and is applied to all three,
    so gold highlights brighten without shifting colour.

    Cutting the paper out instead -- a flood fill to transparency -- was tried
    first and left a ragged cream halo around the mark: the glow around the
    pulse line and the drop shadow are both warm and light, so no threshold
    separates them from paper cleanly. Lifting the paper sidesteps the question,
    because the icon's background is white either way.
    """
    px = img.load()
    ceiling = 255 / WHITE_POINT
    for y in range(img.height):
        for x in range(img.width):
            r, g, b = px[x, y]
            m = min(r, g, b)
            if m < KNEE:
                continue
            target = min(255, KNEE + (m - KNEE) * (255 - KNEE) / (WHITE_POINT - KNEE))
            k = min(ceiling, target / m)
            px[x, y] = (
                min(255, round(r * k)),
                min(255, round(g * k)),
                min(255, round(b * k)),
            )
    return img


def solid_box(img):
    """Bounding box of the mark's body, shadow excluded."""
    px = img.load()
    xs, ys = [], []
    for y in range(img.height):
        for x in range(img.width):
            if min(px[x, y]) < SOLID:
                xs.append(x)
                ys.append(y)
    if not xs:
        raise SystemExit("no mark found in CROP -- re-measure it against the logo")
    return min(xs), min(ys), max(xs) + 1, max(ys) + 1


def corner_radius(img, box):
    """Farthest solid pixel from the mark's centre, as a fraction of half-width.

    This is what decides how large the adaptive foreground may be. The current
    mark is a triangle whose base corners are solid mass sitting right at the
    bbox corners, so it cannot be sized by bounding box the way a tapering
    shield can be -- that would push them under the launcher's circular mask.
    """
    px = img.load()
    cx, cy = (box[0] + box[2] - 1) / 2, (box[1] + box[3] - 1) / 2
    best = 0.0
    for y in range(box[1], box[3]):
        for x in range(box[0], box[2]):
            if min(px[x, y]) < SOLID:
                best = max(best, math.hypot(x - cx, y - cy))
    return best / ((box[2] - box[0]) / 2)


def ink_box(img):
    """Bounding box of everything a flood fill from the border cannot reach.

    Flooding rather than thresholding because the glow inside the mark is
    near-white too, and a global test would punch holes in it.
    """
    w, h = img.size
    px = img.load()
    paper = bytearray(w * h)
    queue = deque()
    for x in range(w):
        queue += [(x, 0), (x, h - 1)]
    for y in range(h):
        queue += [(0, y), (w - 1, y)]
    while queue:
        x, y = queue.popleft()
        i = y * w + x
        if paper[i] or px[x, y] != (255, 255, 255):
            continue
        paper[i] = 1
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and not paper[ny * w + nx]:
                queue.append((nx, ny))
    return Image.frombytes("L", (w, h), bytes(255 - v * 255 for v in paper)).getbbox()


def framed(img, solid, ink):
    """Crop symmetrically around the mark, wide enough to hold its shadow.

    Symmetric because the crop is what gets centred on the canvas: cropping to
    the ink bbox instead would let the shadow, which falls to one side, shove
    the mark off-centre.
    """
    cx, cy = (solid[0] + solid[2]) / 2, (solid[1] + solid[3]) / 2
    dx = round(max(cx - ink[0], ink[2] - cx))
    dy = round(max(cy - ink[1], ink[3] - cy))
    # Paste onto white rather than crop() past the edge -- crop() pads with
    # black, which drew a hard black rule along the top and right of the icon.
    frame = Image.new("RGB", (dx * 2, dy * 2), (255, 255, 255))
    frame.paste(img, (dx - round(cx), dy - round(cy)))
    return frame


def place(frame, mark_width, width_fraction):
    """Scale so the mark -- not the frame -- occupies width_fraction of the canvas."""
    scale = (CANVAS * width_fraction) / mark_width
    size = (round(frame.width * scale), round(frame.height * scale))
    # resize(), never thumbnail() -- thumbnail only ever shrinks, so a mark
    # smaller than the canvas comes out untouched and tiny.
    scaled = frame.resize(size, Image.LANCZOS)
    canvas = Image.new("RGB", (CANVAS, CANVAS), (255, 255, 255))
    canvas.paste(scaled, ((CANVAS - size[0]) // 2, (CANVAS - size[1]) // 2))
    return canvas


def main():
    page = whiten_paper(Image.open(SRC).convert("RGB").crop(CROP))
    solid = solid_box(page)
    radius = corner_radius(page, solid)
    frame = framed(page, solid, ink_box(page))
    mark_width = solid[2] - solid[0]
    print(
        f"mark {mark_width}x{solid[3] - solid[1]}"
        f"  frame {frame.width}x{frame.height}"
        f"  corner radius {radius:.3f} x half-width"
    )

    foreground = (2 * TARGET_RADIUS / radius) / INSET_SCALE
    print(f"foreground {foreground:.1%} of canvas -> {foreground * INSET_SCALE:.1%} visible")

    place(frame, mark_width, foreground).save(BRANDING / "icon_foreground.png")
    place(frame, mark_width, LEGACY_WIDTH).save(BRANDING / "icon.png")
    print(f"written to {BRANDING}")


if __name__ == "__main__":
    main()
