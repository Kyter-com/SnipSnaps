#if os(macOS)
import XCTest
@testable import SnipSnaps

final class FileLibraryTests: XCTestCase {
  func testDuplicateScanDoesNotSurfaceOverlappingFolderGrantAsDuplicate() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    let nested = root.appendingPathComponent("Nested", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    let uniqueFile = nested.appendingPathComponent("unique.txt")
    try Data("only copy".utf8).write(to: uniqueFile)

    let result = FileLibrary.scan(
      folders: [root, nested],
      category: .duplicates,
      limit: 20,
      sort: .name
    )

    XCTAssertTrue(result.items.isEmpty)
    XCTAssertFalse(result.truncated)
  }

  func testFailedTrashItemsCanBeRetriedByCaller() {
    let missing = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("txt")
    let item = FileItem(
      url: missing,
      size: 42,
      logicalSize: 42,
      modified: Date(),
      created: Date(),
      contentType: .plainText
    )

    let result = FileLibrary.moveToTrash([item])

    XCTAssertEqual(result.trashed, 0)
    XCTAssertEqual(result.freedBytes, 0)
    XCTAssertEqual(result.failed, [item])
  }

  func testExcludedFolderIsSkippedByScansAndCounts() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    let project = root.appendingPathComponent("KeepThisProject", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    try Data("project file".utf8).write(to: project.appendingPathComponent("source.swift"))

    let looseFile = root.appendingPathComponent("review-me.txt")
    try Data("loose file".utf8).write(to: looseFile)
    let excluded = Set([project.standardizedFileURL.path])

    let scan = FileLibrary.scan(
      folders: [root],
      category: .everything,
      limit: 20,
      excludedFolderPaths: excluded,
      sort: .name
    )
    let counts = FileLibrary.counts(
      folders: [root],
      reviewedPaths: [],
      excludedFolderPaths: excluded
    )

    XCTAssertEqual(scan.items.map(\.name), ["review-me.txt"])
    XCTAssertEqual(counts.counts[.everything]?.total, 1)
    XCTAssertEqual(counts.counts[.everything]?.notReviewed, 1)
  }

  func testPersistentReviewHistoryReadsWaitForQueuedWrites() {
    FileReviewHistory.clearAll()
    defer { FileReviewHistory.clearAll() }
    let path = "/tmp/\(UUID().uuidString)"

    FileReviewHistory.markReviewed(path, memoryOption: .forever)
    XCTAssertTrue(FileReviewHistory.reviewedPaths(memoryOption: .forever).contains(path))

    FileReviewHistory.unmarkReviewed(path, memoryOption: .forever)
    XCTAssertFalse(FileReviewHistory.reviewedPaths(memoryOption: .forever).contains(path))

    FileReviewHistory.markReviewed(path, memoryOption: .forever)
    FileReviewHistory.clearAll()
    XCTAssertFalse(FileReviewHistory.reviewedPaths(memoryOption: .forever).contains(path))
  }

  func testSimilarReviewHistoryReadsWaitForQueuedWrites() {
    PhotoReviewHistory.clearAll()
    defer { PhotoReviewHistory.clearAll() }
    let identifier = UUID().uuidString

    PhotoReviewHistory.markSimilarReviewed(identifier, memoryOption: .forever)
    XCTAssertTrue(
      PhotoReviewHistory.similarReviewedIdentifiers(memoryOption: .forever).contains(identifier)
    )

    PhotoReviewHistory.unmarkSimilarReviewed(identifier, memoryOption: .forever)
    XCTAssertFalse(
      PhotoReviewHistory.similarReviewedIdentifiers(memoryOption: .forever).contains(identifier)
    )

    PhotoReviewHistory.markSimilarReviewed(identifier, memoryOption: .forever)
    PhotoReviewHistory.clearAll()
    XCTAssertFalse(
      PhotoReviewHistory.similarReviewedIdentifiers(memoryOption: .forever).contains(identifier)
    )
  }

  func testSharedPhotoReviewHistoryReadsWaitForQueuedWrites() {
    PhotoReviewHistory.clearAll()
    defer { PhotoReviewHistory.clearAll() }
    let identifier = UUID().uuidString

    PhotoReviewHistory.markReviewedIdentifier(identifier, for: .today, memoryOption: .forever)
    XCTAssertTrue(
      PhotoReviewHistory.reviewedIdentifiers(for: .today, memoryOption: .forever).contains(identifier)
    )

    PhotoReviewHistory.unmarkReviewedIdentifier(identifier, for: .today, memoryOption: .forever)
    XCTAssertFalse(
      PhotoReviewHistory.reviewedIdentifiers(for: .today, memoryOption: .forever).contains(identifier)
    )

    PhotoReviewHistory.markReviewedIdentifier(identifier, for: .today, memoryOption: .forever)
    PhotoReviewHistory.clearAll()
    XCTAssertFalse(
      PhotoReviewHistory.reviewedIdentifiers(for: .today, memoryOption: .forever).contains(identifier)
    )
  }

  func testPhotoReviewHistoryFlushPersistsQueuedMutations() {
    PhotoReviewHistory.clearAll()
    defer { PhotoReviewHistory.clearAll() }
    let sharedIdentifier = UUID().uuidString
    let similarIdentifier = UUID().uuidString

    PhotoReviewHistory.markReviewedIdentifier(
      sharedIdentifier,
      for: .today,
      memoryOption: .forever
    )
    PhotoReviewHistory.markSimilarReviewed(similarIdentifier, memoryOption: .forever)
    PhotoReviewHistory.flushStoredHistory()

    XCTAssertNotNil(
      UserDefaults.standard.dictionary(forKey: "reviewedAssetIdentifiers.shared")?[sharedIdentifier]
    )
    XCTAssertNotNil(
      UserDefaults.standard.dictionary(forKey: "reviewedAssetIdentifiers.similar")?[similarIdentifier]
    )

    PhotoReviewHistory.unmarkReviewedIdentifier(
      sharedIdentifier,
      for: .today,
      memoryOption: .forever
    )
    PhotoReviewHistory.unmarkSimilarReviewed(similarIdentifier, memoryOption: .forever)
    PhotoReviewHistory.flushStoredHistory()

    XCTAssertNil(
      UserDefaults.standard.dictionary(forKey: "reviewedAssetIdentifiers.shared")?[sharedIdentifier]
    )
    XCTAssertNil(
      UserDefaults.standard.dictionary(forKey: "reviewedAssetIdentifiers.similar")?[similarIdentifier]
    )
  }

  func testPhotoReviewHistoryClearInvalidatesScheduledWrites() {
    PhotoReviewHistory.clearAll()
    defer { PhotoReviewHistory.clearAll() }

    PhotoReviewHistory.markReviewedIdentifier(
      UUID().uuidString,
      for: .today,
      memoryOption: .forever
    )
    PhotoReviewHistory.markSimilarReviewed(UUID().uuidString, memoryOption: .forever)
    PhotoReviewHistory.clearAll()

    Thread.sleep(forTimeInterval: 0.4)

    XCTAssertNil(UserDefaults.standard.object(forKey: "reviewedAssetIdentifiers.shared"))
    XCTAssertNil(UserDefaults.standard.object(forKey: "reviewedAssetIdentifiers.similar"))
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
#endif
