#if os(iOS)
import XCTest

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

    // If Photos permission isn't granted yet, walk through the system dialog.
    // (Run once per simulator; subsequent runs see the grant.)
    let enableButton = app.buttons["Enable Photo Access"].firstMatch
    if enableButton.waitForExistence(timeout: 2) {
      enableButton.tap()
      let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
      let allowFull = springboard.buttons["Allow Full Access"].firstMatch
      if allowFull.waitForExistence(timeout: 5) {
        allowFull.tap()
      } else {
        let allowAny = springboard.buttons.matching(
          NSPredicate(format: "label BEGINSWITH[c] 'Allow'")
        ).firstMatch
        if allowAny.exists { allowAny.tap() }
      }
      sleep(2)
    }

    sleep(1)
    capture("01-home")

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
    sleep(2)
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

    // Back to home
    let summaryDone = app.buttons["Done"].firstMatch
    if summaryDone.exists {
      summaryDone.tap()
      sleep(1)
    }

    // ---- Similar -------------------------------------------------------
    _ = homeTitle.waitForExistence(timeout: 6)
    let similarCard = app.staticTexts["Similar"].firstMatch
    if similarCard.waitForExistence(timeout: 4) {
      similarCard.tap()
    }
    // Wait for the similar review nav (its close button has the unique
    // accessibility label "Close similar review").
    let closeSimilar = app.buttons["Close similar review"].firstMatch
    _ = closeSimilar.waitForExistence(timeout: 12)
    sleep(4)  // give the hashing/grouping pass a moment to finish
    capture("03-similar")

    if closeSimilar.exists {
      closeSimilar.tap()
      sleep(1)
    }

    // ---- Settings ------------------------------------------------------
    let settingsTab = app.tabBars.buttons["Settings"].firstMatch
    if settingsTab.waitForExistence(timeout: 4) {
      settingsTab.tap()
    }
    sleep(1)
    capture("06-settings")
  }

  // MARK: - Helpers

  /// Take a full-screen screenshot and attach it with a stable name so the
  /// host extraction script can find it inside the xcresult bundle.
  private func capture(_ name: String) {
    let screenshot = XCUIScreen.main.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
#endif
