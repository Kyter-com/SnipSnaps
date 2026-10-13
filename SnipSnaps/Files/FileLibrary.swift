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
    guard limit > 0 else { return .empty }
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
    var batch = RankedBatch(limit: limit, sort: sort)
    let enumeration = enumerateFiles(folders: folders, excludedFolderPaths: excludedFolderPaths) { item in
      if matches(item, category: category, oldCutoff: oldCutoff), !reviewed.contains(item.url.path) {
        batch.insert(item)
      }
    }
    guard !Task.isCancelled else { return .empty }
    return ScanResult(items: batch.sortedItems, truncated: enumeration.truncated, accessErrorCount: enumeration.accessErrorCount)
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
    let enumeration = enumerateFiles(folders: folders, excludedFolderPaths: excludedFolderPaths) { item in
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

    var result: [FileReviewCategory: FileCounts] = [:]
    for category in [FileReviewCategory.everything, .large, .old, .screenshots] {
      result[category] = FileCounts(total: total[category] ?? 0, notReviewed: fresh[category] ?? 0)
    }
    return FileCountsResult(counts: result, truncated: enumeration.truncated, accessErrorCount: enumeration.accessErrorCount)
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
    guard limit > 0 else { return .empty }
    var bySize: [Int64: [FileItem]] = [:]
    let enumeration = enumerateFiles(folders: folders, excludedFolderPaths: excludedFolderPaths) { item in
      // Equal logical lengths may have different allocated sizes across volumes.
      if item.logicalSize > 0 {
        bySize[item.logicalSize, default: []].append(item)
      }
    }
    guard !Task.isCancelled else { return .empty }

    var batch = RankedBatch(limit: limit, sort: sort)
    for (_, sameSize) in bySize where sameSize.count > 1 {
      if Task.isCancelled { return .empty }
      var byHash: [String: [FileItem]] = [:]
      for item in sameSize {
        if Task.isCancelled { return .empty }
        guard let hash = contentHash(item.url) else { continue }
        byHash[hash, default: []].append(item)
      }
      for (_, identical) in byHash where identical.count > 1 {
        let ordered = identical.sorted { $0.created < $1.created }
        for copy in ordered.dropFirst() where !reviewed.contains(copy.url.path) {
          batch.insert(copy)
        }
      }
    }
    return ScanResult(items: batch.sortedItems, truncated: enumeration.truncated, accessErrorCount: enumeration.accessErrorCount)
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

  private static func enumerateFiles(
    folders: [URL],
    excludedFolderPaths: Set<String>,
    visit: (FileItem) -> Void
  ) -> (truncated: Bool, accessErrorCount: Int) {
    var seen = Set<String>()
    var examined = 0
    var truncated = false
    var accessErrorCount = 0
    for folder in folders {
      guard !Task.isCancelled, !truncated else { break }
      guard !isExcluded(folder, excludedFolderPaths: excludedFolderPaths) else { continue }
      guard let (enumerator, errors) = enumerator(for: folder) else {
        accessErrorCount += 1
        continue
      }
      while !Task.isCancelled {
        // Foundation's enumerator and resource lookups create autoreleased
        // objects. Drain them per entry on detached workers instead of keeping
        // an entire tree's temporary metadata alive until the task completes.
        let hasNext = autoreleasepool { () -> Bool in
          guard let url = enumerator.nextObject() as? URL else { return false }
          if isExcluded(url, excludedFolderPaths: excludedFolderPaths) {
            enumerator.skipDescendants()
            return true
          }
          // Bound all entries, including directories and iCloud placeholders.
          if examined >= maxFilesExamined {
            truncated = true
            return false
          }
          examined += 1
          guard let item = makeItem(url) else { return true }
          // Deduplicate overlapping grants BEFORE counting or hashing: a file
          // must never match itself and be offered as a redundant copy.
          guard seen.insert(dedupKey(item.url)).inserted else { return true }
          visit(item)
          return true
        }
        if !hasNext { break }
      }
      accessErrorCount += errors.count
    }
    return (truncated, accessErrorCount)
  }

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

  // Keep only the requested review batch while examining the whole tree. A
  // worst-first heap avoids retaining/sorting up to 200k FileItems to show 20.
  // The traversal cap, exclusions, and global ranking are unchanged. Encounter
  // order breaks ties, preserving the previous stable full-sort behavior.
  private struct RankedBatch {
    private struct Entry {
      let item: FileItem
      let order: Int
    }

    let limit: Int
    let sort: FileSortOption
    private var heap: [Entry] = []
    private var nextOrder = 0

    init(limit: Int, sort: FileSortOption) {
      self.limit = limit
      self.sort = sort
    }

    var sortedItems: [FileItem] {
      heap.sorted(by: precedes).map(\.item)
    }

    mutating func insert(_ item: FileItem) {
      let entry = Entry(item: item, order: nextOrder)
      nextOrder += 1
      if heap.count < limit {
        heap.append(entry)
        var child = heap.count - 1
        while child > 0 {
          let parent = (child - 1) / 2
          guard precedes(heap[parent], heap[child]) else { break }
          heap.swapAt(parent, child)
          child = parent
        }
      } else if precedes(entry, heap[0]) {
        heap[0] = entry
        var parent = 0
        while parent * 2 + 1 < heap.count {
          var worseChild = parent * 2 + 1
          let right = worseChild + 1
          if right < heap.count, precedes(heap[worseChild], heap[right]) {
            worseChild = right
          }
          guard precedes(heap[parent], heap[worseChild]) else { break }
          heap.swapAt(parent, worseChild)
          parent = worseChild
        }
      }
    }

    private func precedes(_ lhs: Entry, _ rhs: Entry) -> Bool {
      switch sort {
      case .largest:
        if lhs.item.size != rhs.item.size { return lhs.item.size > rhs.item.size }
      case .smallest:
        if lhs.item.size != rhs.item.size { return lhs.item.size < rhs.item.size }
      case .recent:
        if lhs.item.modified != rhs.item.modified { return lhs.item.modified > rhs.item.modified }
      case .oldest:
        if lhs.item.modified != rhs.item.modified { return lhs.item.modified < rhs.item.modified }
      case .name:
        let order = lhs.item.name.localizedStandardCompare(rhs.item.name)
        if order != .orderedSame { return order == .orderedAscending }
      }
      return lhs.order < rhs.order
    }
  }
}
#endif
