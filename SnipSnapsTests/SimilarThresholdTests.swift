import XCTest
@testable import SnipSnaps

final class SimilarThresholdTests: XCTestCase {
  func testDefaultIsTheBalancedDetent() {
    XCTAssertEqual(SimilarThreshold.defaultValue, 0.35, accuracy: 0.0001)
    XCTAssertEqual(SimilarThreshold.presetName(for: SimilarThreshold.defaultValue), "Balanced")
  }

  func testRangeContainsAllDetents() {
    for detent in SimilarThreshold.detents {
      XCTAssertTrue(
        SimilarThreshold.range.contains(detent),
        "Detent \(detent) falls outside the slider range"
      )
    }
  }

  func testPresetNamesSplitAtDetentMidpoints() {
    XCTAssertEqual(SimilarThreshold.presetName(for: 0.28), "Strict")
    XCTAssertEqual(SimilarThreshold.presetName(for: 0.30), "Strict")
    XCTAssertEqual(SimilarThreshold.presetName(for: 0.324), "Strict")
    XCTAssertEqual(SimilarThreshold.presetName(for: 0.325), "Balanced")
    XCTAssertEqual(SimilarThreshold.presetName(for: 0.35), "Balanced")
    XCTAssertEqual(SimilarThreshold.presetName(for: 0.375), "Balanced")
    XCTAssertEqual(SimilarThreshold.presetName(for: 0.376), "Loose")
    XCTAssertEqual(SimilarThreshold.presetName(for: 0.40), "Loose")
    XCTAssertEqual(SimilarThreshold.presetName(for: 0.42), "Loose")
  }

  func testPresetNamesMatchDetents() {
    // presetName subscripts presetNames by detent index, so the two arrays
    // must stay in lockstep or a future edit could crash.
    XCTAssertEqual(SimilarThreshold.presetNames.count, SimilarThreshold.detents.count)
  }

  func testClampedCorralsOutOfRangeValues() {
    XCTAssertEqual(SimilarThreshold.clamped(0.28), 0.28)
    XCTAssertEqual(SimilarThreshold.clamped(0.35), 0.35)
    XCTAssertEqual(SimilarThreshold.clamped(0.42), 0.42)
    XCTAssertEqual(SimilarThreshold.clamped(-1.0), 0.28)
    XCTAssertEqual(SimilarThreshold.clamped(5.0), 0.42)
    // In-range float noise from the stepped slider passes through untouched.
    XCTAssertEqual(SimilarThreshold.clamped(0.35000000000000003), 0.35000000000000003)
  }

  func testDetentIndexTracksNearestDetentForHaptics() {
    XCTAssertEqual(SimilarThreshold.detentIndex(for: 0.28), 0)
    XCTAssertEqual(SimilarThreshold.detentIndex(for: 0.30), 0)
    XCTAssertEqual(SimilarThreshold.detentIndex(for: 0.35), 1)
    XCTAssertEqual(SimilarThreshold.detentIndex(for: 0.40), 2)
    XCTAssertEqual(SimilarThreshold.detentIndex(for: 0.42), 2)
    // Midpoint ties resolve toward Balanced so the tick boundary is stable.
    XCTAssertEqual(SimilarThreshold.detentIndex(for: 0.325), 1)
    XCTAssertEqual(SimilarThreshold.detentIndex(for: 0.375), 1)
  }
}
