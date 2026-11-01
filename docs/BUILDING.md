# Building — prerequisites and limitations

This repository exposes the preservation bridge's Objective-C source, inspection helpers and architectural documentation. **It is not a complete build-from-scratch distribution of the third-party application.**

## Privately supplied prerequisites

- Legally obtained original iVerse-based Pocket God Comics application bundle.
- Locally obtained offline comic pages and covers with appropriate usage rights.
- Properly authorized iOS SDK, compatible Objective-C cross compiler and ARMv7 linker.
- A Mach-O load-command editor and an authorized installation/signing workflow.
- Python 3 for staging, manifest validation and archive inspection; Pillow for cover validation.
- At least one physical device for actual compatibility testing.

The private packaging pipeline changes only the application identifier/display metadata and executable load command, adds the compatibility library and local offline content, and retains the original interface/assets. Package verification compares source pages and covers byte-for-byte.

## Compiling the bridge (illustrative; not a complete IPA)

Assuming a legal SDK and toolchain have already been set up, compile a copy for each legacy architecture:

```sh
"$CC" -target armv7-apple-ios7.0 -isysroot "$SDKROOT" \
  -fobjc-arc -O2 -c src/PGOfflineLoader.m -o bridge.armv7.o

"$CC" -target armv7s-apple-ios7.0 -isysroot "$SDKROOT" \
  -fobjc-arc -O2 -c src/PGOfflineLoader.m -o bridge.armv7s.o
```

Link each slice against matching system frameworks and combine them with `llvm-lipo`. The resulting library alone is not an app and cannot be used without the lawful original app and local content. Don't ship a private app bundle, copyrighted issues or SDK as part of a public build.

## Inspection utilities

```sh
python3 tools/inspect_ipa.py /path/to/owned-test.ipa
python3 -m pip install -r requirements-dev.txt
python3 tools/verify_cover_set.py /path/to/numbered/covers --start 26 --end 63
```

## Reproducibility status

The project still depends on private, user-supplied inputs and a legacy iOS toolchain. It is not a one-click reproducible public IPA build; this is an explicit future roadmap item. Compilation and structural verification cannot replace device QA.
