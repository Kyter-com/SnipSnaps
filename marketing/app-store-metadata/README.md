# SnipSnaps App Store Metadata

Prepared non-image release metadata for App Store Connect.

## Required App Information

- Name: SnipSnaps
- Subtitle: Clean up your photo library
- Primary category: Photo & Video
- Secondary category: Utilities
- Bundle ID: com.kyter.SnipSnaps
- Version: 1.0.1
- Build: 29
- Content rights: The app does not contain, show, or access third-party content outside the user's own photo library.
- Encryption: Uses no non-exempt encryption (`ITSAppUsesNonExemptEncryption` is false).

## Description

SnipSnaps helps you clean up your photo library in quick, focused review sessions.

Swipe through recent photos, screenshots, videos, memories from this day, random shots, or duplicate-looking groups. Keep the photos and videos that matter, mark the ones you do not need, and delete them when you are ready. Every session is designed to be fast enough for a spare minute and careful enough to avoid accidental cleanup.

Use SnipSnaps to:

- Review your newest photos before clutter builds up
- Clear screenshots without digging through Photos
- Sort videos by size, length, or date before reviewing
- Revisit pictures from this day across past years
- Find similar-looking groups and choose the best shot
- See how many photos and videos, and how much storage you have cleared

SnipSnaps works with your photo library on device. It asks for Photos access only so you can review and delete the photos and videos you choose.

## Promotional Text

Clean up recent photos, videos, screenshots, memories, and similar-looking shots in fast swipe sessions.

## Keywords

photo cleaner,delete photos,storage,duplicates,screenshots,camera roll,photo organizer,cleanup

## What's New

• Added a dedicated video review mode with sorting by size, length, date, or random order.
• Added sorting controls for screenshot review sessions.
• Improved similar photo matching with burst detection, smarter visual matching, and confidence labels.
• Added sorting controls and clearer cleanup estimates for similar photo groups.
• Added a reset option for local settings and lifetime cleanup stats.

## Review Notes

SnipSnaps does not require an account or server access. To review the app, launch it and grant Photos permission when prompted. The app reads the user's photo library locally to present review sessions. When a user chooses to delete selected photos, iOS moves those assets to Recently Deleted through the system Photos API.

Suggested review path:

1. Open SnipSnaps.
2. Grant full or limited Photos access.
3. Choose Today, Screenshots, Videos, Random, On This Day, or Similar.
4. Swipe or use the action buttons to keep or mark photos.
5. Confirm deletion for marked photos.

## Privacy Nutrition Label Draft

Data collected: None.

Tracking: No.

Linked to user: None.

Data used for tracking: None.

Photos access: The app accesses the user's photo library on device to display review sessions and delete only the photos and videos the user explicitly selects. Photo data is not uploaded, sold, tracked, or shared.

Diagnostics/analytics: None found in the app code.

Networking: No network calls found in the app code.

## Fields Still Needed

- Support URL: https://kyter.com/snipsnaps/support/
- Marketing URL, optional
- Privacy Policy URL: https://kyter.com/snipsnaps/privacy/
- Terms URL, optional: https://kyter.com/snipsnaps/terms/
- Hosted support page URL
- Copyright holder
- App Store Connect API Key ID
- App Store Connect Issuer ID
- App Store app record ID, if already created

Public privacy, support, and terms pages were added to the Kyter website repo under `src/pages/snipsnaps/`.
