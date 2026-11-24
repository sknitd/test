#!/usr/bin/env python3
"""Draws the WidgetForge app icon (a 2x2 widget grid on a blue-violet squircle) at every macOS size.
Requires Pillow. Output: Resources/Assets.xcassets/AppIcon.appiconset"""
import json, os, sys
from PIL import Image, ImageDraw

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources", "Assets.xcassets")
out = os.path.join(root, "AppIcon.appiconset")
os.makedirs(out, exist_ok=True)

def render(size):
    scale = 4
    s = size * scale
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    grad = Image.new("RGBA", (s, s))
    px = grad.load()
    for y in range(s):
        t = y / max(1, s - 1)
        r, g, b = int(72 + (124 - 72) * t), int(118 + (58 - 118) * t), int(255 + (237 - 255) * t)
        for x in range(s):
            px[x, y] = (r, g, b, 255)
    mask = Image.new("L", (s, s), 0)
    margin = int(s * 0.1)
    ImageDraw.Draw(mask).rounded_rectangle([margin, margin, s - margin, s - margin], radius=int(s * 0.185), fill=255)
    img.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(img)
    inner0, inner1 = int(s * 0.27), int(s * 0.73)
    gap = int(s * 0.045)
    mid = (inner0 + inner1) // 2
    rad = int(s * 0.05)
    tiles = [((inner0, inner0, mid - gap // 2, mid - gap // 2), 245), ((mid + gap // 2, inner0, inner1, mid - gap // 2), 200),
             ((inner0, mid + gap // 2, mid - gap // 2, inner1), 200), ((mid + gap // 2, mid + gap // 2, inner1, inner1), 150)]
    for box, alpha in tiles:
        d.rounded_rectangle(box, radius=rad, fill=(255, 255, 255, alpha))
    return img.resize((size, size), Image.LANCZOS)

images = []
for points in (16, 32, 128, 256, 512):
    for factor in (1, 2):
        pixels = points * factor
        name = f"icon_{points}x{points}{'@2x' if factor == 2 else ''}.png"
        render(pixels).save(os.path.join(out, name))
        images.append({"idiom": "mac", "size": f"{points}x{points}", "scale": f"{factor}x", "filename": name})
with open(os.path.join(out, "Contents.json"), "w") as f:
    json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
with open(os.path.join(root, "Contents.json"), "w") as f:
    json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
accent = os.path.join(root, "AccentColor.colorset")
os.makedirs(accent, exist_ok=True)
with open(os.path.join(accent, "Contents.json"), "w") as f:
    json.dump({"colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": {"red": "0.345", "green": "0.396", "blue": "0.965", "alpha": "1.000"}}}],
               "info": {"author": "xcode", "version": 1}}, f, indent=2)
print("wrote", len(images), "icons")
