# Apple Release History

Generated from App Store Connect and git on 2026-06-08T16:21:31.624Z.

ASC is the source of truth for Apple versions and builds. Git commits are correlated by Xcode `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` snapshots.

## App Store Versions

| Version | State | Created | Released | Matched Git Commit | What's New |
| --- | --- | --- | --- | --- | --- |
| 1.0 | READY_FOR_SALE | 2025-06-07 |  | 64a79f8 (2026-05-17) |  |
| 1.0.1 | READY_FOR_SALE | 2026-05-17 |  | 5b4f1ba (2026-05-17) | • Improved video playback behavior and similar-photo scan responsiveness. • Added muted autoplay for video review cards and a location map in details when location data is available. • Added a dedicated video review mode with sorting by size, length, date, or random order. • Added sorting controls for screenshot review sessions. • Improved similar photo matching with burst detection, smarter visual matching, and confidence labels. • Added sorting controls and clearer cleanup estimates for similar photo groups. • Added a reset option for local settings and lifetime cleanup stats. |
| 1.0.2 | READY_FOR_SALE | 2026-06-06 |  | e93f1f8 (2026-06-04) | • Added new review sections for quick cleanup, space savers, and library finds. • Added review modes for old screenshots, screen recordings, large photos, Live Photos, bursts, and old favorites. • Improved swipe smoothness with better photo caching and more reliable image loading during fast reviews. • Improved similar-photo scanning with progress, partial results, clearer comparison details, and smarter best-pick labels. • Refined similar-photo review to skip screenshots and improved Large Photos category counts. • Added review memory controls with not-reviewed and total counts for review modes. • Added a Home indicator while review counts are updating in the background. • Kept local review history and image caches bounded so app storage and memory stay controlled over time. • Refined Home count updating with a quieter indicator and more targeted refreshes. • Made Home load faster with cached counts, deferred heavy scans, and in-session metadata reuse. |

## Builds

| Version | Build | Uploaded | Processing State | Expired | Matched Git Commit |
| --- | --- | --- | --- | --- | --- |
| 1.0 | 5 | 2026-04-21 | VALID |  | 64a79f8 (2026-05-17) |
| 1.0 | 6 | 2026-04-21 | VALID |  | 64a79f8 (2026-05-17) |
| 1.0 | 8 | 2026-04-21 | VALID |  | 64a79f8 (2026-05-17) |
| 1.0 | 9 | 2026-04-21 | VALID |  | 64a79f8 (2026-05-17) |
| 1.0 | 10 | 2026-04-21 | VALID |  | 64a79f8 (2026-05-17) |
| 1.0 | 11 | 2026-04-21 | VALID |  | 64a79f8 (2026-05-17) |
| 1.0 | 12 | 2026-04-23 | VALID |  | 64a79f8 (2026-05-17) |
| 1.0 | 13 | 2026-04-23 | VALID |  | 64a79f8 (2026-05-17) |
| 1.0 | 14 | 2026-04-23 | VALID |  | 64a79f8 (2026-05-17) |
| 1.0 | 15 | 2026-05-08 | VALID |  | 64a79f8 (2026-05-17) |
| 1.0 | 17 | 2026-05-08 | VALID |  | 64a79f8 (2026-05-17) |
| 1.0 | 18 | 2026-05-08 | VALID |  | 64a79f8 (2026-05-17) |
| 1.0 | 19 | 2026-05-08 | VALID |  | 64a79f8 (2026-05-17) |
| 1.0 | 20 | 2026-05-08 | VALID |  | 64a79f8 (2026-05-17) |
| 1.0 | 21 | 2026-05-08 | VALID |  | 64a79f8 (2026-05-17) |
| 1.0 | 22 | 2026-05-10 | VALID |  | 64a79f8 (2026-05-17) |
| 1.0 | 23 | 2026-05-11 | VALID |  | 64a79f8 (2026-05-17) |
| 1.0 | 24 | 2026-05-12 | VALID |  | 64a79f8 (2026-05-17) |
| 1.0 | 25 | 2026-05-14 | VALID |  | 64a79f8 (2026-05-17) |
| 1.0.1 | 27 | 2026-05-17 | VALID |  | d711634 (2026-05-17) |
| 1.0.1 | 28 | 2026-05-17 | VALID |  | 2bb949d (2026-05-17) |
| 1.0.1 | 29 | 2026-05-17 | VALID |  | a56f38f (2026-05-17) |
| 1.0.1 | 30 | 2026-05-17 | VALID |  | dec145f (2026-05-17) |
| 1.0.1 | 31 | 2026-05-17 | VALID |  | 5b4f1ba (2026-05-17) |
| 1.0.1 | 32 | 2026-05-17 | VALID |  | 5b4f1ba (2026-05-17) |
| 1.0.2 | 33 | 2026-05-28 | VALID |  | 873ada3 (2026-05-28) |
| 1.0.2 | 34 | 2026-05-28 | VALID |  | 3f1d068 (2026-05-28) |
| 1.0.2 | 35 | 2026-05-28 | VALID |  | b25a093 (2026-05-28) |
| 1.0.2 | 36 | 2026-05-28 | VALID |  | c8f62af (2026-05-28) |
| 1.0.2 | 37 | 2026-05-28 | VALID |  | e93f1f8 (2026-06-04) |
| 1.0.2 | 38 | 2026-06-04 | VALID |  | e93f1f8 (2026-06-04) |
| 1.0.2 | 39 | 2026-06-06 | VALID |  | e93f1f8 (2026-06-04) |

## Correlated Commits

### 1.0 (5)

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

### 1.0 (6)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### 1.0 (8)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### 1.0 (9)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### 1.0 (10)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### 1.0 (11)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### 1.0 (12)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### 1.0 (13)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### 1.0 (14)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### 1.0 (15)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### 1.0 (17)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### 1.0 (18)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### 1.0 (19)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### 1.0 (20)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### 1.0 (21)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### 1.0 (22)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### 1.0 (23)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### 1.0 (24)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### 1.0 (25)

Matched 64a79f8 from 2026-05-17: Add screenshot sorting and reset settings

No commits found in this range.

### 1.0.1 (27)

Matched d711634 from 2026-05-17: Bump release train and improve similar review

- Bump release train and improve similar review

### 1.0.1 (28)

Matched 2bb949d from 2026-05-17: Improve similar photo matching

- Improve similar photo matching

### 1.0.1 (29)

Matched a56f38f from 2026-05-17: Add video review mode

- Add agent release workflow notes
- Add video review mode

### 1.0.1 (30)

Matched dec145f from 2026-05-17: Add video autoplay and asset maps

- Add video autoplay and asset maps

### 1.0.1 (31)

Matched 5b4f1ba from 2026-05-17: Harden video and similar review UX

- Harden video and similar review UX

### 1.0.1 (32)

Matched 5b4f1ba from 2026-05-17: Harden video and similar review UX

No commits found in this range.

### 1.0.2 (33)

Matched 873ada3 from 2026-05-28: Refine review memory and category counts

- Improve review modes and swipe performance
- Refine review memory and category counts

### 1.0.2 (34)

Matched 3f1d068 from 2026-05-28: Show count refresh progress

- Show count refresh progress

### 1.0.2 (35)

Matched b25a093 from 2026-05-28: Refine count refresh indicator

- Refine count refresh indicator

### 1.0.2 (36)

Matched c8f62af from 2026-05-28: Speed up home count refreshes

- Speed up home count refreshes

### 1.0.2 (37)

Matched e93f1f8 from 2026-06-04: Remove misleading review folder

- Remove misleading review folder

### 1.0.2 (38)

Matched e93f1f8 from 2026-06-04: Remove misleading review folder

No commits found in this range.

### 1.0.2 (39)

Matched e93f1f8 from 2026-06-04: Remove misleading review folder

No commits found in this range.

