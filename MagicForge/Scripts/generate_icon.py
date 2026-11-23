#!/usr/bin/env python3
"""Generates the MagicForge app icon, accent colour and .icns.

Outputs (relative to the package root):
  Resources/Assets.xcassets/Contents.json
  Resources/Assets.xcassets/AppIcon.appiconset/{Contents.json,icon_*.png}
  Resources/Assets.xcassets/AccentColor.colorset/Contents.json
  Resources/AppIcon.icns

Requires Pillow (`python3 -m pip install Pillow`). The artwork is drawn as vectors at
4x supersampling and downscaled, so re-running the script reproduces the same icon.

Usage: python3 Scripts/generate_icon.py [--check]
  --check  only verify that every expected file exists with the right pixel size.
"""
from __future__ import annotations

import json
import math
import struct
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Resources" / "Assets.xcassets"
ICONSET = ASSETS / "AppIcon.appiconset"
ACCENT = ASSETS / "AccentColor.colorset"
ICNS = ROOT / "Resources" / "AppIcon.icns"

# (point size, scale) pairs required for a macOS app icon.
SLOTS = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
# icns chunk type per pixel size (PNG payloads).
ICNS_TYPES = [(16, b"icp4"), (32, b"icp5"), (64, b"icp6"), (128, b"ic07"), (256, b"ic08"),
              (512, b"ic09"), (1024, b"ic10"), (32, b"ic11"), (64, b"ic12"), (256, b"ic13"), (512, b"ic14")]

CANVAS = 1024
SS = 4  # supersampling factor

TOP = (124, 92, 255)      # violet
BOTTOM = (38, 198, 218)   # cyan
ACCENT_LIGHT = (108, 76, 240)
ACCENT_DARK = (150, 128, 255)
SPARK = (255, 214, 102)


def file_name(points: int, scale: int) -> str:
    return f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"


def gradient(size: int) -> Image.Image:
    """Diagonal top-left -> bottom-right gradient."""
    ramp = Image.linear_gradient("L").resize((size * 2, size * 2)).rotate(-35, resample=Image.BICUBIC)
    left = (ramp.width - size) // 2
    ramp = ramp.crop((left, left, left + size, left + size))
    top = Image.new("RGB", (size, size), TOP)
    bottom = Image.new("RGB", (size, size), BOTTOM)
    return Image.composite(bottom, top, ramp)


def star(cx: float, cy: float, outer: float, inner: float, points: int = 4, rotation: float = 0.0):
    pts = []
    for i in range(points * 2):
        radius = outer if i % 2 == 0 else inner
        angle = rotation + math.pi * i / points - math.pi / 2
        pts.append((cx + radius * math.cos(angle), cy + radius * math.sin(angle)))
    return pts


def draw_master() -> Image.Image:
    s = CANVAS * SS
    u = s / 1024.0  # one 1024-grid unit in supersampled pixels

    # macOS icon grid: 824x824 rounded rect centred in the 1024 canvas, radius ~185.
    inset, radius = 100 * u, 185 * u
    plate_box = (inset, inset, s - inset, s - inset)
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle(plate_box, radius=radius, fill=255)

    icon = Image.new("RGBA", (s, s), (0, 0, 0, 0))

    # Soft drop shadow under the plate.
    shadow = Image.new("L", (s, s), 0)
    ImageDraw.Draw(shadow).rounded_rectangle(
        (inset, inset + 12 * u, s - inset, s - inset + 12 * u), radius=radius, fill=110)
    shadow = shadow.filter(ImageFilter.GaussianBlur(14 * u))
    icon.paste(Image.new("RGBA", (s, s), (0, 0, 0, 255)), (0, 0), shadow)

    plate = gradient(s).convert("RGBA")
    # Subtle top highlight.
    glow = Image.new("L", (s, s), 0)
    ImageDraw.Draw(glow).ellipse((120 * u, -260 * u, 904 * u, 420 * u), fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(60 * u))
    plate = Image.composite(Image.new("RGBA", (s, s), (255, 255, 255, 255)), plate, glow)
    icon.paste(plate, (0, 0), mask)

    # Mouse silhouette: tall capsule, slightly rotated.
    layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    body = (372 * u, 300 * u, 652 * u, 800 * u)
    body_shadow = Image.new("L", (s, s), 0)
    ImageDraw.Draw(body_shadow).rounded_rectangle(
        (body[0], body[1] + 18 * u, body[2], body[3] + 18 * u), radius=140 * u, fill=120)
    body_shadow = body_shadow.filter(ImageFilter.GaussianBlur(16 * u))
    layer.paste(Image.new("RGBA", (s, s), (20, 16, 60, 255)), (0, 0), body_shadow)
    d.rounded_rectangle(body, radius=140 * u, fill=(255, 255, 255, 255))
    # Touch-surface hint: a short swipe stroke with a finger contact at its head.
    d.rounded_rectangle((500 * u, 372 * u, 524 * u, 500 * u), radius=12 * u, fill=(124, 92, 255, 110))
    d.ellipse((484 * u, 352 * u, 540 * u, 408 * u), fill=(124, 92, 255, 230))
    layer = layer.rotate(-14, resample=Image.BICUBIC, center=(512 * u, 550 * u))

    # Gesture arc sweeping over the mouse, ending in a spark.
    arc_box = (236 * u, 196 * u, 836 * u, 796 * u)
    d = ImageDraw.Draw(layer)
    d.arc(arc_box, start=215, end=318, fill=(255, 255, 255, 235), width=int(26 * u))
    for angle in (215, 318):  # round caps
        r = 300 * u
        cx = 536 * u + r * math.cos(math.radians(angle))
        cy = 496 * u + r * math.sin(math.radians(angle))
        if angle == 215:
            d.ellipse((cx - 13 * u, cy - 13 * u, cx + 13 * u, cy + 13 * u), fill=(255, 255, 255, 235))
        else:
            d.polygon(star(cx, cy, 86 * u, 26 * u, rotation=math.radians(8)), fill=SPARK + (255,))
            d.polygon(star(cx + 92 * u, cy - 78 * u, 34 * u, 11 * u), fill=(255, 255, 255, 240))
            d.polygon(star(cx - 96 * u, cy - 70 * u, 24 * u, 8 * u), fill=(255, 255, 255, 220))

    # Keep artwork inside the plate.
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
    icon = Image.alpha_composite(icon, layer)
    return icon.resize((CANVAS, CANVAS), Image.LANCZOS)


def render(master: Image.Image, pixels: int) -> Image.Image:
    if pixels == master.width:
        return master.copy()
    image = master.resize((pixels, pixels), Image.LANCZOS)
    if pixels <= 64:  # small sizes benefit from a touch of sharpening
        image = image.filter(ImageFilter.UnsharpMask(radius=0.6, percent=60, threshold=0))
    return image


def png_bytes(image: Image.Image) -> bytes:
    import io
    buffer = io.BytesIO()
    image.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def write_icns(master: Image.Image) -> None:
    """Writes the icns container by hand: 'icns' + total length, then typed PNG chunks."""
    cache: dict[int, bytes] = {}
    chunks = b""
    for pixels, kind in ICNS_TYPES:
        data = cache.setdefault(pixels, png_bytes(render(master, pixels)))
        chunks += kind + struct.pack(">I", len(data) + 8) + data
    ICNS.write_bytes(b"icns" + struct.pack(">I", len(chunks) + 8) + chunks)


def colour(rgb: tuple[int, int, int]) -> dict:
    r, g, b = (f"0x{c:02X}" for c in rgb)
    return {"color-space": "srgb", "components": {"alpha": "1.000", "red": r, "green": g, "blue": b}}


def write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2) + "\n")


def generate() -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)
    ACCENT.mkdir(parents=True, exist_ok=True)
    master = draw_master()
    images = []
    for points, scale in SLOTS:
        name = file_name(points, scale)
        render(master, points * scale).save(ICONSET / name, format="PNG", optimize=True)
        images.append({"idiom": "mac", "size": f"{points}x{points}", "scale": f"{scale}x", "filename": name})
    info = {"author": "xcode", "version": 1}
    write_json(ICONSET / "Contents.json", {"images": images, "info": info})
    write_json(ASSETS / "Contents.json", {"info": info})
    write_json(ACCENT / "Contents.json", {
        "colors": [
            {"idiom": "universal", "color": colour(ACCENT_LIGHT)},
            {"idiom": "universal", "color": colour(ACCENT_DARK),
             "appearances": [{"appearance": "luminosity", "value": "dark"}]},
        ],
        "info": info,
    })
    write_icns(master)


def check() -> int:
    problems = []
    for points, scale in SLOTS:
        path = ICONSET / file_name(points, scale)
        expected = points * scale
        if not path.exists():
            problems.append(f"missing {path}")
            continue
        with Image.open(path) as image:
            if image.size != (expected, expected) or image.mode != "RGBA":
                problems.append(f"{path.name}: {image.size} {image.mode}, expected {expected}px RGBA")
    listed = {entry["filename"] for entry in json.loads((ICONSET / "Contents.json").read_text())["images"]}
    on_disk = {p.name for p in ICONSET.glob("*.png")}
    if listed != on_disk:
        problems.append(f"Contents.json and PNG files differ: {sorted(listed ^ on_disk)}")
    json.loads((ACCENT / "Contents.json").read_text())
    json.loads((ASSETS / "Contents.json").read_text())

    data = ICNS.read_bytes() if ICNS.exists() else b""
    if data[:4] != b"icns" or struct.unpack(">I", data[4:8])[0] != len(data):
        problems.append("AppIcon.icns: bad header or length")
    else:
        offset, expected_sizes = 8, dict((kind, px) for px, kind in ICNS_TYPES)
        seen = set()
        while offset < len(data):
            kind, length = data[offset:offset + 4], struct.unpack(">I", data[offset + 4:offset + 8])[0]
            payload = data[offset + 8:offset + length]
            width, height = struct.unpack(">II", payload[16:24])  # PNG IHDR
            if payload[:8] != b"\x89PNG\r\n\x1a\n" or width != expected_sizes.get(kind) or width != height:
                problems.append(f"icns chunk {kind!r}: unexpected payload ({width}x{height})")
            seen.add(kind)
            offset += length
        if seen != set(expected_sizes):
            problems.append(f"icns chunks missing: {sorted(set(expected_sizes) - seen)}")
    for problem in problems:
        print(f"FAIL {problem}")
    if not problems:
        print(f"OK {len(SLOTS)} icon PNGs, AccentColor, AppIcon.icns ({len(data)} bytes, {len(ICNS_TYPES)} chunks)")
    return 1 if problems else 0


if __name__ == "__main__":
    if "--check" in sys.argv[1:]:
        sys.exit(check())
    generate()
    sys.exit(check())
