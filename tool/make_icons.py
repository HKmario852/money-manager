"""Draws the app icon (the lime savings mark on a dark circle, same as docs/assets/logo.svg)
into the Android and iOS launcher icon PNGs.

    pip install pillow
    python tool/make_icons.py
"""
import re
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
INK = (0x13, 0x14, 0x17, 255)
LIME = (0xC8, 0xF1, 0x69, 255)

# Material Icons "savings" (outlined, Apache-2.0), font units: 512 per em, y up.
# Keep in sync with docs/assets/logo.svg and android/.../drawable/ic_launcher_foreground.xml.
GLYPH = (
    "M320 299C320 310 330 320 341 320C353 320 363 310 363 299C363 287 353 277 341 277C330 277 320 287 320 299Z"
    "M171 320H277V363H171V320Z"
    "M469 352V203L409 183L373 64H256V107H213V64H96C96 64 43 244 43 309C43 374 95 427 160 427H267C286 452 317 469 352 469"
    "C370 469 384 455 384 437C384 433 383 429 381 425C378 418 376 409 375 400L423 352H469Z"
    "M427 309H405L331 384C331 398 333 412 336 425C316 419 299 404 292 384H160C119 384 85 351 85 309C85 269 111 167 128 107"
    "H171V149H299V107H342L375 217L427 234V309Z"
)


def contours(path):
    """Splits the path into closed polygons, flattening cubic curves."""
    out, pts, x, y = [], [], 0.0, 0.0
    tokens = re.findall(r"[MCLHVZ]|-?\d+(?:\.\d+)?", path)
    i, cmd = 0, None
    while i < len(tokens):
        if tokens[i].isalpha():
            cmd = tokens[i]
            i += 1
            if cmd == "Z":
                out.append(pts)
                pts = []
                continue
        n = lambda k: float(tokens[i + k])  # noqa: E731
        if cmd == "M" or cmd == "L":
            x, y = n(0), n(1)
            pts.append((x, y))
            i += 2
        elif cmd == "H":
            x = n(0)
            pts.append((x, y))
            i += 1
        elif cmd == "V":
            y = n(0)
            pts.append((x, y))
            i += 1
        elif cmd == "C":
            x1, y1, x2, y2, x3, y3 = (n(k) for k in range(6))
            for s in range(1, 17):
                t = s / 16
                a, b, c, d = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t**2, t**3
                pts.append((a * x + b * x1 + c * x2 + d * x3, a * y + b * y1 + c * y2 + d * y3))
            x, y = x3, y3
            i += 6
    return out


def draw(size, round_shape):
    """Icon at `size` px: dark circle (or full square for iOS) with the glyph at half the width."""
    big = size * 8
    bg = Image.new("L", (big, big), 0)
    if round_shape:
        ImageDraw.Draw(bg).ellipse((0, 0, big - 1, big - 1), fill=255)
    else:
        bg.paste(255, (0, 0, big, big))

    em, left, top = big / 2, big / 4, big / 4
    mark = Image.new("L", (big, big), 0)
    for poly in contours(GLYPH):
        layer = Image.new("L", (big, big), 0)
        pts = [(left + px / 512 * em, top + (512 - py) / 512 * em) for px, py in poly]
        ImageDraw.Draw(layer).polygon(pts, fill=255)
        mark = ImageChops.logical_xor(mark.convert("1"), layer.convert("1")).convert("L")  # even-odd: holes

    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    img.paste(Image.new("RGBA", (big, big), INK), mask=bg)
    img.paste(Image.new("RGBA", (big, big), LIME), mask=mark)
    img = img.resize((size, size), Image.LANCZOS)
    return img if round_shape else img.convert("RGB")  # iOS icons must not have alpha


ANDROID = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
IOS = {"20x20@1x": 20, "20x20@2x": 40, "20x20@3x": 60, "29x29@1x": 29, "29x29@2x": 58, "29x29@3x": 87,
       "40x40@1x": 40, "40x40@2x": 80, "40x40@3x": 120, "60x60@2x": 120, "60x60@3x": 180,
       "76x76@1x": 76, "76x76@2x": 152, "83.5x83.5@2x": 167, "1024x1024@1x": 1024}

for name, px in ANDROID.items():
    draw(px, True).save(ROOT / f"android/app/src/main/res/mipmap-{name}/ic_launcher.png", optimize=True)
for name, px in IOS.items():
    draw(px, False).save(ROOT / f"ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-{name}.png", optimize=True)
print(f"wrote {len(ANDROID)} Android and {len(IOS)} iOS icons")
