# Architecture

The restoration target is the **existing iVerse-based Pocket God Comics reader**—not a new interface. The original iPhone and iPad UI, page navigation and other assets remain in the original application. Proprietary files aren't distributed in this repository.

## Components

1. **Original application:** User-supplied app binary and nibs; separate phone/tablet controllers.
2. **Offline manifest:** Local JSON listing episodes, page image filenames, cover and shelf thumbnail. Two archive sizes, 25 and 63 entries.
3. **Objective-C compatibility bridge:** Runtime hooks for known offline entries, preserving original methods for unrelated content.
4. **Core Data catalog:** Original Product and Supplier records, with small cover thumbnail entities.
5. **ComicBundle:** Original reader is supplied with local page counts and images.

| Path | Original class | Compatibility behavior |
|---|---|---|
| iPhone shelf | `MyComicsViewController` | Hooks `loadShelfView` so product records exist when original shelf refreshes |
| iPad shelf | `ShelfViewController_iPad` | Hooks `loadProducts` to merge local entries into the existing product list |
| Both readers | `ComicBundle` | Intercepts local offline pages, cover and page count, passing non-offline content through |

## Startup crash regression

An experimental v11 startup hook forced `showShelfView:` to present My Comics automatically. The owner reported that both v11 iPad editions crashed. v12 restored original launch behavior, and v13 builds on that rollback. The **only currently recommended QA path** is to navigate to My Comics manually. This is not proof that all other crashes have been resolved.

## Memory and offline content

Legacy iOS devices have very limited working memory. Instead of storing full 1024×1536 images repeatedly in Core Data, test packages use JPEG shelf thumbnails no larger than **144×216** pixels. Missing image records are restored in small asynchronous batches. Full comic pages remain separate on disk and are decoded as required.

Packaging supplies local pages instead of requesting them from discontinued network services. The app may still contain an original Store interface; network functionality of the old store is outside this preservation target.

## Source/release boundary

This repository contains the project-authored bridge source and inspection tools; it does not contain an executable or comic assets. A local, rights-respecting build starts with originals supplied by the user and uses a compatible Objective-C cross toolchain. Structural checks verify content counts and archive integrity, but real-device testing is essential.
