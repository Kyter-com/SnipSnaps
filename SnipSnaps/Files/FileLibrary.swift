#if os(macOS)
import Foundation
import UniformTypeIdentifiers
import CryptoKit

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

  static func scan(folders: [URL], category: FileReviewCategory, limit: Int, excluding reviewed: Set<String> = []) -> [FileItem] {
    if category == .duplicates {
      return duplicateRedundantCopies(folders: folders, excluding: reviewed, limit: limit)
    }

    let oldCutoff = Calendar.current.date(byAdding: .day, value: -oldFileAgeDays, to: Date()) ?? .distantPast
    var items: [FileItem] = []
    var examined = 0

    for folder in folders {
      guard let enumerator = enumerator(for: folder) else { continue }
      for case let url as URL in enumerator {
        if examined >= maxFilesExamined { break }
        guard let item = makeItem(url) else { continue }
        examined += 1
        if matches(item, category: category, oldCutoff: oldCutoff), !reviewed.contains(item.url.path) {
          items.append(item)
        }
      }
    }

    return Array(sorted(items, category: category).prefix(limit))
  }

  // Single-pass tally for the category cards: total and not-yet-reviewed per
  // category (duplicates is scan-on-demand, so it is omitted here).
  static func counts(folders: [URL], reviewedPaths reviewed: Set<String>) -> [FileReviewCategory: FileCounts] {
    let oldCutoff = Calendar.current.date(byAdding: .day, value: -oldFileAgeDays, to: Date()) ?? .distantPast
    var total: [FileReviewCategory: Int] = [:]
    var fresh: [FileReviewCategory: Int] = [:]
    var examined = 0

    for folder in folders {
      guard let enumerator = enumerator(for: folder) else { continue }
      for case let url as URL in enumerator {
        if examined >= maxFilesExamined { break }
        guard let item = makeItem(url) else { continue }
        examined += 1
        let notReviewed = !reviewed.contains(item.url.path)
        func bump(_ category: FileReviewCategory) {
          total[category, default: 0] += 1
          if notReviewed { fresh[category, default: 0] += 1 }
        }
        bump(.everything)
        if item.size >= largeFileMinimumBytes { bump(.large) }
        if item.modified < oldCutoff { bump(.old) }
        if item.isScreenshot { bump(.screenshots) }
      }
    }

    var result: [FileReviewCategory: FileCounts] = [:]
    for category in [FileReviewCategory.everything, .large, .old, .screenshots] {
      result[category] = FileCounts(total: total[category] ?? 0, notReviewed: fresh[category] ?? 0)
    }
    return result
  }

  // Exact-content duplicates: bucket by size, hash only collision buckets, then
  // surface the redundant copies (every copy except the oldest "original" in
  // each identical group). Unique file sizes never get hashed.
  static func duplicateRedundantCopies(folders: [URL], excluding reviewed: Set<String>, limit: Int) -> [FileItem] {
    var bySize: [Int64: [FileItem]] = [:]
    var examined = 0
    for folder in folders {
      guard let enumerator = enumerator(for: folder) else { continue }
      for case let url as URL in enumerator {
        if examined >= maxFilesExamined { break }
        guard let item = makeItem(url), item.size > 0 else { continue }
        examined += 1
        bySize[item.size, default: []].append(item)
      }
    }

    var redundant: [FileItem] = []
    for (_, sameSize) in bySize where sameSize.count > 1 {
      var byHash: [String: [FileItem]] = [:]
      for item in sameSize {
        guard let hash = contentHash(item.url) else { continue }
        byHash[hash, default: []].append(item)
      }
      for (_, identical) in byHash where identical.count > 1 {
        let ordered = identical.sorted { $0.created < $1.created }
        for copy in ordered.dropFirst() where !reviewed.contains(copy.url.path) {
          redundant.append(copy)
        }
      }
    }
    return Array(redundant.sorted { $0.size > $1.size }.prefix(limit))
  }

  private static func contentHash(_ url: URL) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
      hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
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
    case .duplicates: return false // handled separately via duplicateRedundantCopies
    }
  }

  private static func sorted(_ items: [FileItem], category: FileReviewCategory) -> [FileItem] {
    switch category {
    case .large:
      return items.sorted { $0.size > $1.size }
    case .old:
      return items.sorted { $0.modified < $1.modified }
    case .everything, .screenshots, .duplicates:
      return items.sorted { $0.modified > $1.modified }
    }
  }
}
#endif
