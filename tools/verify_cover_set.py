#!/usr/bin/env python3
"""Validate a set of locally owned cover images named 026.png through 063.png.

No cover files are downloaded or uploaded. Requires Pillow; see requirements-dev.txt.
"""
from __future__ import annotations
import argparse
import hashlib
from pathlib import Path
import sys
from PIL import Image, UnidentifiedImageError

SUPPORTED = {".png", ".jpg", ".jpeg", ".webp"}

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path, help="Directory containing numbered covers")
    parser.add_argument("--start", type=int, default=26)
    parser.add_argument("--end", type=int, default=63)
    parser.add_argument("--min-width", type=int, default=720)
    parser.add_argument("--min-height", type=int, default=1000)
    parser.add_argument("--strict-size", action="store_true",
                        help="Require generated 1024x1536 portrait image dimensions")
    args = parser.parse_args()
    if not args.directory.is_dir() or args.start < 1 or args.start > args.end:
        parser.error("Provide a real cover directory and valid issue range")
    ok = True
    unique_hashes = {}
    for n in range(args.start, args.end + 1):
        found = [args.directory / f"{n:03d}{ext}" for ext in sorted(SUPPORTED)
                 if (args.directory / f"{n:03d}{ext}").is_file()]
        if len(found) != 1:
            print(f"FAIL {n:03d} expected one numbered image, found {len(found)}", file=sys.stderr)
            ok = False
            continue
        path = found[0]
        try:
            with Image.open(path) as image:
                image.verify()
            with Image.open(path) as image:
                width, height = image.size
                if width < args.min_width or height < args.min_height or width >= height:
                    raise ValueError(f"bad portrait dimensions {width}x{height}")
                if args.strict_size and (width, height) != (1024, 1536):
                    raise ValueError(f"expected 1024x1536, got {width}x{height}")
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            if digest in unique_hashes:
                raise ValueError(f"identical image already used for issue {unique_hashes[digest]}")
            unique_hashes[digest] = n
            print(f"OK {n:03d} {width}x{height} sha256={digest[:16]}…")
        except (OSError, UnidentifiedImageError, ValueError) as exc:
            print(f"FAIL {n:03d} {exc}", file=sys.stderr)
            ok = False
    if ok:
        print(f"PASS {args.end - args.start + 1} unique numbered covers")
    return 0 if ok else 1

if __name__ == "__main__":
    raise SystemExit(main())
