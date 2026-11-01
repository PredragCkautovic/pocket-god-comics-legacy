# Real-device QA checklist

## Before starting

- [ ] Back up original app and data
- [ ] Record device model, full iOS version, edition, and IPA build
- [ ] Note clean vs upgraded data-container state
- [ ] Confirm free space for the large offline archive
- [ ] Install via an authorized mechanism

## Startup

- [ ] App cold-starts without crashing
- [ ] Original initial screen appears; My Comics is **not** forced open
- [ ] Tap My Comics manually
- [ ] 25 or 63 entries appear with stable scrolling
- [ ] Cover thumbnails for the first, middle and last entries are correct

## Reading

- [ ] Open first, middle and last comic
- [ ] Next/previous page works
- [ ] Images are not blank or corrupt
- [ ] Close reader and return to My Comics successfully
- [ ] Previously opened entries remain installed
- [ ] Library operates with network disconnected for local content

## Stability

- [ ] Cold-start and relaunch repeatedly
- [ ] Stress-test 63-cover scrolling without memory termination
- [ ] Test after termination and after device reboot if feasible
- [ ] Record crashes with timestamps and sanitized logs
- [ ] Confirm edition-to-edition behavior separately

## Suggested hardware order

iPhone 4 (iOS 7.1.2), iPhone 4S (its installed iOS), iPad 2 (iOS 9), then other 32-bit devices.

Use the [bug template](../.github/ISSUE_TEMPLATE/bug_report.yml). **Do not attach proprietary IPAs, commercial comic pages, credentials or personally identifying logs.**
