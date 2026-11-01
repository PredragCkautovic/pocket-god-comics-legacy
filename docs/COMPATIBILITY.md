# Legacy compatibility

**Current universal build target:** iOS **7.0 through 9.x**. The original application executable and injected bridge both include **armv7 and armv7s**; the package advertises both iPhone and iPad device families.

| Device | Target iOS version | Verification |
|---|---|---|
| iPhone 4 | 7.0–7.1.2 | Pending physical QA |
| iPhone 4S | 7.0–9.3.6 | Pending physical QA |
| iPhone 5 / 5c | 7.0–9.x | Pending physical QA |
| iPad 2 | 7.0–9.x | **v11 startup crash reported**; v13 retest pending |
| iPad 3 / 4 | 7.0–9.x | Pending physical QA |
| iPad mini (1st generation) | 7.0–9.x | Pending physical QA |

Compatibility means *targeted*, not *proven*: even with correct `UIDeviceFamily` and `MinimumOSVersion` declarations, legacy apps can fail on specific OS builds, devices and installation methods.

Some 64-bit devices on iOS 7–9 can run 32-bit apps; these are not individually certified. **Current exclusions:** iOS 6 and older, ARMv6, and iOS 11+ 32-bit application execution. Later versions of the app need a separately engineered 64-bit implementation.

## Test on physical hardware

For every report, capture: device model, exact iOS version, edition (25 or 63), cold-launch behavior, shelf display, page navigation, memory pressure and whether an existing app container was reused. Refer to [Testing](TESTING.md).
