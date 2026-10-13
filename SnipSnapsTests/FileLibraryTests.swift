#if os(macOS)
import XCTest
@testable import SnipSnaps

final class FileLibraryTests: XCTestCase {
  func testLimitedScansMatchFullRankingForEverySortAndCategory() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let nested = root.appendingPathComponent("Nested", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    let oldDate = Date(timeIntervalSince1970: 1_600_000_000)
    for i in 0..<67 {
      let directory = i.isMultiple(of: 2) ? nested : root
      let url = directory.appendingPathComponent("Screenshot \((i * 31) % 67).png")
      // Distinct allocated sizes and repeated dates exercise both rankings
      // and stable ties; numbered names exercise natural (2 before 10) sorting.
      try Data(repeating: UInt8(i), count: (i + 1) * 4096).write(to: url)
      try FileManager.default.setAttributes(
        [.modificationDate: oldDate.addingTimeInterval(Double(i / 3))],
        ofItemAtPath: url.path
      )
    }
    // Review history records the enumerated URL's path (which can differ
    // from the fixture URL through macOS's /var -> /private/var alias).
    let firstScan = FileLibrary.scan(folders: [root], category: .everything, limit: 100)
    let reviewed = Set(firstScan.items.filter { $0.name == "Screenshot 0.png" }.map { $0.url.path })
    XCTAssertEqual(reviewed.count, 1)
    for category in [FileReviewCategory.everything, .old, .screenshots] {
      for sort in FileSortOption.allCases {
        let full = FileLibrary.scan(
          folders: [root, nested], category: category, limit: 100,
          excluding: reviewed, sort: sort
        )
        XCTAssertEqual(full.items.count, 66)
        for limit in [1, 5, 20, 66, 100] {
          let batch = FileLibrary.scan(
            folders: [root, nested], category: category, limit: limit,
            excluding: reviewed, sort: sort
          )
          XCTAssertEqual(batch.items, Array(full.items.prefix(limit)), "\(category), \(sort), limit \(limit)")
          XCTAssertFalse(batch.truncated)
          XCTAssertEqual(batch.accessErrorCount, 0)
        }
      }
    }
    let names = FileLibrary.scan(folders: [root], category: .everything, limit: 3, sort: .name)
    XCTAssertEqual(names.items.map(\.name), ["Screenshot 0.png", "Screenshot 1.png", "Screenshot 2.png"])
    let sizes = FileLibrary.scan(folders: [root], category: .everything, limit: 3, sort: .largest)
    XCTAssertEqual(sizes.items.map(\.logicalSize), [67, 66, 65].map { Int64($0 * 4096) })
  }

  func testNonpositiveReviewLimitsAreEmpty() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("same".utf8).write(to: root.appendingPathComponent("first.txt"))
    try Data("same".utf8).write(to: root.appendingPathComponent("second.txt"))
    for limit in [0, -1] {
      for category in FileReviewCategory.allCases {
        XCTAssertTrue(FileLibrary.scan(folders: [root], category: category, limit: limit).items.isEmpty)
      }
    }
  }

  func testEnumerationStillSkipsHiddenFilesPackagesAndSymlinks() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let package = root.appendingPathComponent("Example.app", isDirectory: true)
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    try Data("inside".utf8).write(to: package.appendingPathComponent("contents.txt"))
    try Data("hidden".utf8).write(to: root.appendingPathComponent(".hidden"))
    let visible = root.appendingPathComponent("visible.txt")
    try Data("visible".utf8).write(to: visible)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.txt"), withDestinationURL: visible)
    let scan = FileLibrary.scan(folders: [root], category: .everything, limit: 20)
    XCTAssertEqual(scan.items.map(\.name), ["visible.txt"])
    XCTAssertEqual(FileLibrary.counts(folders: [root], reviewedPaths: []).counts[.everything]?.total, 1)
  }

  func testDuplicateBatchContainsOnlyRedundantUnreviewedCopies() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    for i in 0..<5 {
      try Data("identical bytes".utf8).write(to: root.appendingPathComponent("copy-\(i).txt"))
    }
    try Data("unique contents".utf8).write(to: root.appendingPathComponent("unique.txt"))
    let all = FileLibrary.scan(folders: [root, root], category: .duplicates, limit: 20, sort: .name)
    XCTAssertEqual(all.items.count, 4)
    XCTAssertFalse(all.items.contains { $0.name == "unique.txt" })
    let reviewed = Set(all.items.prefix(2).map { $0.url.path })
    let batch = FileLibrary.scan(folders: [root, root], category: .duplicates, limit: 1, excluding: reviewed, sort: .name)
    XCTAssertEqual(batch.items, Array(all.items.dropFirst(2).prefix(1)))
  }

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
