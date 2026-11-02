# Pocket God Comics — Modern Android 0.1 alpha

This project is a native Android offline reader that shares the *verified original comic assets* with the modern iOS reconstruction. It is **not** an Android emulator for the original 32-bit iVerse executable, and is not yet a pixel-perfect adaptation.

## Asset provenance

GitHub Actions runs the owner-authorized modern-iOS asset builder to retrieve the already-public legacy v17 IPA, converts Apple CgBI PNG artwork, and stages an Android APK with:
- 25 corrected original print issues, in print issue order.
- 654 source-authentic page images, verified against the source archive.
- Original iVerse header/shelf button graphics and corrected book covers.
- Completely offline reading; no authentication or remote services.

## Native Android features in alpha

Native scrolling illustrated shelves, two-column portrait phone/tablet and four-column tablet landscape; Shelf/List switch; live comic title search; Custom library; Files-based CBZ import; long-press delete of imported CBZs; native full-screen reader with page swipes and edge taps, pinch zoom, double-tap zoom, page scrubber, bookmarks, saved reading position and iPad-style two-page landscape mode on tablets.

CBZ import uses bounded ZIP extraction, image-dimension checks, file-count/size limits, and app-private directories with generated filenames. User-provided CBZs are copied locally and can be removed individually.

## Android APK build

Workflow: `.github/workflows/android-modern-apk.yml` on branch `modern-3.0.0-rc1-ci`.

The workflow must pass these gates before any download is called ready: native Android Gradle build, APK ZIP CRC integrity, 25 issue catalog entries, all 654 packaged media file paths, AndroidManifest.xml and classes.dex.

The generated artifact is a **debug-signed test APK**, not a production Play Store release.

## Hardware test checklist

1. Launch offline and scroll from issue #1 to #25 in portrait; rotate to landscape and check shelf alignment.
2. Open issues #1, #13, and #25. Swipe, edge tap, scrub to last page, rotate, pinch/double-tap zoom. Check that zoomed dragging does not change pages.
3. Verify page progress and bookmarks persist after force-close/relaunch. Confirm two-page landscape tablet mode (cover remains single).
4. Open a different issue from the final-page dialog; end of issue #25 should offer only stay/return.
5. Import a valid CBZ via Files; verify its first image as cover, natural numeric page order, search, deletion and preservation of original issues.
6. Verify malformed or oversized archives refuse import without corrupting the Custom library.
7. Compare with real iVerse iPhone 4 / iPad 2 screenshots for original-layout refinements. Current Android surfaces are a native recreation, not the original iVerse binary.

## Next fidelity and stability improvements

- Original drawer animation and exact control/shelf metrics from device reference screenshots.
- Memory profiling and bounded cache on low-RAM Android devices.
- RTL/manga direction and single/double spread enhancements after source verification.
- Signed non-debug APK and installation/update QA after hardware acceptance.
