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

  private func makeTemporaryDirectory() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
#endif
