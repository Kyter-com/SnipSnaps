# Apple Release History

Generated from App Store Connect and git on 2026-07-29T01:01:47.075Z.

ASC is the source of truth for Apple versions and builds. Git commits are correlated by Xcode `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` snapshots.

## App Store Versions

| Platform | Version | State | Created | Released | Matched Git Commit | What's New |
| --- | --- | --- | --- | --- | --- | --- |
| iOS | 1.0 | READY_FOR_SALE | 2025-06-07 |  | 64a79f8 (2026-05-17) |  |
| iOS | 1.0.1 | READY_FOR_SALE | 2026-05-17 |  | 5b4f1ba (2026-05-17) | • Improved video playback behavior and similar-photo scan responsiveness. • Added muted autoplay for video review cards and a location map in details when location data is available. • Added a dedicated video review mode with sorting by size, length, date, or random order. • Added sorting controls for screenshot review sessions. • Improved similar photo matching with burst detection, smarter visual matching, and confidence labels. • Added sorting controls and clearer cleanup estimates for similar photo groups. • Added a reset option for local settings and lifetime cleanup stats. |
| iOS | 1.0.2 | READY_FOR_SALE | 2026-06-06 |  | e6a0d8a (2026-06-08) | • Added new review sections for quick cleanup, space savers, and library finds. • Added review modes for old screenshots, screen recordings, large photos, Live Photos, bursts, and old favorites. • Improved swipe smoothness with better photo caching and more reliable image loading during fast reviews. • Improved similar-photo scanning with progress, partial results, clearer comparison details, and smarter best-pick labels. • Refined similar-photo review to skip screenshots and improved Large Photos category counts. • Added review memory controls with not-reviewed and total counts for review modes. • Added a Home indicator while review counts are updating in the background. • Kept local review history and image caches bounded so app storage and memory stay controlled over time. • Refined Home count updating with a quieter indicator and more targeted refreshes. • Made Home load faster with cached counts, deferred heavy scans, and in-session metadata reuse. |
| iOS | 1.0.4 | READY_FOR_SALE | 2026-06-20 |  | b92215c (2026-07-02) | • Redesigned the Similar photos review. Every photo now gets a clear Keep or Delete choice instead of selecting which ones to keep. Swipe through each photo in a group, tap a photo to see its details, open photos full screen to compare them, skip a group to decide later, and undo your last choice at any time. • Improved how similar photos are grouped, so unrelated photos are much less likely to appear together. • Reviewed photos now stay reviewed across every category. Once you keep or remove an item, it no longer reappears in another category until your Remember Reviewed window passes. • The Delete button on the review summary is pinned to the bottom, so finishing a cleanup no longer means scrolling past the marked photos to find it. • On This Day always resurfaces photos from past years, even ones you have reviewed elsewhere. |
| iOS | 1.1.0 | READY_FOR_SALE | 2026-07-03 |  | 5246667 (2026-07-12) | • SnipSnaps is now available on Mac. • Similar now scans your whole library and skips groups you have already reviewed, so each scan reaches new photos instead of showing you the same ones again. • Fixed Similar and Duplicates missing some photos that had no subtype, such as photos added by AirDrop or imported without camera information. • If you allow access to only selected photos, you can now add more photos or switch to full access at any time — from the Home screen, from Settings, or when a category runs out of photos to review. Before, limited access could leave you with nothing left to review and no way to add more. |
| macOS | 1.1.0 | READY_FOR_SALE | 2026-07-13 |  | 5246667 (2026-07-12) |  |
| iOS | 1.1.1 | PREPARE_FOR_SUBMISSION | 2026-07-18 |  | 89bcc76 (2026-07-18) |  |
| macOS | 1.1.1 | PREPARE_FOR_SUBMISSION | 2026-07-18 |  | 89bcc76 (2026-07-18) |  |

## Builds

| Platform | Version | Build | Uploaded | Processing State | Expired | Matched Git Commit |
| --- | --- | --- | --- | --- | --- | --- |
| iOS | 1.0 | 5 | 2026-04-21 | VALID | true | 64a79f8 (2026-05-17) |
| iOS | 1.0 | 6 | 2026-04-21 | VALID | true | 64a79f8 (2026-05-17) |
| iOS | 1.0 | 8 | 2026-04-21 | VALID | true | 64a79f8 (2026-05-17) |
| iOS | 1.0 | 9 | 2026-04-21 | VALID | true | 64a79f8 (2026-05-17) |
| iOS | 1.0 | 10 | 2026-04-21 | VALID | true | 64a79f8 (2026-05-17) |
| iOS | 1.0 | 11 | 2026-04-21 | VALID | true | 64a79f8 (2026-05-17) |
| iOS | 1.0 | 12 | 2026-04-23 | VALID | true | 64a79f8 (2026-05-17) |
| iOS | 1.0 | 13 | 2026-04-23 | VALID | true | 64a79f8 (2026-05-17) |
| iOS | 1.0 | 14 | 2026-04-23 | VALID | true | 64a79f8 (2026-05-17) |
| iOS | 1.0 | 15 | 2026-05-08 | VALID |  | 64a79f8 (2026-05-17) |
| iOS | 1.0 | 17 | 2026-05-08 | VALID |  | 64a79f8 (2026-05-17) |
| iOS | 1.0 | 18 | 2026-05-08 | VALID |  | 64a79f8 (2026-05-17) |
| iOS | 1.0 | 19 | 2026-05-08 | VALID |  | 64a79f8 (2026-05-17) |
| iOS | 1.0 | 20 | 2026-05-08 | VALID |  | 64a79f8 (2026-05-17) |
| iOS | 1.0 | 21 | 2026-05-08 | VALID |  | 64a79f8 (2026-05-17) |
| iOS | 1.0 | 22 | 2026-05-10 | VALID |  | 64a79f8 (2026-05-17) |
| iOS | 1.0 | 23 | 2026-05-11 | VALID |  | 64a79f8 (2026-05-17) |
| iOS | 1.0 | 24 | 2026-05-12 | VALID |  | 64a79f8 (2026-05-17) |
| iOS | 1.0 | 25 | 2026-05-14 | VALID |  | 64a79f8 (2026-05-17) |
| iOS | 1.0.1 | 27 | 2026-05-17 | VALID |  | d711634 (2026-05-17) |
| iOS | 1.0.1 | 28 | 2026-05-17 | VALID |  | 2bb949d (2026-05-17) |
| iOS | 1.0.1 | 29 | 2026-05-17 | VALID |  | a56f38f (2026-05-17) |
| iOS | 1.0.1 | 30 | 2026-05-17 | VALID |  | dec145f (2026-05-17) |
| iOS | 1.0.1 | 31 | 2026-05-17 | VALID |  | 5b4f1ba (2026-05-17) |
| iOS | 1.0.1 | 32 | 2026-05-17 | VALID |  | 5b4f1ba (2026-05-17) |
| iOS | 1.0.2 | 33 | 2026-05-28 | VALID |  | 873ada3 (2026-05-28) |
| iOS | 1.0.2 | 34 | 2026-05-28 | VALID |  | 3f1d068 (2026-05-28) |
| iOS | 1.0.2 | 35 | 2026-05-28 | VALID |  | b25a093 (2026-05-28) |
| iOS | 1.0.2 | 36 | 2026-05-28 | VALID |  | c8f62af (2026-05-28) |
| iOS | 1.0.2 | 37 | 2026-05-28 | VALID |  | e93f1f8 (2026-06-04) |
| iOS | 1.0.2 | 38 | 2026-06-04 | VALID |  | 37a207e (2026-06-06) |
| iOS | 1.0.2 | 39 | 2026-06-06 | VALID |  | e6a0d8a (2026-06-08) |
| iOS | 1.0.3 | 41 | 2026-06-08 | VALID |  | 312d4be (2026-06-08) |
| iOS | 1.0.3 | 42 | 2026-06-20 | VALID |  | d9293a8 (2026-06-20) |
| iOS | 1.0.4 | 43 | 2026-06-20 | VALID | true | 23114bb (2026-06-20) |
| iOS | 1.0.4 | 44 | 2026-06-20 | VALID | true | b77beda (2026-06-20) |
| iOS | 1.0.4 | 45 | 2026-06-20 | VALID | true | 08b6441 (2026-06-20) |
| iOS | 1.0.4 | 46 | 2026-06-20 | VALID | true | b92215c (2026-07-02) |
| iOS | 1.0.4 | 47 | 2026-06-20 | VALID |  | b92215c (2026-07-02) |
| iOS | 1.1.0 | 49 | 2026-07-03 | VALID |  | 5246667 (2026-07-12) |
| iOS | 1.1.0 | 50 | 2026-07-03 | VALID |  | 93ee789 (2026-07-03) |
| iOS | 1.1.0 | 51 | 2026-07-03 | VALID |  | 5246667 (2026-07-12) |
| iOS | 1.1.0 | 52 | 2026-07-10 | VALID |  | d390b3b (2026-07-10) |
| iOS | 1.1.0 | 53 | 2026-07-11 | VALID |  | 5246667 (2026-07-12) |
| iOS | 1.1.0 | 54 | 2026-07-11 | VALID |  | 5246667 (2026-07-12) |
| iOS | 1.1.0 | 55 | 2026-07-11 | VALID |  | 2c9d62c (2026-07-11) |
| iOS | 1.1.0 | 56 | 2026-07-12 | VALID |  | 5246667 (2026-07-12) |
| iOS | 1.1.0 | 57 | 2026-07-12 | VALID |  | 5246667 (2026-07-12) |
| iOS | 1.1.0 | 58 | 2026-07-13 | VALID |  | 5246667 (2026-07-12) |
| macOS | 1.1.0 | 59 | 2026-07-13 | VALID |  | 5246667 (2026-07-12) |
| iOS | 1.1.0 | 60 | 2026-07-13 | VALID |  | 5246667 (2026-07-12) |
| macOS | 1.1.0 | 61 | 2026-07-13 | VALID |  | 5246667 (2026-07-12) |
| macOS | 1.1.0 | 62 | 2026-07-13 | VALID |  | 5246667 (2026-07-12) |
| iOS | 1.1.0 | 63 | 2026-07-13 | VALID |  | 5246667 (2026-07-12) |
| iOS | 1.1.1 | 64 | 2026-07-18 | VALID |  | 89bcc76 (2026-07-18) |
| macOS | 1.1.1 | 65 | 2026-07-18 | VALID |  | 89bcc76 (2026-07-18) |
| iOS | 1.1.1 | 66 | 2026-07-26 | VALID |  | 89bcc76 (2026-07-18) |
| macOS | 1.1.1 | 67 | 2026-07-26 | VALID |  | 89bcc76 (2026-07-18) |

## Correlated Commits

### iOS 1.0 (5)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

- Initial Commit
- icon
- rm unused
- setup photos auth
- handle cases
- push
- changes
- polish review flow and add on this day
- align app permissions for release
- limit app targets to iphone only
- bump build number
- fix app icon alpha channel
- fix review photo quality
- fix photo preview placeholder
- set export compliance flag
- add photo details during review
- polish review transitions and live photos
- refine review card handoff
- polish review swiper motion
- refine review card stack
- simplify review action chrome
- Hide tab bar during photo review
- Add similar photo review flow
- Add app store screenshots skill
- Allow multiple keep selections in similar review
- Polish similar photo review UX
- Add App Store screenshot assets
- Use simulator captures for app store screenshots
- Prepare App Store release metadata
- Automate App Store screenshot captures from the real app
- Polish App Store screenshots and fix GitHub icon
- Clarify photo library purpose string for App Review
- Add screenshot sorting and reset settings

### iOS 1.0 (6)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### iOS 1.0 (8)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### iOS 1.0 (9)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### iOS 1.0 (10)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### iOS 1.0 (11)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### iOS 1.0 (12)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### iOS 1.0 (13)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### iOS 1.0 (14)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### iOS 1.0 (15)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### iOS 1.0 (17)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### iOS 1.0 (18)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### iOS 1.0 (19)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### iOS 1.0 (20)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### iOS 1.0 (21)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### iOS 1.0 (22)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### iOS 1.0 (23)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### iOS 1.0 (24)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### iOS 1.0 (25)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### iOS 1.0.1 (27)

Matched d711634 from 2026-05-17: Bump release train and improve similar review

- Bump release train and improve similar review

### iOS 1.0.1 (28)

Matched 2bb949d from 2026-05-17: Improve similar photo matching

- Improve similar photo matching

### iOS 1.0.1 (29)

Matched a56f38f from 2026-05-17: Add video review mode

- Add agent release workflow notes
- Add video review mode

### iOS 1.0.1 (30)

Matched dec145f from 2026-05-17: Add video autoplay and asset maps

- Add video autoplay and asset maps

### iOS 1.0.1 (31)

Matched 5b4f1ba from 2026-05-17: Harden video and similar review UX

- Harden video and similar review UX

### iOS 1.0.1 (32)

Matched 5b4f1ba from 2026-05-17: Harden video and similar review UX

No commits found in this range.

### iOS 1.0.2 (33)

Matched 873ada3 from 2026-05-28: Refine review memory and category counts

- Improve review modes and swipe performance
- Refine review memory and category counts

### iOS 1.0.2 (34)

Matched 3f1d068 from 2026-05-28: Show count refresh progress

- Show count refresh progress

### iOS 1.0.2 (35)

Matched b25a093 from 2026-05-28: Refine count refresh indicator

- Refine count refresh indicator

### iOS 1.0.2 (36)

Matched c8f62af from 2026-05-28: Speed up home count refreshes

- Speed up home count refreshes

### iOS 1.0.2 (37)

Matched e93f1f8 from 2026-06-04: Remove misleading review folder

- Remove misleading review folder

### iOS 1.0.2 (38)

Matched 37a207e from 2026-06-06: Bump version to 1.0.2 (build 38)

- Bump version to 1.0.2 (build 38)

### iOS 1.0.2 (39)

Matched e6a0d8a from 2026-06-08: Add ASC-backed release tracking

- Add ASC-backed release tracking

### iOS 1.0.3 (41)

Matched 312d4be from 2026-06-08: Bump release train to 1.0.3

- Bump release train to 1.0.3

### iOS 1.0.3 (42)

Matched d9293a8 from 2026-06-20: Fix cross-category review memory and review summary delete (build 42)

- Fix cross-category review memory and review summary delete (build 42)

### iOS 1.0.4 (43)

Matched 23114bb from 2026-06-20: Redesign Similar photos review (1.0.4, build 43)

- Redesign Similar photos review (1.0.4, build 43)

### iOS 1.0.4 (44)

Matched b77beda from 2026-06-20: Use swipe flow for all similar groups; fix similar-photo matching (build 44)

- Use swipe flow for all similar groups; fix similar-photo matching (build 44)

### iOS 1.0.4 (45)

Matched 08b6441 from 2026-06-20: Match Similar review UI to other modes; filmstrip on top (build 45)

- Correct 1.0.4 notes: swipe-only similar review + grouping accuracy
- Match Similar review UI to other modes; filmstrip on top (build 45)

### iOS 1.0.4 (46)

Matched b92215c from 2026-07-02: chore: sync build number before merge

- Add macOS port implementation plan (docs)
- macOS Phase 0-1: native Mac target, sandbox entitlements, fix UIKit-only code
- Fix macOS launch crash: use .formStyle(.grouped) in Settings
- docs: record macOS Form layout-cycle crash + fix in port plan
- macOS Phase 2: restore Similar/duplicate scan on macOS (shared CGImage core)
- macOS Phase 4: on-disk Files cleanup surface (macOS-only)
- Make Files surface cohesive with Photos (shared settings + stats)
- macOS Phase 4b: Files 'Remember Reviewed' + duplicate detection
- docs: update macOS port plan with progress log at pause point
- macOS: native UI/UX & desktop pass (sidebar, menus, keyboard, Liquid Glass, Finder, bug fixes)
- macOS: review fixes, lower deploy target to 15, a11y + UX polish
- macOS: resolve review issues and harden Files flow
- chore: prep macOS branch for merge
- chore: sync build number before merge

### iOS 1.0.4 (47)

Matched b92215c from 2026-07-02: chore: sync build number before merge

No commits found in this range.

### iOS 1.1.0 (49)

Matched 5246667 from 2026-07-12: chore: release 1.1.0 (build 56)

- chore: bump marketing version to 1.1.0 (open new App Store train)
- ci: pre-push guard against shipping a closed App Store version train
- Let limited-access users add photos or grant full access
- Similar: scan the whole library and skip already-reviewed groups
- Redesign App Store screenshots: aurora backdrop + real iPhone 16 frame
- chore: bump build number to 52
- Fix Similar/duplicate scan returning nothing for NULL-subtype photos
- Show location map + fully-expanded details in App Store screenshot #4
- Frame iPad App Store screenshots in a real iPad Pro 13" mockup
- Bolder App Store screenshot headlines + plainer taglines
- macOS: match iOS grouped palette and fix native UI details
- Add macOS App Store screenshot pipeline and regenerate the Mac shots
- chore: bump build number to 55
- Fix Similar scan depth, Mac Trash reveal, and review perf/a11y
- chore: release 1.1.0 (build 56)

### iOS 1.1.0 (50)

Matched 93ee789 from 2026-07-03: Let limited-access users add photos or grant full access

No commits found in this range.

### iOS 1.1.0 (51)

Matched 5246667 from 2026-07-12: chore: release 1.1.0 (build 56)

- Similar: scan the whole library and skip already-reviewed groups
- Redesign App Store screenshots: aurora backdrop + real iPhone 16 frame
- chore: bump build number to 52
- Fix Similar/duplicate scan returning nothing for NULL-subtype photos
- Show location map + fully-expanded details in App Store screenshot #4
- Frame iPad App Store screenshots in a real iPad Pro 13" mockup
- Bolder App Store screenshot headlines + plainer taglines
- macOS: match iOS grouped palette and fix native UI details
- Add macOS App Store screenshot pipeline and regenerate the Mac shots
- chore: bump build number to 55
- Fix Similar scan depth, Mac Trash reveal, and review perf/a11y
- chore: release 1.1.0 (build 56)

### iOS 1.1.0 (52)

Matched d390b3b from 2026-07-10: chore: bump build number to 52

No commits found in this range.

### iOS 1.1.0 (53)

Matched 5246667 from 2026-07-12: chore: release 1.1.0 (build 56)

- Fix Similar/duplicate scan returning nothing for NULL-subtype photos
- Show location map + fully-expanded details in App Store screenshot #4
- Frame iPad App Store screenshots in a real iPad Pro 13" mockup
- Bolder App Store screenshot headlines + plainer taglines
- macOS: match iOS grouped palette and fix native UI details
- Add macOS App Store screenshot pipeline and regenerate the Mac shots
- chore: bump build number to 55
- Fix Similar scan depth, Mac Trash reveal, and review perf/a11y
- chore: release 1.1.0 (build 56)

### iOS 1.1.0 (54)

Matched 5246667 from 2026-07-12: chore: release 1.1.0 (build 56)

No commits found in this range.

### iOS 1.1.0 (55)

Matched 2c9d62c from 2026-07-11: chore: bump build number to 55

No commits found in this range.

### iOS 1.1.0 (56)

Matched 5246667 from 2026-07-12: chore: release 1.1.0 (build 56)

- Fix Similar scan depth, Mac Trash reveal, and review perf/a11y
- chore: release 1.1.0 (build 56)

### iOS 1.1.0 (57)

Matched 5246667 from 2026-07-12: chore: release 1.1.0 (build 56)

No commits found in this range.

### iOS 1.1.0 (58)

Matched 5246667 from 2026-07-12: chore: release 1.1.0 (build 56)

No commits found in this range.

### macOS 1.1.0 (59)

Matched 5246667 from 2026-07-12: chore: release 1.1.0 (build 56)

No commits found in this range.

### iOS 1.1.0 (60)

Matched 5246667 from 2026-07-12: chore: release 1.1.0 (build 56)

No commits found in this range.

### macOS 1.1.0 (61)

Matched 5246667 from 2026-07-12: chore: release 1.1.0 (build 56)

No commits found in this range.

### macOS 1.1.0 (62)

Matched 5246667 from 2026-07-12: chore: release 1.1.0 (build 56)

No commits found in this range.

### iOS 1.1.0 (63)

Matched 5246667 from 2026-07-12: chore: release 1.1.0 (build 56)

No commits found in this range.

### iOS 1.1.1 (64)

Matched 89bcc76 from 2026-07-18: Adopt Icon Composer app icon and release 1.1.1

- Fix Mac App Store screenshots: uncropped home hero + consistent counts
- macos portion
- Record 1.1.0 macOS release and fix macOS keyword length
- Harden release-notes flow and clean up changelog history
- Adopt Icon Composer app icon and release 1.1.1

### macOS 1.1.1 (65)

Matched 89bcc76 from 2026-07-18: Adopt Icon Composer app icon and release 1.1.1

No commits found in this range.

### iOS 1.1.1 (66)

Matched 89bcc76 from 2026-07-18: Adopt Icon Composer app icon and release 1.1.1

No commits found in this range.

### macOS 1.1.1 (67)

Matched 89bcc76 from 2026-07-18: Adopt Icon Composer app icon and release 1.1.1

No commits found in this range.

