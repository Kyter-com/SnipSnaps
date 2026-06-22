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

  static func reviewedPaths(memoryOption: ReviewMemoryOption) -> Set<String> {
    guard memoryOption != .never else { return [] }
    if memoryOption == .session {
      sessionLock.lock()
      defer { sessionLock.unlock() }
      return sessionPaths
    }
    return Set(filteredEntries(memoryOption: memoryOption).keys)
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
    var entries = persistentEntries()
    entries[path] = Date().timeIntervalSince1970
    store(entries)
  }

  static func unmarkReviewed(_ path: String, memoryOption: ReviewMemoryOption) {
    guard memoryOption != .never else { return }
    if memoryOption == .session {
      sessionLock.lock()
      sessionPaths.remove(path)
      sessionLock.unlock()
      return
    }
    var entries = persistentEntries()
    entries.removeValue(forKey: path)
    store(entries)
  }

  static func clearAll() {
    sessionLock.lock()
    sessionPaths.removeAll()
    sessionLock.unlock()
    UserDefaults.standard.removeObject(forKey: storeKey)
  }

  static func compact() {
    store(persistentEntries())
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
    let limited = entries
      .filter { $0.value >= cutoff }
      .sorted { $0.value > $1.value }
      .prefix(maxEntries)
    guard !limited.isEmpty else {
      UserDefaults.standard.removeObject(forKey: storeKey)
      return
    }
    UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: limited.map { ($0.key, $0.value) }), forKey: storeKey)
  }
}
#endif
