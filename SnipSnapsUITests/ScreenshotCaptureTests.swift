#if os(iOS)
import XCTest
import UIKit

/// Drives the real SnipSnaps app through each marketing screen and attaches
/// a screenshot of every state to the test result so the host can extract them
/// from the xcresult bundle.
///
/// Run with:
///   xcodebuild -project SnipSnaps.xcodeproj -scheme SnipSnaps \
///     -destination 'id=<sim-id>' \
///     -only-testing:SnipSnapsUITests/ScreenshotCaptureTests/testCaptureAllScreens \
///     -resultBundlePath /tmp/SnipSnapsScreenshots.xcresult test
///
/// Then extract attachments with marketing/app-store-screenshots/extract-shots.sh.
///
/// Conventions:
/// - Every step calls capture(name:) which attaches a PNG named like "01-home".
/// - The test never fails mid-flow; it always continues so partial captures land.
final class ScreenshotCaptureTests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = true
  }

  @MainActor
  func testCaptureAllScreens() throws {
    let app = XCUIApplication()
    app.launch()

    // Wait for home
    let homeTitle = app.staticTexts["SnipSnaps"].firstMatch
    _ = homeTitle.waitForExistence(timeout: 12)

    // Grant Photos access. `simctl privacy grant photos` does NOT stick on
    // iOS 26.x (tccd keeps serving its own value), so a fresh sim always shows
    // the system permission dialog. The app surfaces an "Enable Photo Access"
    // button when not-determined and also auto-requests on appear, so the
    // SpringBoard alert can show up either on its own or after a tap — and the
    // timing races. Poll for up to ~15s: tap the in-app button if it's there,
    // and tap "Allow Full Access" the moment the alert appears.
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let enableButton = app.buttons["Enable Photo Access"].firstMatch
    func allowFullAccess() -> XCUIElement {
      let exact = springboard.buttons["Allow Full Access"].firstMatch
      if exact.exists { return exact }
      return springboard.buttons.matching(
        NSPredicate(format: "label CONTAINS[c] 'Full Access' OR label BEGINSWITH[c] 'Allow'")
      ).firstMatch
    }
    for _ in 0..<15 {
      let allow = allowFullAccess()
      if allow.exists { allow.tap(); break }
      if enableButton.exists { enableButton.tap() }
      sleep(1)
    }
    sleep(2)

    sleep(1)
    capture("01-home")

    // ---- Similar (must run BEFORE the Today review) --------------------
    // "Similar" is in the "Space Savers" section near the bottom of the home
    // list, so scroll it into view first. The card is one button labelled
    // "Similar" (older builds exposed it as a static text). This has to happen
    // before any review below: once photos are reviewed, their near-duplicate
    // groups are remembered and skipped, leaving "No Similar Photos Found".
    let similarButton = app.buttons["Similar"].firstMatch
    let similarText = app.staticTexts["Similar"].firstMatch
    var scrollTries = 0
    while !(similarButton.exists || similarText.exists) && scrollTries < 6 {
      app.swipeUp()
      scrollTries += 1
      usleep(500_000)
    }
    let similarCard = similarButton.exists ? similarButton : similarText
    if similarCard.exists {
      var hitTries = 0
      while !similarCard.isHittable && hitTries < 4 {
        app.swipeUp()
        hitTries += 1
        usleep(400_000)
      }
      similarCard.tap()
    }
    let closeSimilar = app.buttons["Close similar review"].firstMatch
    _ = closeSimilar.waitForExistence(timeout: 12)
    sleep(4)  // give the hashing/grouping pass a moment to finish
    capture("03-similar")
    if closeSimilar.exists {
      closeSimilar.tap()
      sleep(1)
    }

    // Scroll the home list back to the top so "Today" is reachable again.
    _ = homeTitle.waitForExistence(timeout: 6)
    var topTries = 0
    while !app.staticTexts["Today"].firstMatch.isHittable && topTries < 6 {
      app.swipeDown()
      topTries += 1
      usleep(400_000)
    }

    // ---- Today → review ------------------------------------------------
    let todayCard = app.staticTexts["Today"].firstMatch
    if todayCard.waitForExistence(timeout: 5) {
      todayCard.tap()
    }
    // Reliable waypoint: the toolbar "Close review" button is unique to the
    // running review session.
    let closeReview = app.buttons["Close review"].firstMatch
    _ = closeReview.waitForExistence(timeout: 8)
    sleep(2)  // let the photo render
    capture("02-review")

    // ---- Details (tap the date+size info pill) -------------------------
    // The whole pill is one Button whose label concatenates date + size + info icon.
    // Easiest: find a button label that contains "MB" or "KB".
    // Advance past the first photo so the photo behind the details sheet has
    // no high-contrast linework that bleeds through the .ultraThinMaterial.
    // We tap "Keep photo" twice to land on a cleaner-looking shot.
    let keepFirst = app.buttons["Keep photo"].firstMatch
    if keepFirst.waitForExistence(timeout: 3) {
      keepFirst.tap()
      usleep(450_000)
      if keepFirst.exists {
        keepFirst.tap()
        usleep(450_000)
      }
    }

    let storageButton = app.buttons.matching(
      NSPredicate(format: "label CONTAINS[c] ' MB' OR label CONTAINS[c] ' KB' OR label CONTAINS[c] ' bytes'")
    ).firstMatch
    if storageButton.waitForExistence(timeout: 3) {
      storageButton.tap()
    }

    // Get the details sheet showing the full metadata list + the Location map.
    // On iPhone the sheet opens at .medium, so drag its nav-bar chrome up to the
    // .large detent (a plain swipeUp() would scroll the Form instead of raising
    // the sheet). On iPad the app presents it as a page-size sheet that already
    // shows the whole list, so no gesture is needed.
    if UIDevice.current.userInterfaceIdiom != .pad {
      let detailsNav = app.navigationBars["Photo Details"].firstMatch
      let dragStart = detailsNav.waitForExistence(timeout: 3)
        ? detailsNav.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        : app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      let dragEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
      dragStart.press(forDuration: 0.15, thenDragTo: dragEnd)
    }

    // Let the MapKit tiles in the Location section fetch over the network — they
    // render as a blank grid until they arrive, so a short wait would capture an
    // empty map.
    sleep(8)
    capture("04-details")

    // Dismiss details (sheet has a "Done" button at top-trailing)
    let detailsDone = app.buttons["Done"].firstMatch
    if detailsDone.exists {
      detailsDone.tap()
      sleep(1)
    } else {
      // Sheet swipe-down fallback
      app.swipeDown()
      sleep(1)
    }

    // ---- Mark some photos and surface summary --------------------------
    // Tap the photo card to advance using swipes, alternating keep/skip.
    // The two decision buttons are labelled by accessibility:
    //   "Keep this photo" / "Mark for deletion".
    let keep = app.buttons["Keep photo"].firstMatch
    let skip = app.buttons["Delete photo"].firstMatch
    // Review limit defaults to 20 — loop a bit higher and short-circuit when
    // the decision buttons disappear (which happens once the summary takes over).
    let summaryTitle = app.staticTexts["Review complete"].firstMatch
    for i in 0..<25 {
      if summaryTitle.exists { break }
      let button = (i % 2 == 0) ? skip : keep
      if !button.exists { break }
      button.tap()
      usleep(350_000)
    }
    _ = summaryTitle.waitForExistence(timeout: 8)
    sleep(2)
    capture("05-summary")

    // Back to home. With photos marked, the summary's primary button is
    // "Delete N" (not "Done"), so dismiss via the top-left X — which is
    // labelled "Close without deleting" while the summary is showing.
    let summaryClose = app.buttons["Close without deleting"].firstMatch
    if summaryClose.exists {
      summaryClose.tap()
    } else if app.buttons["Done"].firstMatch.exists {
      app.buttons["Done"].firstMatch.tap()  // shown only when nothing is marked
    } else if app.buttons["Close review"].firstMatch.exists {
      app.buttons["Close review"].firstMatch.tap()
    }
    sleep(1)

    // ---- Settings ------------------------------------------------------
    navigateToSettingsAndCapture(in: app)
  }

  /// Focused path for refreshing the Settings marketing slide without driving
  /// every photo-review state first. It still launches the production app,
  /// handles the real Photos permission dialog, and verifies navigation before
  /// saving so a missed tab tap cannot be mislabeled as Settings.
  @MainActor
  func testCaptureSettingsScreen() throws {
    let app = XCUIApplication()
    app.launch()

    let homeTitle = app.staticTexts["SnipSnaps"].firstMatch
    _ = homeTitle.waitForExistence(timeout: 12)

    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let enableButton = app.buttons["Enable Photo Access"].firstMatch
    for _ in 0..<15 {
      let exactAllow = springboard.buttons["Allow Full Access"].firstMatch
      let fallbackAllow = springboard.buttons.matching(
        NSPredicate(format: "label CONTAINS[c] 'Full Access' OR label BEGINSWITH[c] 'Allow'")
      ).firstMatch
      let allow = exactAllow.exists ? exactAllow : fallbackAllow
      if allow.exists {
        allow.tap()
        break
      }
      if enableButton.exists {
        enableButton.tap()
      }
      sleep(1)
    }
    sleep(2)

    navigateToSettingsAndCapture(in: app)
  }

  // MARK: - Helpers

  @MainActor
  private func navigateToSettingsAndCapture(in app: XCUIApplication) {
    // iPhone shows the tabs in a bottom tab bar; on iPad the same TabView
    // renders as a floating tab bar at the top that isn't exposed under
    // `tabBars`, so fall back to a plain button query for the "Settings" tab.
    let settingsTab = app.tabBars.buttons["Settings"].firstMatch
    if settingsTab.waitForExistence(timeout: 4) {
      settingsTab.tap()
    } else {
      let settingsButton = app.buttons["Settings"].firstMatch
      if settingsButton.waitForExistence(timeout: 4) {
        settingsButton.tap()
      }
    }

    let settingsTitle = app.navigationBars["Settings"].firstMatch
    XCTAssertTrue(
      settingsTitle.waitForExistence(timeout: 4),
      "Settings must be visible before capturing 06-settings"
    )
    guard settingsTitle.exists else { return }
    sleep(1)
    capture("06-settings")
  }

  /// Take a full-screen screenshot and attach it with a stable name so the
  /// host extraction script can find it inside the xcresult bundle.
  @MainActor
  private func capture(_ name: String) {
    let screenshot = XCUIScreen.main.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
#endif
