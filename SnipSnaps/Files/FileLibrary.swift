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
  // When the cap is hit, callers are told (truncated) so they don't mistake a
  // partial scan for an empty result.
  static let maxFilesExamined = 200_000

  // Outcome of a scan: the ranked items plus whether the file cap was reached.
  struct ScanResult: Sendable {
    let items: [FileItem]
    let truncated: Bool

    static let empty = ScanResult(items: [], truncated: false)
  }

  private static let resourceKeys: Set<URLResourceKey> = [
    .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey, .creationDateKey,
    .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
    .isPackageKey, .contentTypeKey,
    .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
  ]

  static func scan(folders: [URL], category: FileReviewCategory, limit: Int, excluding reviewed: Set<String> = [], sort: FileSortOption = .largest) -> ScanResult {
    if category == .duplicates {
      return duplicateRedundantCopies(folders: folders, excluding: reviewed, limit: limit, sort: sort)
    }

    let oldCutoff = Calendar.current.date(byAdding: .day, value: -oldFileAgeDays, to: Date()) ?? .distantPast
    var items: [FileItem] = []
    var examined = 0
    var truncated = false

    folderLoop: for folder in folders {
      guard let enumerator = enumerator(for: folder) else { continue }
      for case let url as URL in enumerator {
        if Task.isCancelled { return .empty }
        if examined >= maxFilesExamined { truncated = true; break folderLoop }
        guard let item = makeItem(url) else { continue }
        examined += 1
        if matches(item, category: category, oldCutoff: oldCutoff), !reviewed.contains(item.url.path) {
          items.append(item)
        }
      }
    }

    return ScanResult(items: Array(sortItems(items, by: sort).prefix(limit)), truncated: truncated)
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
  static func duplicateRedundantCopies(folders: [URL], excluding reviewed: Set<String>, limit: Int, sort: FileSortOption = .largest) -> ScanResult {
    var bySize: [Int64: [FileItem]] = [:]
    var examined = 0
    var truncated = false
    folderLoop: for folder in folders {
      guard let enumerator = enumerator(for: folder) else { continue }
      for case let url as URL in enumerator {
        if Task.isCancelled { return .empty }
        if examined >= maxFilesExamined { truncated = true; break folderLoop }
        // Bucket by logical byte length, not allocated size: identical files on
        // volumes with different block sizes share a logical size but not an
        // allocated one, and must still be compared.
        guard let item = makeItem(url), item.logicalSize > 0 else { continue }
        examined += 1
        bySize[item.logicalSize, default: []].append(item)
      }
    }

    var redundant: [FileItem] = []
    for (_, sameSize) in bySize where sameSize.count > 1 {
      if Task.isCancelled { return .empty }
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
    return ScanResult(items: Array(sortItems(redundant, by: sort).prefix(limit)), truncated: truncated)
  }

  private static func contentHash(_ url: URL) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    var hasher = SHA256()
    // Read explicitly (not `try?`) so a mid-file read error returns nil rather than
    // hashing partial content — a partial hash could collide falsely.
    do {
      while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
        if Task.isCancelled { return nil }
        hasher.update(data: chunk)
      }
    } catch {
      return nil
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
    // Skip iCloud placeholders that aren't downloaded locally. Enumerating, hashing,
    // or trashing them would force a (potentially multi-GB) download, and they use
    // ~no local disk so they don't belong in a "free up space" review.
    if rv.isUbiquitousItem == true, rv.ubiquitousItemDownloadingStatus == .notDownloaded {
      return nil
    }
    let modified = rv.contentModificationDate ?? .distantPast
    // Prefer the on-disk allocated size so "Large Files" / "space freed" reflect
    // disk actually reclaimed; fall back to the logical size.
    let onDiskSize = rv.totalFileAllocatedSize ?? rv.fileSize ?? 0
    let logical = Int64(rv.fileSize ?? onDiskSize)
    return FileItem(
      url: url,
      size: Int64(onDiskSize),
      logicalSize: logical,
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

  private static func sortItems(_ items: [FileItem], by option: FileSortOption) -> [FileItem] {
    switch option {
    case .largest:
      return items.sorted { $0.size > $1.size }
    case .smallest:
      return items.sorted { $0.size < $1.size }
    case .recent:
      return items.sorted { $0.modified > $1.modified }
    case .oldest:
      return items.sorted { $0.modified < $1.modified }
    case .name:
      return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
  }
}
#endif
