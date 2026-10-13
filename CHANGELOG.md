# @kyter/snipsnaps-ios

## 1.3.0

### Minor Changes

- 652b570: Enjoy a refreshed Liquid Glass interface on iPhone, iPad, and Mac, with clearer review controls, a floating tab bar on iPhone, and livelier tap feedback.

  Pull to refresh photo counts on iPhone and iPad. Photos access is now requested only when you choose Enable.

  On Mac, file review categories sit above your folders so they stay easy to reach.

- 08b00b5: Tune Similar matching with a new slider in Settings. Choose Strict for near-identical shots, Balanced for the familiar matching behavior, or Loose to find more lookalikes.

### Patch Changes

- Review large Mac file collections faster with much lower memory use.

  Improve contrast, spacing, larger-text layouts, and VoiceOver descriptions across Home, review controls, and Settings.

  Make photo counts refresh more reliably, including Large Photos, and cancel file previews when they are no longer needed.

## 1.2.0

### Minor Changes

- Set an optional daily reminder for a quick photo review at the time you choose.
- On Mac, exclude folders from review and move an entire reviewed folder to the Trash with a recoverable action.
- Enjoy roomier adaptive layouts on iPad and Mac.

### Patch Changes

- Large Photo and Random reviews now stay responsive with more efficient loading and memory use.
- Review progress is saved more reliably, with clearer VoiceOver context across photo and Similar reviews.

## 1.1.1

### Patch Changes

- Refreshed the app icon.

## 1.1.0

### Minor Changes

- SnipSnaps is now available on Mac.
- Similar now scans your whole library and skips groups you have already reviewed, so each scan reaches new photos instead of showing you the same ones again.
- Fixed Similar and Duplicates missing some photos that had no subtype, such as photos added by AirDrop or imported without camera information.
- If you allow access to only selected photos, you can now add more photos or switch to full access at any time — from the Home screen, from Settings, or when a category runs out of photos to review. Before, limited access could leave you with nothing left to review and no way to add more.

## 1.0.4

### Patch Changes

- Redesigned the Similar photos review. Every photo now gets a clear Keep or Delete choice instead of selecting which ones to keep. Swipe through each photo in a group, tap a photo to see its details, open photos full screen to compare them, skip a group to decide later, and undo your last choice at any time.
- Improved how similar photos are grouped, so unrelated photos are much less likely to appear together.
- Reviewed photos now stay reviewed across every category. Once you keep or remove an item, it no longer reappears in another category until your Remember Reviewed window passes.
- The Delete button on the review summary is pinned to the bottom, so finishing a cleanup no longer means scrolling past the marked photos to find it.
- On This Day always resurfaces photos from past years, even ones you have reviewed elsewhere.

## 1.0.3

Reopened the App Store Connect release train after 1.0.2 closed to new build submissions.

## 1.0.2

Current tracked app version when Changesets release tracking was adopted.

Historical Apple release/build data is pulled from App Store Connect with `npm run release:backfill`.
