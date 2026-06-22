#if os(macOS)
import Foundation
import UniformTypeIdentifiers

// On-disk analog of PhotoLibrary: enumerates the user-granted folders, buckets
// files into review categories, and moves confirmed files to the Trash
// (recoverable) — never a permanent delete. All work is value-type based so it
// runs off the main actor.
enum FileLibrary {
  static let largeFileMinimumBytes: Int64 = 50 * 1024 * 1024
  static let oldFileAgeDays = 180
  // Cap enumeration so a huge folder tree can't stall a scan/count indefinitely.
  static let maxFilesExamined = 50_000

  private static let resourceKeys: Set<URLResourceKey> = [
    .fileSizeKey, .contentModificationDateKey, .creationDateKey,
    .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
    .isPackageKey, .contentTypeKey
  ]

  static func scan(folders: [URL], category: FileReviewCategory, limit: Int) -> [FileItem] {
    let oldCutoff = Calendar.current.date(byAdding: .day, value: -oldFileAgeDays, to: Date()) ?? .distantPast
    var items: [FileItem] = []
    var examined = 0

    for folder in folders {
      guard let enumerator = enumerator(for: folder) else { continue }
      for case let url as URL in enumerator {
        if examined >= maxFilesExamined { break }
        guard let item = makeItem(url) else { continue }
        examined += 1
        if matches(item, category: category, oldCutoff: oldCutoff) {
          items.append(item)
        }
      }
    }

    return Array(sorted(items, category: category).prefix(limit))
  }

  // Single-pass tally for the category cards.
  static func counts(folders: [URL]) -> [FileReviewCategory: Int] {
    let oldCutoff = Calendar.current.date(byAdding: .day, value: -oldFileAgeDays, to: Date()) ?? .distantPast
    var counts: [FileReviewCategory: Int] = [:]
    var examined = 0

    for folder in folders {
      guard let enumerator = enumerator(for: folder) else { continue }
      for case let url as URL in enumerator {
        if examined >= maxFilesExamined { break }
        guard let item = makeItem(url) else { continue }
        examined += 1
        counts[.everything, default: 0] += 1
        if item.size >= largeFileMinimumBytes { counts[.large, default: 0] += 1 }
        if item.modified < oldCutoff { counts[.old, default: 0] += 1 }
        if item.isScreenshot { counts[.screenshots, default: 0] += 1 }
      }
    }
    return counts
  }

  struct TrashResult: Sendable {
    let trashed: Int
    let freedBytes: Int64
    let failed: [String]
  }

  static func moveToTrash(_ items: [FileItem]) -> TrashResult {
    let fm = FileManager.default
    var trashed = 0
    var freed: Int64 = 0
    var failed: [String] = []
    for item in items {
      var resultingURL: NSURL?
      do {
        try fm.trashItem(at: item.url, resultingItemURL: &resultingURL)
        trashed += 1
        freed += item.size
      } catch {
        failed.append(item.name)
      }
    }
    return TrashResult(trashed: trashed, freedBytes: freed, failed: failed)
  }

  // MARK: - Private

  private static func enumerator(for folder: URL) -> FileManager.DirectoryEnumerator? {
    FileManager.default.enumerator(
      at: folder,
      includingPropertiesForKeys: Array(resourceKeys),
      options: [.skipsHiddenFiles, .skipsPackageDescendants]
    )
  }

  private static func makeItem(_ url: URL) -> FileItem? {
    guard let rv = try? url.resourceValues(forKeys: resourceKeys) else { return nil }
    // Only loose regular files: skip directories, symlinks, and packages (.app etc).
    guard rv.isRegularFile == true,
          rv.isDirectory != true,
          rv.isSymbolicLink != true,
          rv.isPackage != true else {
      return nil
    }
    let modified = rv.contentModificationDate ?? .distantPast
    return FileItem(
      url: url,
      size: Int64(rv.fileSize ?? 0),
      modified: modified,
      created: rv.creationDate ?? modified,
      contentType: rv.contentType
    )
  }

  private static func matches(_ item: FileItem, category: FileReviewCategory, oldCutoff: Date) -> Bool {
    switch category {
    case .everything: return true
    case .large: return item.size >= largeFileMinimumBytes
    case .old: return item.modified < oldCutoff
    case .screenshots: return item.isScreenshot
    }
  }

  private static func sorted(_ items: [FileItem], category: FileReviewCategory) -> [FileItem] {
    switch category {
    case .large:
      return items.sorted { $0.size > $1.size }
    case .old:
      return items.sorted { $0.modified < $1.modified }
    case .everything, .screenshots:
      return items.sorted { $0.modified > $1.modified }
    }
  }
}
#endif
