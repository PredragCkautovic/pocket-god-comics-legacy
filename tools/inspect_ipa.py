#!/usr/bin/env python3
"""Read-only inspection of a locally owned iOS IPA, without distributing contents.

Only standard-library dependencies. Does not unpack proprietary images or executable.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import plistlib
import struct
import sys
import zipfile

FAT_MAGIC = b"\xca\xfe\xba\xbe"
FAT_MAGIC_LE = b"\xbe\xba\xfe\xca"
CPU_ARM = 12
ARM_SUBTYPES = {9: "armv7", 11: "armv7s"}

def archs(data: bytes) -> list[str]:
    """Read architecture headers without executing or extracting anything."""
    if len(data) < 8:
        return []
    if data[:4] in (FAT_MAGIC, FAT_MAGIC_LE):
        prefix = ">" if data[:4] == FAT_MAGIC else "<"
        count = struct.unpack_from(prefix + "I", data, 4)[0]
        if count > 20 or len(data) < 8 + count * 20:
            return []
        result = []
        for index in range(count):
            cputype, subtype, _, _, _ = struct.unpack_from(prefix + "IIIII", data, 8 + index * 20)
            result.append(ARM_SUBTYPES.get(subtype & 0x00FFFFFF, f"cpu-{cputype}-subtype-{subtype & 0x00FFFFFF}")
                          if cputype == CPU_ARM else f"cpu-{cputype}")
        return result
    if data[:4] in (b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xce"):
        prefix = "<" if data[:4] == b"\xce\xfa\xed\xfe" else ">"
        cpu, subtype = struct.unpack_from(prefix + "II", data, 4)
        return [ARM_SUBTYPES.get(subtype & 0x00FFFFFF, f"cpu-{cpu}-subtype-{subtype & 0x00FFFFFF}")
                if cpu == CPU_ARM else f"cpu-{cpu}"]
    return ["not-recognized"]

def inspect(path: Path) -> dict:
    with zipfile.ZipFile(path) as ipa:
        entries = ipa.namelist()
        if any(name.startswith("/") or ".." in Path(name).parts for name in entries):
            raise ValueError("Unsafe archive member paths")
        apps = sorted({name.split("/")[1] for name in entries if name.startswith("Payload/")
                       and name.endswith(".app/Info.plist") and name.count("/") == 2})
        if len(apps) != 1:
            raise ValueError(f"Expected exactly one application bundle, found: {apps}")
        root = "Payload/" + apps[0] + "/"
        info = plistlib.loads(ipa.read(root + "Info.plist"))
        executable_name = info.get("CFBundleExecutable", "")
        if not isinstance(executable_name, str) or not executable_name:
            raise ValueError("Missing executable name in Info.plist")
        exe = ipa.read(root + executable_name)
        library_name = root + "PGOfflineLoader.dylib"
        library_archs = archs(ipa.read(library_name)) if library_name in entries else []
        manifest_name = root + "PGOffline/manifest.json"
        manifest = json.loads(ipa.read(manifest_name)) if manifest_name in entries else {}
        episode_count = len(manifest.get("episodes", []))
        page_count = sum(len(e.get("pages", [])) for e in manifest.get("episodes", []))
        return {
            "file": path.name,
            "bytes": path.stat().st_size,
            "bundle_identifier": info.get("CFBundleIdentifier"),
            "display_name": info.get("CFBundleDisplayName", info.get("CFBundleName")),
            "minimum_ios_version": info.get("MinimumOSVersion"),
            "device_families": info.get("UIDeviceFamily"),
            "executable_architectures": archs(exe),
            "compatibility_bridge_architectures": library_archs,
            "offline_episode_count": episode_count,
            "offline_page_count": page_count,
            "custom_cover_count": len(manifest.get("art_applied", [])),
            "missing_custom_cover_numbers": manifest.get("art_missing", []),
        }

def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("ipa", type=Path, help="Path to a locally owned IPA file")
    p.add_argument("--json", action="store_true", help="Print machine-readable JSON")
    args = p.parse_args()
    if not args.ipa.is_file():
        p.error(f"File not found: {args.ipa}")
    try:
        result = inspect(args.ipa)
    except (ValueError, KeyError, OSError, zipfile.BadZipFile, plistlib.InvalidFileException) as exc:
        print(f"Inspection failed: {exc}", file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        for key, value in result.items():
            print(f"{key.replace('_', ' '):35s}: {value}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
