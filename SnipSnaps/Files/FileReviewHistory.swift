#if os(macOS)
import Foundation

// On-disk analog of PhotoReviewHistory: remembers which files the user has
// already reviewed so the shared "Remember Reviewed" setting skips them on later
// scans, using the same ReviewMemoryOption windows as the Photos surface.
// Keyed on file path — a moved/renamed file is treated as new, which is the
// pragmatic stable key for loose files.
enum FileReviewHistory {
  private static let storeKey = "fileReviewedPaths"
  private static let maxEntries = 20_000
  private static let maxPersistentAge: TimeInterval = 5 * 365 * 24 * 60 * 60
  private static let sessionLock = NSLock()
  nonisolated(unsafe) private static var sessionPaths: Set<String> = []
  // Serial queue so per-decision persistent writes leave the main actor while
  // staying ordered (a mark and a later unmark must not reorder).
  private static let persistQueue = DispatchQueue(
    label: "com.kyter.SnipSnaps.FileReviewHistory.persist"
  )

  static func reviewedPaths(memoryOption: ReviewMemoryOption) -> Set<String> {
    guard memoryOption != .never else { return [] }
    if memoryOption == .session {
      sessionLock.lock()
      defer { sessionLock.unlock() }
      return sessionPaths
    }
    // Wait for any prior per-swipe writes on the serial queue before reading.
    // Without this barrier, closing and immediately reopening a review could
    // resurface files whose async "reviewed" write had not reached UserDefaults.
    return persistQueue.sync {
      Set(filteredEntries(memoryOption: memoryOption).keys)
    }
  }

  static func hasReviewedPaths() -> Bool {
    sessionLock.lock()
    let hasSessionPaths = !sessionPaths.isEmpty
    sessionLock.unlock()
    return hasSessionPaths || persistQueue.sync { !persistentEntries().isEmpty }
  }

  static func markReviewed(_ path: String, memoryOption: ReviewMemoryOption) {
    guard memoryOption != .never else { return }
    if memoryOption == .session {
      sessionLock.lock()
      sessionPaths.insert(path)
      while sessionPaths.count > maxEntries, let excess = sessionPaths.first {
        sessionPaths.remove(excess)
      }
      sessionLock.unlock()
      return
    }
    // Off the main actor: this fires on every keep/trash decision, and the
    // read/scan path is already async, so the write shouldn't block the review.
    persistQueue.async {
      var entries = persistentEntries()
      entries[path] = Date().timeIntervalSince1970
      store(entries)
    }
  }

  static func unmarkReviewed(_ path: String, memoryOption: ReviewMemoryOption) {
    guard memoryOption != .never else { return }
    if memoryOption == .session {
      sessionLock.lock()
      sessionPaths.remove(path)
      sessionLock.unlock()
      return
    }
    persistQueue.async {
      var entries = persistentEntries()
      entries.removeValue(forKey: path)
      store(entries)
    }
  }

  static func clearAll() {
    sessionLock.lock()
    sessionPaths.removeAll()
    sessionLock.unlock()
    // Order reset after every previously queued mark/unmark so an old async mark
    // cannot finish later and resurrect history the user explicitly cleared.
    persistQueue.sync {
      UserDefaults.standard.removeObject(forKey: storeKey)
    }
  }

  static func compact() {
    persistQueue.async {
      store(persistentEntries())
    }
  }

  // MARK: - Private

  private static func filteredEntries(memoryOption: ReviewMemoryOption) -> [String: TimeInterval] {
    let entries = persistentEntries()
    guard let interval = memoryOption.expirationInterval, interval > 0 else { return entries }
    let cutoff = Date().timeIntervalSince1970 - interval
    return entries.filter { $0.value >= cutoff }
  }

  private static func persistentEntries() -> [String: TimeInterval] {
    guard let dictionary = UserDefaults.standard.dictionary(forKey: storeKey) else { return [:] }
    return dictionary.compactMapValues { value in
      if let number = value as? NSNumber { return number.doubleValue }
      return value as? TimeInterval
    }
  }

  private static func store(_ entries: [String: TimeInterval]) {
    let cutoff = Date().timeIntervalSince1970 - maxPersistentAge
    let filtered = entries.filter { $0.value >= cutoff }
    guard !filtered.isEmpty else {
      UserDefaults.standard.removeObject(forKey: storeKey)
      return
    }
    // Only pay for the O(n log n) sort + trim when actually over the cap; the
    // common per-decision write stays well under maxEntries and skips it.
    let limited: [String: TimeInterval]
    if filtered.count > maxEntries {
      limited = Dictionary(uniqueKeysWithValues:
        filtered.sorted { $0.value > $1.value }.prefix(maxEntries).map { ($0.key, $0.value) })
    } else {
      limited = filtered
    }
    UserDefaults.standard.set(limited, forKey: storeKey)
  }
}
#endif
