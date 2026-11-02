#!/usr/bin/env python3
"""Generate true Pocket God Comics Android launcher icons from the recovered iVerse PNG."""
from pathlib import Path
import sys

from PIL import Image

if len(sys.argv) != 2:
    raise SystemExit("Usage: create_launcher_icons.py /path/to/original/icon@2x.png")

source = Path(sys.argv[1])
if not source.is_file():
    raise SystemExit(f"Missing recovered Pocket God Comics app icon: {source}")

res = Path(__file__).resolve().parent.parent / "app" / "src" / "main" / "res"
densities = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}

with Image.open(source) as im:
    im.load()
    if im.width < 64 or im.height < 64:
        raise SystemExit(f"Recovered app icon is too small: {im.size}")
    rgba = im.convert("RGBA")
    for name, pixels in densities.items():
        target = res / f"mipmap-{name}" / "ic_launcher.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        rgba.resize((pixels, pixels), Image.Resampling.LANCZOS).save(target, format="PNG", optimize=True)
        assert target.stat().st_size > 200, target
        print(f"Generated original iVerse launcher icon: {target} ({pixels}x{pixels})")

print("Successfully installed the original Pocket God Comics art as Android's launcher icon.")
