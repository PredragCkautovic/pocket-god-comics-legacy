#!/usr/bin/env python3
"""Build an ARM64 offline Pocket God Comics test IPA from authorized legacy v17 media.

This is a separate *test build*, not a replacement for the approved 32-bit
legacy release. Runs on a macOS GitHub Actions runner with Xcode installed.
"""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import urllib.request
import zipfile

from PIL import Image

REPO = Path(__file__).resolve().parent
BUILD = REPO / "build"
ARTIFACT = BUILD / "Pocket_God_Comics_Modern_3.0.0_RC1_TEST.ipa"
LEGACY_URL = (
    "https://github.com/PredragCkautovic/pocket-god-comics-legacy"
    "/releases/download/legacy-v17/Pocket_God_Comics_Legacy.ipa"
)
LEGACY = BUILD / "Pocket_God_Comics_Legacy.ipa"


def run(*args):
    print("+", " ".join(str(x) for x in args), flush=True)
    subprocess.run(list(map(str, args)), check=True)


def add_bytes(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def main():
    BUILD.mkdir(exist_ok=True)
    if not LEGACY.exists():
        print("Downloading the owner-authorized, publicly released legacy asset set", flush=True)
        urllib.request.urlretrieve(LEGACY_URL, LEGACY)
    if LEGACY.stat().st_size < 10_000_000:
        raise RuntimeError("Legacy IPA download was incomplete")

    with zipfile.ZipFile(LEGACY) as legacy:
        names = set(legacy.namelist())
        manifest_candidates = [n for n in names if n.endswith("/PGOffline/manifest.json")]
        if len(manifest_candidates) != 1:
            raise ValueError(f"Expected one original 25-issue manifest: {manifest_candidates}")
        prefix = manifest_candidates[0][:-len("PGOffline/manifest.json")]
        manifest = json.loads(legacy.read(prefix + "PGOffline/manifest.json"))
        issues = manifest["episodes"]
        if len(issues) != 25:
            raise ValueError("The authorized source is missing issues")

        package = BUILD / "Payload" / "PocketGodComics.app"
        if package.exists():
            shutil.rmtree(package)
        web = package / "web"
        originals = web / "assets" / "ipa_original"
        originals.mkdir(parents=True)
        catalog = []

        print("Extracting source iVerse graphics", flush=True)
        # Preserve original artwork under a generated resource bundle, no binary relinking.
        for name in sorted(names):
            if not name.startswith(prefix):
                continue
            relative = name[len(prefix):]
            if not relative or "/" in relative or not relative.lower().endswith(".png"):
                continue
            add_bytes(originals / relative, legacy.read(name))

        required = [
            "Default@2x.png", "shelf_bg@2x.png", "shelfBlueiPad@2x.png",
            "drawer_bg@2x.png", "blue_button.png",
            "my_comics@2x.png", "list_icon@2x.png", "downloads.png",
            "settings@2x.png", "bookmark@2x.png",
            "single_page_spread_white@2x.png", "two_page_spread_white@2x.png",
        ]
        for name in required:
            if not (originals / name).exists():
                raise RuntimeError(f"Missing original iVerse graphic: {name}")

        # iVerse stores some PNGs as Apple's non-standard CgBI images.
        # Normalize with Xcode's original pngcrush before using Pillow or UIKit.
        converted = 0
        for png in sorted(originals.glob("*.png")):
            if b"CgBI" in png.read_bytes()[:64]:
                temporary = png.with_name(png.stem + "-normalized.png")
                run("xcrun", "-sdk", "iphoneos", "pngcrush",
                    "-revert-iphone-optimizations", "-q", png, temporary)
                if not temporary.is_file():
                    raise RuntimeError(f"Unable to normalize legacy image: {png.name}")
                temporary.replace(png)
                converted += 1
        print(f"Normalized {converted} iPhone-optimized PNG files", flush=True)

        shelf = Image.open(originals / "shelf_bg@2x.png").convert("RGBA")
        if shelf.size[0] < 640 or shelf.size[1] < 736:
            raise ValueError(f"Unexpected original shelf sprite size: {shelf.size}")
        for orientation, w, h in [
            ("ipad_portrait", 768, 355),
            ("ipad_landscape", 1024, 315),
            ("phone", 375, 206),
        ]:
            for part in range(2):
                section = shelf.crop((0, part*368, 640, (part+1)*368))
                section = section.resize((w*2, h*2), Image.Resampling.LANCZOS)
                section.save(originals / f"native_shelf_{orientation}_{part}.png", optimize=True)
        default = Image.open(originals / "Default@2x.png").convert("RGBA")
        default.crop((0, 118, 640, 378)).save(originals / "native_header_logo.png")

        thumbs = web / "assets" / "native_thumbs"
        thumbs.mkdir(parents=True)
        expected_images = {}
        for number, issue in enumerate(issues, 1):
            folder = f"PGOffline/{number:03d}/"
            root = prefix + folder
            # The legacy v17 manifest already counts the corrected cover as
            # its FIRST reading image. Do not insert it again.
            files = issue["pages"]
            relroot = f"assets/official/{number:03d}"
            sources = []
            cover = legacy.read(root + files[0])
            listed_cover = legacy.read(root + issue["cover"])
            if cover != listed_cover:
                raise RuntimeError(f"Cover mismatch in source issue {number}")
            for index, original_filename in enumerate(files):
                data = legacy.read(root + original_filename)
                extension = Path(original_filename).suffix.lower()
                normalized_filename = f"{index:04d}{extension}"
                rel = f"{relroot}/{normalized_filename}"
                add_bytes(web / rel, data)
                expected_images[rel] = hashlib.sha256(data).hexdigest()
                sources.append(rel)
            thumb = thumbs / f"{number:03d}.jpg"
            from io import BytesIO
            with Image.open(BytesIO(cover)) as im:
                image = im.convert("RGB")
                image.thumbnail((280, 420), Image.Resampling.LANCZOS)
                image.save(thumb, "JPEG", quality=84, optimize=True)
            catalog.append({
                "id": f"print-{number:03d}",
                "kind": "official",
                "type": "images",
                "title": issue["title"],
                "cover": sources[0],
                "thumbnail": f"assets/native_thumbs/{number:03d}.jpg",
                "pages": sources,
            })
        if sum(len(x["pages"]) for x in catalog) != 654:
            raise RuntimeError("Original 25 comics must contain exactly 654 reading pages")
        add_bytes(package / "native_catalog.json", json.dumps(catalog, ensure_ascii=False).encode())

    info = plistlib.loads((REPO / "Info.plist").read_bytes())
    assert info["CFBundleIdentifier"] == "com.pocketgod.comics.offline"
    assert info["CFBundleShortVersionString"] == "3.0.0"
    assert info["UIDeviceFamily"] == [1, 2]
    add_bytes(package / "Info.plist", plistlib.dumps(info))

    with Image.open(originals / "icon@2x.png") as icon:
        rgba = icon.convert("RGBA")
        for size, suffix in [(120, "2x"), (180, "3x")]:
            rgba.resize((size, size), Image.Resampling.LANCZOS).save(
                package / f"Icon60@{suffix}.png"
            )
    xcrun = shutil.which("xcrun")
    if not xcrun:
        raise RuntimeError("This build requires macOS with Xcode / iPhoneOS SDK")
    sdk = subprocess.check_output([xcrun, "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip()
    compiler = subprocess.check_output([xcrun, "--sdk", "iphoneos", "--find", "clang"], text=True).strip()
    print(f"iOS SDK: {sdk}", flush=True)
    binary = package / "PocketGodComics"
    command = [
        compiler, "-arch", "arm64", "-isysroot", sdk,
        "-miphoneos-version-min=12.0", "-fobjc-arc", "-fblocks", "-O2",
        "-Wno-deprecated-declarations", "-Wno-unguarded-availability-new",
        *[str(REPO / file) for file in (
            "main.m", "AppDelegate.m", "PGImportedLibrary.m")],
        "-framework", "UIKit", "-framework", "Foundation",
        "-framework", "ImageIO", "-framework", "CoreGraphics",
        "-lz", "-o", str(binary),
    ]
    run(*command)
    run("xcrun", "lipo", "-info", binary)
    # Ad-hoc signing suitable for supported homebrew installation workflows;
    # ordinary non-jailbroken devices still require proper provisioning.
    run("codesign", "--force", "--sign", "-", "--timestamp=none", package)
    ARTIFACT.unlink(missing_ok=True)
    with zipfile.ZipFile(ARTIFACT, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=3) as dst:
        for path in sorted((BUILD / "Payload").rglob("*")):
            if path.is_file():
                dst.write(path, path.relative_to(BUILD).as_posix())

    with zipfile.ZipFile(ARTIFACT) as result:
        if result.testzip() is not None:
            raise RuntimeError("Failed final IPA CRC verification")
        prefix = "Payload/PocketGodComics.app/"
        actual = json.loads(result.read(prefix + "native_catalog.json"))
        assert len(actual) == 25 and sum(len(i["pages"]) for i in actual) == 654
        for relpath, sha in expected_images.items():
            output = hashlib.sha256(result.read(prefix + "web/" + relpath)).hexdigest()
            if output != sha:
                raise RuntimeError(f"Source comic image changed: {relpath}")
    sha = hashlib.sha256(ARTIFACT.read_bytes()).hexdigest()
    report = {
        "ipa": ARTIFACT.name,
        "bytes": ARTIFACT.stat().st_size,
        "sha256": sha,
        "architecture": "arm64",
        "original_issues": len(catalog),
        "byte_verified_pages": len(expected_images),
        "physical_device_test": "PENDING",
        "signature": "ad-hoc",
    }
    (BUILD / "QA.json").write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2), flush=True)


if __name__ == "__main__":
    main()
