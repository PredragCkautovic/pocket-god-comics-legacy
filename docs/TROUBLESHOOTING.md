# Troubleshooting and known limitations

### Immediate startup crash

Two previous **v11 iPad** builds were reported to crash after automatically opening My Comics from the app delegate. This behavior was removed in v12 and v13. Use original startup and open My Comics manually. If the new build still crashes, collect sanitized diagnostics before assuming the cause.

### iPhone crashes when opening My Comics

The owner confirmed this on a v13 Classic 25 iPhone test while the same edition **worked on iPad**. The iPhone's own shelf lifecycle had extra compatibility hooks to seed Core Data during shelf loading and reload it again on appearance. A v13.1 experimental patch disables those extra phone-specific hooks, leaving the original phone shelf controller to load normally. The precise cause is **not confirmed without the phone crash log**. Retesting is required before declaring a fix.

### My Comics has an empty shelf

The original phone and tablet use different controllers. The compatibility bridge hooks both paths, but real-device behavior still needs verification. Record which device/OS and which edition, and whether the catalog remains empty on a repeat launch.

### Covers missing, blurry, or shelf freezes

The small JPEG thumbnail cache is intentional to reduce memory usage. The original implementation holds multiple Core Data image objects per product. Allow time for the cache to initialize on the first launch. Do not assume full-resolution cover art should be embedded in shelf thumbnails.

### Books disappear after opening

The original reader can treat an unreadable legacy comic bundle as a bad product. The offline bridge has an interception path for local content and blocks the automatic removal of those entries. Report the affected number and exact action; this path needs physical testing.

### Classic 25 covers do not match episode stories

Original *printed issue* covers and the first 25 *WEBTOON episodes* are different sequences. Their current index mapping is explicitly provisional until authentic printed-volume regrouping is complete.

### Original Store won't load

Offline reading and legacy network commerce are different features. The old iVerse Store may rely on unavailable services. This project does not recreate or circumvent them.

### Installation fails

Check `MinimumOSVersion`, 32-bit compatibility, code signing, available space, correct bundle ID, and authorized installation mechanism. No commercial IPA is distributed by this public repo.
