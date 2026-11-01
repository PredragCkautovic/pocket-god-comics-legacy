# Troubleshooting and known limitations

### Immediate startup crash

Two previous **v11 iPad** builds were reported to crash after automatically opening My Comics from the app delegate. This behavior was removed in v12 and v13. Use original startup and open My Comics manually. If the new build still crashes, collect sanitized diagnostics before assuming the cause.

### iPhone crashes when opening My Comics

The owner confirmed this on a v13 Classic 25 iPhone test while the same edition **worked on iPad**. The iPhone's own shelf lifecycle had extra compatibility hooks to seed Core Data during shelf loading and reload it again on appearance. A v13.1 experimental patch disables those extra phone-specific hooks, leaving the original phone shelf controller to load normally. The precise cause is **not confirmed without the phone crash log**. Retesting is required before declaring a fix.

### iPhone 4 crashes on v13.2 deferred original shelf reload

The owner compared v13.2 diagnostics from iPhone 4 and iPhone 4S. Both created all 25 offline Core Data records. On iPhone 4, the final log event was entry into the deferred second call to the original My Comics shelf loader; the app later restarted. On iPhone 4S, that call returned and all 25 cover records finished processing. This strongly suggests the repeated shelf reload is unsafe on iPhone 4, but the actual termination reason requires an iOS crash report.

v13.3 removes the repeat loadShelfView call entirely and refetches the existing phone controller after the catalog is ready, then reloads its original table view. The earlier assumption that alphabeticalIndex was a named cache was incorrect: it is the original section-name key path, and the original controller has no named cache. The iPad code is left untouched. **v13.3 is an unverified test build, not a confirmed repair.**

### v14 loads, but comics are in alphabetical order

The owner confirmed that **both iPhone 4 and 4S** now load the offline comics with v14. That repair aligned `Product.sortName` with the displayed title, which resolved Core Data section error 134060 but naturally sorted the stories alphabetically. To restore issue progression while retaining the original reader, **v15** gives offline iPhone comics a zero-padded numeric sort key (`0001` through `0063`) and provides a matching single numeric section through a narrow override of `Product.alphabeticalIndex`. Commercial/original products continue using the original section behavior. The iPad original shelf methods are unchanged. Installed comic rows are migrated in place, without removing their reading progress. This is a test candidate, awaiting physical phone confirmation.

### v13.3 stable iPhones, but no books: Core Data error 134060

Both owner-supplied v13.3 logs successfully seed 25 of 25 offline entries yet report an unsuccessful NSFetchedResultsController fetch (Core Data 134060). Investigation of the original iVerse executable confirmed that `Database.productsByName` sorts first by `Product.sortName`, but sections are derived from `Product.alphabeticalIndex` (the first character of `Product.name`). Old offline builds saved identifiers like `pg.offline.001` as sortName while retaining natural chapter titles in name. This violates the controller's alphabetical section order. **v14** now stores the displayed title as sortName, including an in-place migration for already installed entries, and logs fetch-error details if the problem persists. Do not delete the device's app data merely to apply this fix. Real-device confirmation is still pending.

### iPhone no longer crashes, but My Comics shows no books

The owner confirmed v13.1 avoids the immediate iPhone crash but still presents an empty comic shelf. The original phone shelf creates an NSFetchedResultsController whose named cache can predate local offline catalog seeding. v13.2 attempts **one deferred refresh** after the catalog is ready and the phone shelf is visible, with a bounded retry window and no extra synchronous lifecycle seeding. This remains a testable hypothesis until iPhone hardware confirms that the books appear.

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
