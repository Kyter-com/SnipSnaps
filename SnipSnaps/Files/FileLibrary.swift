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
    let accessErrorCount: Int

    static let empty = ScanResult(items: [], truncated: false, accessErrorCount: 0)
  }

  private static let resourceKeys: Set<URLResourceKey> = [
    .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey, .creationDateKey,
    .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
    .isPackageKey, .contentTypeKey,
    .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
  ]

  private final class AccessErrorCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var rawCount = 0

    var count: Int {
      lock.lock()
      defer { lock.unlock() }
      return rawCount
    }

    func increment() {
      lock.lock()
      rawCount += 1
      lock.unlock()
    }
  }

  static func scan(
    folders: [URL],
    category: FileReviewCategory,
    limit: Int,
    excluding reviewed: Set<String> = [],
    excludedFolderPaths: Set<String> = [],
    sort: FileSortOption = .largest
  ) -> ScanResult {
    if category == .duplicates {
      return duplicateRedundantCopies(
        folders: folders,
        excluding: reviewed,
        excludedFolderPaths: excludedFolderPaths,
        limit: limit,
        sort: sort
      )
    }

    let oldCutoff = Calendar.current.date(byAdding: .day, value: -oldFileAgeDays, to: Date()) ?? .distantPast
    var items: [FileItem] = []
    var seen = Set<String>()
    var examined = 0
    var truncated = false
    var accessErrorCount = 0

    folderLoop: for folder in folders {
      guard !isExcluded(folder, excludedFolderPaths: excludedFolderPaths) else { continue }
      guard let (enumerator, errors) = enumerator(for: folder) else {
        accessErrorCount += 1
        continue
      }
      defer { accessErrorCount += errors.count }
      for case let url as URL in enumerator {
        if Task.isCancelled { return .empty }
        if isExcluded(url, excludedFolderPaths: excludedFolderPaths) {
          enumerator.skipDescendants()
          continue
        }
        // Count every enumerated entry (files, directories, skipped placeholders)
        // so a directory-heavy or all-iCloud tree still trips the cap instead of
        // looping for a very long time without ever reaching it.
        if examined >= maxFilesExamined { truncated = true; break folderLoop }
        examined += 1
        guard let item = makeItem(url) else { continue }
        guard seen.insert(dedupKey(item.url)).inserted else { continue }
        if matches(item, category: category, oldCutoff: oldCutoff), !reviewed.contains(item.url.path) {
          items.append(item)
        }
      }
    }

    return ScanResult(items: Array(sortItems(items, by: sort).prefix(limit)), truncated: truncated, accessErrorCount: accessErrorCount)
  }

  // Single-pass tally for the category cards: total and not-yet-reviewed per
  // category (duplicates is scan-on-demand, so it is omitted here).
  static func counts(
    folders: [URL],
    reviewedPaths reviewed: Set<String>,
    excludedFolderPaths: Set<String> = []
  ) -> FileCountsResult {
    let oldCutoff = Calendar.current.date(byAdding: .day, value: -oldFileAgeDays, to: Date()) ?? .distantPast
    var total: [FileReviewCategory: Int] = [:]
    var fresh: [FileReviewCategory: Int] = [:]
    var seen = Set<String>()
    var examined = 0
    var truncated = false
    var accessErrorCount = 0

    folderLoop: for folder in folders {
      guard !isExcluded(folder, excludedFolderPaths: excludedFolderPaths) else { continue }
      guard let (enumerator, errors) = enumerator(for: folder) else {
        accessErrorCount += 1
        continue
      }
      defer { accessErrorCount += errors.count }
      for case let url as URL in enumerator {
        if Task.isCancelled { break folderLoop }
        if isExcluded(url, excludedFolderPaths: excludedFolderPaths) {
          enumerator.skipDescendants()
          continue
        }
        // Cap is global across all granted folders, not per-folder, so a labeled
        // break is required (a bare break would only end this folder's loop). Count
        // every enumerated entry so a directory-heavy tree still trips the cap.
        if examined >= maxFilesExamined { truncated = true; break folderLoop }
        examined += 1
        guard let item = makeItem(url) else { continue }
        // Skip files already tallied via an overlapping grant so the cards don't
        // double-count the same physical file.
        guard seen.insert(dedupKey(item.url)).inserted else { continue }
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
    return FileCountsResult(counts: result, truncated: truncated, accessErrorCount: accessErrorCount)
  }

  // Exact-content duplicates: bucket by size, hash only collision buckets, then
  // surface the redundant copies (every copy except the oldest "original" in
  // each identical group). Unique file sizes never get hashed.
  static func duplicateRedundantCopies(
    folders: [URL],
    excluding reviewed: Set<String>,
    excludedFolderPaths: Set<String> = [],
    limit: Int,
    sort: FileSortOption = .largest
  ) -> ScanResult {
    var bySize: [Int64: [FileItem]] = [:]
    var seen = Set<String>()
    var examined = 0
    var truncated = false
    var accessErrorCount = 0
    folderLoop: for folder in folders {
      guard !isExcluded(folder, excludedFolderPaths: excludedFolderPaths) else { continue }
      guard let (enumerator, errors) = enumerator(for: folder) else {
        accessErrorCount += 1
        continue
      }
      defer { accessErrorCount += errors.count }
      for case let url as URL in enumerator {
        if Task.isCancelled { return .empty }
        if isExcluded(url, excludedFolderPaths: excludedFolderPaths) {
          enumerator.skipDescendants()
          continue
        }
        if examined >= maxFilesExamined { truncated = true; break folderLoop }
        examined += 1
        // Bucket by logical byte length, not allocated size: identical files on
        // volumes with different block sizes share a logical size but not an
        // allocated one, and must still be compared.
        guard let item = makeItem(url), item.logicalSize > 0 else { continue }
        // Dedup by real path BEFORE bucketing: a file reachable through two
        // overlapping grants would otherwise hash-match itself and be surfaced as a
        // redundant copy — trashing it would delete the only copy of a unique file.
        guard seen.insert(dedupKey(item.url)).inserted else { continue }
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
    return ScanResult(items: Array(sortItems(redundant, by: sort).prefix(limit)), truncated: truncated, accessErrorCount: accessErrorCount)
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
    let failed: [FileItem]
    // The files' real locations inside ~/.Trash, as reported by trashItem — used
    // to reveal them in Finder, since the sandbox hides the real Trash path.
    let trashedURLs: [URL]
  }

  struct FolderTrashResult: Sendable {
    let trashedURL: URL?
    let freedBytes: Int64
    let errorMessage: String?

    var succeeded: Bool { trashedURL != nil && errorMessage == nil }
  }

  static func moveToTrash(_ items: [FileItem]) -> TrashResult {
    let fm = FileManager.default
    var trashed = 0
    var freed: Int64 = 0
    var failed: [FileItem] = []
    var trashedURLs: [URL] = []
    for item in items {
      var resultingURL: NSURL?
      do {
        try fm.trashItem(at: item.url, resultingItemURL: &resultingURL)
        trashed += 1
        freed += item.size
        if let resultingURL { trashedURLs.append(resultingURL as URL) }
      } catch {
        failed.append(item)
      }
    }
    return TrashResult(trashed: trashed, freedBytes: freed, failed: failed, trashedURLs: trashedURLs)
  }

  static func moveFolderToTrash(_ folder: URL) -> FolderTrashResult {
    let standardized = folder.standardizedFileURL
    guard let values = try? standardized.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
          values.isDirectory == true,
          values.isSymbolicLink != true else {
      return FolderTrashResult(
        trashedURL: nil,
        freedBytes: 0,
        errorMessage: "The selected folder is no longer available."
      )
    }

    var resultingURL: NSURL?
    do {
      try FileManager.default.trashItem(at: standardized, resultingItemURL: &resultingURL)
      guard let trashedURL = resultingURL as URL? else {
        return FolderTrashResult(
          trashedURL: nil,
          freedBytes: 0,
          errorMessage: "macOS moved the folder but didn't return its Trash location."
        )
      }
      return FolderTrashResult(
        trashedURL: trashedURL,
        freedBytes: allocatedSize(of: trashedURL),
        errorMessage: nil
      )
    } catch {
      return FolderTrashResult(
        trashedURL: nil,
        freedBytes: 0,
        errorMessage: error.localizedDescription
      )
    }
  }

  // MARK: - Private

  private static func enumerator(for folder: URL) -> (FileManager.DirectoryEnumerator, AccessErrorCounter)? {
    let errors = AccessErrorCounter()
    guard let enumerator = FileManager.default.enumerator(
      at: folder,
      includingPropertiesForKeys: Array(resourceKeys),
      options: [.skipsHiddenFiles, .skipsPackageDescendants],
      errorHandler: { _, _ in
        errors.increment()
        return true
      }
    ) else { return nil }
    return (enumerator, errors)
  }

  // Stable per-pass identity for a file. Standardizing collapses the path so a file
  // reachable through overlapping grants (e.g. both ~/Downloads and
  // ~/Downloads/installers are granted) resolves to one key — otherwise the same
  // physical file is enumerated twice, inflating counts and, worse, colliding with
  // itself in duplicate detection so its only copy gets offered for trashing.
  private static func dedupKey(_ url: URL) -> String {
    url.standardizedFileURL.path
  }

  private static func isExcluded(_ url: URL, excludedFolderPaths: Set<String>) -> Bool {
    guard !excludedFolderPaths.isEmpty else { return false }
    let path = url.standardizedFileURL.path
    return excludedFolderPaths.contains { excludedPath in
      path == excludedPath || path.hasPrefix(excludedPath == "/" ? "/" : excludedPath + "/")
    }
  }

  private static func allocatedSize(of folder: URL) -> Int64 {
    let keys: [URLResourceKey] = [
      .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey
    ]
    guard let enumerator = FileManager.default.enumerator(
      at: folder,
      includingPropertiesForKeys: keys,
      options: [],
      errorHandler: { _, _ in true }
    ) else {
      return 0
    }

    var total: Int64 = 0
    for case let url as URL in enumerator {
      if Task.isCancelled { break }
      guard let values = try? url.resourceValues(forKeys: Set(keys)),
            values.isRegularFile == true else {
        continue
      }
      total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }
    return total
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
