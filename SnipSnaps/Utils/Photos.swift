//
//  Photos.swift
//  SnipSnaps
//
//  Created by Nick Reisenauer on 6/7/25.
//

import Foundation
import Photos
import Vision

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum PhotoLibraryError: LocalizedError {
  case deleteFailed

  var errorDescription: String? {
    switch self {
    case .deleteFailed:
      return "Unable to delete the selected photos."
    }
  }
}

enum SimilarGroupConfidence {
  case burst
  case strong
  case likely

  var title: String {
    switch self {
    case .burst:
      return "Burst"
    case .strong:
      return "Strong"
    case .likely:
      return "Likely"
    }
  }

  var systemImage: String {
    switch self {
    case .burst:
      return "bolt.fill"
    case .strong:
      return "checkmark.seal.fill"
    case .likely:
      return "sparkles"
    }
  }
}

struct SimilarPhotoScanProgress: Equatable {
  enum Phase: String {
    case preparing
    case fingerprinting
    case comparing
    case finishing

    var title: String {
      switch self {
      case .preparing:
        return "Preparing scan"
      case .fingerprinting:
        return "Reading thumbnails"
      case .comparing:
        return "Comparing photos"
      case .finishing:
        return "Finishing scan"
      }
    }
  }

  let phase: Phase
  let completedCount: Int
  let totalCount: Int
  let groupsFound: Int

  var fractionCompleted: Double? {
    guard totalCount > 0 else { return nil }
    return min(max(Double(completedCount) / Double(totalCount), 0), 1)
  }
}

struct SimilarPhotoGroup: Identifiable {
  let assets: [PHAsset]
  let confidence: SimilarGroupConfidence

  init(assets: [PHAsset], confidence: SimilarGroupConfidence = .likely) {
    self.assets = assets
    self.confidence = confidence
  }

  var id: String {
    assets.map(\.localIdentifier).joined(separator: "|")
  }
}

struct ReviewModeCounts {
  let total: Int
  let notReviewed: Int

  var hasReviewMemory: Bool {
    notReviewed != total
  }
}

enum PhotoReviewHistory {
  private static let keyPrefix = "reviewedAssetIdentifiers"
  // Review memory is shared across every review mode: once an asset is reviewed
  // in any category it is skipped in all categories until the memory window
  // elapses. Older builds stored a separate list per mode; those lists are
  // merged into this shared store the first time it is accessed.
  private static let sharedKey = "reviewedAssetIdentifiers.shared"
  private static let legacyModeRawValues = ["recentlyEdited"]
  private static let maxIdentifiers = 20_000
  private static let maxPersistentHistoryAge: TimeInterval = 5 * 365 * 24 * 60 * 60
  private static let sessionLock = NSLock()
  private static let migrationLock = NSLock()
  nonisolated(unsafe) private static var sessionIdentifiers: Set<String> = []
  nonisolated(unsafe) private static var didMigrateLegacyStores = false
  private static let persistentWriteDebounce: DispatchTimeInterval = .milliseconds(250)
  // Persistent review history can contain thousands of identifiers. Keep a
  // queue-confined cache so a swipe only mutates one dictionary entry instead
  // of decoding and rewriting the entire UserDefaults payload. Synchronous
  // reads act as a barrier behind queued marks/unmarks before a new review or
  // count begins.
  private static let sharedPersistQueue = DispatchQueue(
    label: "com.kyter.SnipSnaps.PhotoReviewHistory.sharedPersist"
  )
  nonisolated(unsafe) private static var sharedPersistentCache: [String: TimeInterval]?
  nonisolated(unsafe) private static var sharedPersistGeneration = 0

  // Similar review memory lives in its own namespace, separate from the shared
  // cross-mode store. Keeping it separate means (a) keeping one of two
  // near-duplicates here does not hide that photo from the other cleanup modes,
  // and (b) a photo reviewed in another mode is not silently dropped from a
  // Similar scan, which would otherwise leave its twin without a match and hide
  // the pair entirely.
  private static let similarKey = "reviewedAssetIdentifiers.similar"
  nonisolated(unsafe) private static var similarSessionIdentifiers: Set<String> = []
  // Serial queue for the Similar persistent store so per-swipe writes leave the
  // main actor (mirroring the off-main read path) while staying strictly ordered
  // — a mark followed by an undo's unmark must not reorder.
  private static let similarPersistQueue = DispatchQueue(
    label: "com.kyter.SnipSnaps.PhotoReviewHistory.similarPersist"
  )
  nonisolated(unsafe) private static var similarPersistentCache: [String: TimeInterval]?
  nonisolated(unsafe) private static var similarPersistGeneration = 0

  static func supportsSkipping(for mode: ReviewMode) -> Bool {
    switch mode {
    case .today, .random, .screenshots, .oldScreenshots, .videos, .screenRecordings, .largePhotos, .livePhotos, .bursts, .oldFavorites:
      return true
    // On This Day is a revisit surface, not a cleanup queue: it always
    // resurfaces past-year photos, so it neither skips reviewed items nor
    // records its own. Similar uses its own group-based review flow.
    case .onThisDay, .similar:
      return false
    }
  }

  static func reviewedIdentifiers(for mode: ReviewMode, memoryOption: ReviewMemoryOption) -> Set<String> {
    guard supportsSkipping(for: mode) else { return [] }
    guard memoryOption != .never else { return [] }
    if memoryOption == .session {
      return sessionReviewedIdentifiers()
    }

    return sharedPersistQueue.sync {
      ensureSharedPersistentCacheOnQueue()
      return Set(
        filteredPersistentEntries(
          sharedPersistentCache ?? [:],
          memoryOption: memoryOption
        ).keys
      )
    }
  }

  static func hasReviewedIdentifiers() -> Bool {
    !sessionReviewedIdentifiersAreEmpty()
      || sharedPersistQueue.sync {
        ensureSharedPersistentCacheOnQueue()
        return !(sharedPersistentCache?.isEmpty ?? true)
      }
      || !similarSessionReviewedIdentifiersAreEmpty()
      || similarPersistQueue.sync {
        ensureSimilarPersistentCacheOnQueue()
        return !(similarPersistentCache?.isEmpty ?? true)
      }
  }

  private static func similarSessionReviewedIdentifiersAreEmpty() -> Bool {
    sessionLock.lock()
    defer { sessionLock.unlock() }
    return similarSessionIdentifiers.isEmpty
  }

  static func markReviewed(_ asset: PHAsset, for mode: ReviewMode, memoryOption: ReviewMemoryOption) {
    markReviewedIdentifier(asset.localIdentifier, for: mode, memoryOption: memoryOption)
  }

  static func markReviewedIdentifier(
    _ identifier: String,
    for mode: ReviewMode,
    memoryOption: ReviewMemoryOption
  ) {
    guard supportsSkipping(for: mode) else { return }
    guard memoryOption != .never else { return }
    if memoryOption == .session {
      insertSessionReviewedIdentifier(identifier)
      return
    }

    sharedPersistQueue.async {
      ensureSharedPersistentCacheOnQueue()
      sharedPersistentCache?[identifier] = Date().timeIntervalSince1970
      scheduleSharedPersistOnQueue()
    }
  }

  static func unmarkReviewed(_ asset: PHAsset, for mode: ReviewMode, memoryOption: ReviewMemoryOption) {
    unmarkReviewedIdentifier(asset.localIdentifier, for: mode, memoryOption: memoryOption)
  }

  static func unmarkReviewedIdentifier(
    _ identifier: String,
    for mode: ReviewMode,
    memoryOption: ReviewMemoryOption
  ) {
    guard supportsSkipping(for: mode) else { return }
    guard memoryOption != .never else { return }
    if memoryOption == .session {
      removeSessionReviewedIdentifier(identifier)
      return
    }

    sharedPersistQueue.async {
      ensureSharedPersistentCacheOnQueue()
      sharedPersistentCache?.removeValue(forKey: identifier)
      scheduleSharedPersistOnQueue()
    }
  }

  // Similar mode reviews whole groups rather than single photos, and it does not
  // share the cross-mode store, so it gets its own mark/unmark/read trio keyed by
  // asset identifier. Excluding these on the next scan is what lets a Similar
  // scan reach deeper into the library instead of re-surfacing handled groups.
  static func similarReviewedIdentifiers(memoryOption: ReviewMemoryOption) -> Set<String> {
    guard memoryOption != .never else { return [] }
    if memoryOption == .session {
      sessionLock.lock()
      defer { sessionLock.unlock() }
      return similarSessionIdentifiers
    }
    // Barrier behind any prior per-swipe mark/unmark so a new scan cannot race
    // ahead of the async persistent write and resurface the group just reviewed.
    return similarPersistQueue.sync {
      ensureSimilarPersistentCacheOnQueue()
      return Set(
        filteredPersistentEntries(
          similarPersistentCache ?? [:],
          memoryOption: memoryOption
        ).keys
      )
    }
  }

  static func markSimilarReviewed(_ identifier: String, memoryOption: ReviewMemoryOption) {
    guard memoryOption != .never else { return }
    if memoryOption == .session {
      sessionLock.lock()
      defer { sessionLock.unlock() }
      similarSessionIdentifiers.insert(identifier)
      while similarSessionIdentifiers.count > maxIdentifiers, let excess = similarSessionIdentifiers.first {
        similarSessionIdentifiers.remove(excess)
      }
      return
    }
    // Off the main actor: this fires on every keep/delete swipe and the read
    // path is already detached, so the write shouldn't block the swipe either.
    similarPersistQueue.async {
      ensureSimilarPersistentCacheOnQueue()
      similarPersistentCache?[identifier] = Date().timeIntervalSince1970
      scheduleSimilarPersistOnQueue()
    }
  }

  static func unmarkSimilarReviewed(_ identifier: String, memoryOption: ReviewMemoryOption) {
    guard memoryOption != .never else { return }
    if memoryOption == .session {
      sessionLock.lock()
      defer { sessionLock.unlock() }
      similarSessionIdentifiers.remove(identifier)
      return
    }
    similarPersistQueue.async {
      ensureSimilarPersistentCacheOnQueue()
      similarPersistentCache?.removeValue(forKey: identifier)
      scheduleSimilarPersistOnQueue()
    }
  }

  static func clearAll() {
    clearSessionReviewedIdentifiers()
    // Wait behind queued shared-history writes so an older mark cannot recreate
    // history after the user explicitly resets it.
    sharedPersistQueue.sync {
      sharedPersistGeneration &+= 1
      sharedPersistentCache = [:]
      UserDefaults.standard.removeObject(forKey: sharedKey)
      for mode in ReviewMode.allCases where mode != .similar {
        UserDefaults.standard.removeObject(forKey: key(for: mode))
      }
      clearLegacyModeKeys()
      migrationLock.lock()
      didMigrateLegacyStores = true
      migrationLock.unlock()
    }
    // Order reset after every queued Similar mark/unmark so a stale async mark
    // cannot complete later and recreate history the user explicitly cleared.
    similarPersistQueue.sync {
      similarPersistGeneration &+= 1
      similarPersistentCache = [:]
      UserDefaults.standard.removeObject(forKey: similarKey)
    }
    sessionLock.lock()
    similarSessionIdentifiers.removeAll()
    sessionLock.unlock()
  }

  static func compactStoredHistory() {
    trimSessionReviewedIdentifiers()
    sharedPersistQueue.async {
      sharedPersistGeneration &+= 1
      persistSharedEntriesOnQueue()
    }
    similarPersistQueue.async {
      similarPersistGeneration &+= 1
      persistSimilarEntriesOnQueue()
    }
    trimSimilarSessionReviewedIdentifiers()
  }

  // Scene backgrounding has a limited execution window, so commit the latest
  // cache synchronously rather than waiting for the debounce timer to fire.
  static func flushStoredHistory() {
    trimSessionReviewedIdentifiers()
    sharedPersistQueue.sync {
      sharedPersistGeneration &+= 1
      persistSharedEntriesOnQueue()
    }
    similarPersistQueue.sync {
      similarPersistGeneration &+= 1
      persistSimilarEntriesOnQueue()
    }
    trimSimilarSessionReviewedIdentifiers()
  }

  private static func trimSimilarSessionReviewedIdentifiers() {
    sessionLock.lock()
    while similarSessionIdentifiers.count > maxIdentifiers, let excess = similarSessionIdentifiers.first {
      similarSessionIdentifiers.remove(excess)
    }
    sessionLock.unlock()
  }

  private static func key(for mode: ReviewMode) -> String {
    key(forRawValue: mode.rawValue)
  }

  private static func key(forRawValue rawValue: String) -> String {
    "\(keyPrefix).\(rawValue)"
  }

  private static func clearLegacyModeKeys() {
    for rawValue in legacyModeRawValues {
      UserDefaults.standard.removeObject(forKey: key(forRawValue: rawValue))
    }
  }

  // Callers (reviewedIdentifiers) handle .never and .session before reaching
  // here, so the only options that arrive are .forever (nil interval -> keep
  // everything) and the timed windows (keep entries newer than the cutoff).
  private static func filteredPersistentEntries(
    _ entries: [String: TimeInterval],
    memoryOption: ReviewMemoryOption
  ) -> [String: TimeInterval] {
    guard let expirationInterval = memoryOption.expirationInterval, expirationInterval > 0 else {
      return entries
    }

    let cutoff = Date().timeIntervalSince1970 - expirationInterval
    return entries.filter { $0.value >= cutoff }
  }

  // These helpers are only called on their corresponding serial queues.
  private static func ensureSharedPersistentCacheOnQueue() {
    guard sharedPersistentCache == nil else { return }
    sharedPersistentCache = normalizedPersistentEntries(persistentEntries())
  }

  private static func ensureSimilarPersistentCacheOnQueue() {
    guard similarPersistentCache == nil else { return }
    similarPersistentCache = normalizedPersistentEntries(decodeEntries(forKey: similarKey))
  }

  private static func scheduleSharedPersistOnQueue() {
    sharedPersistGeneration &+= 1
    let generation = sharedPersistGeneration
    sharedPersistQueue.asyncAfter(deadline: .now() + persistentWriteDebounce) {
      guard generation == sharedPersistGeneration else { return }
      persistSharedEntriesOnQueue()
    }
  }

  private static func scheduleSimilarPersistOnQueue() {
    similarPersistGeneration &+= 1
    let generation = similarPersistGeneration
    similarPersistQueue.asyncAfter(deadline: .now() + persistentWriteDebounce) {
      guard generation == similarPersistGeneration else { return }
      persistSimilarEntriesOnQueue()
    }
  }

  private static func persistSharedEntriesOnQueue() {
    ensureSharedPersistentCacheOnQueue()
    sharedPersistentCache = storePersistentEntries(sharedPersistentCache ?? [:])
  }

  private static func persistSimilarEntriesOnQueue() {
    ensureSimilarPersistentCacheOnQueue()
    similarPersistentCache = storePersistentEntries(
      similarPersistentCache ?? [:],
      forKey: similarKey
    )
  }

  private static func persistentEntries() -> [String: TimeInterval] {
    migrateLegacyStoresIfNeeded()
    return decodeEntries(forKey: sharedKey)
  }

  private static func decodeEntries(forKey key: String) -> [String: TimeInterval] {
    if let dictionary = UserDefaults.standard.dictionary(forKey: key) {
      return dictionary.compactMapValues { value in
        if let timestamp = value as? TimeInterval {
          return timestamp
        }
        if let number = value as? NSNumber {
          return number.doubleValue
        }
        return nil
      }
    }

    let legacyIdentifiers = UserDefaults.standard.stringArray(forKey: key) ?? []
    guard !legacyIdentifiers.isEmpty else { return [:] }
    return Dictionary(uniqueKeysWithValues: legacyIdentifiers.map { ($0, Date().timeIntervalSince1970) })
  }

  // Folds any per-mode review lists written by older builds into the shared
  // store so reviewed assets are skipped across every category. Runs once.
  private static func migrateLegacyStoresIfNeeded() {
    migrationLock.lock()
    defer { migrationLock.unlock() }
    guard !didMigrateLegacyStores else { return }
    didMigrateLegacyStores = true

    let defaults = UserDefaults.standard
    var merged = decodeEntries(forKey: sharedKey)
    var didFindLegacy = false

    let legacyKeys = ReviewMode.allCases.map { key(for: $0) }
      + legacyModeRawValues.map { key(forRawValue: $0) }
    // similarKey is byte-for-byte identical to key(for: .similar), so it appears
    // in legacyKeys. It must be excluded here or the migration would fold the
    // live Similar-review store into the shared cross-mode store and delete it.
    for legacyKey in legacyKeys where legacyKey != sharedKey && legacyKey != similarKey {
      let entries = decodeEntries(forKey: legacyKey)
      guard !entries.isEmpty else { continue }
      didFindLegacy = true
      for (identifier, timestamp) in entries {
        merged[identifier] = max(merged[identifier] ?? 0, timestamp)
      }
      defaults.removeObject(forKey: legacyKey)
    }

    guard didFindLegacy else { return }
    storePersistentEntries(merged)
  }

  private static func normalizedPersistentEntries(
    _ entries: [String: TimeInterval]
  ) -> [String: TimeInterval] {
    let cutoff = Date().timeIntervalSince1970 - maxPersistentHistoryAge
    let compactedEntries = entries.filter { $0.value >= cutoff }
    // Only pay for the O(n log n) sort + trim when actually over the cap; the
    // common persistence pass stays well under maxIdentifiers and skips it.
    guard compactedEntries.count > maxIdentifiers else {
      return compactedEntries
    }
    let limitedEntries = compactedEntries.sorted { $0.value > $1.value }.prefix(maxIdentifiers)
    return Dictionary(uniqueKeysWithValues: limitedEntries.map { ($0.key, $0.value) })
  }

  @discardableResult
  private static func storePersistentEntries(
    _ entries: [String: TimeInterval]
  ) -> [String: TimeInterval] {
    storePersistentEntries(entries, forKey: sharedKey)
  }

  @discardableResult
  private static func storePersistentEntries(
    _ entries: [String: TimeInterval],
    forKey key: String
  ) -> [String: TimeInterval] {
    let dictionary = normalizedPersistentEntries(entries)
    guard !dictionary.isEmpty else {
      UserDefaults.standard.removeObject(forKey: key)
      return [:]
    }
    UserDefaults.standard.set(dictionary, forKey: key)
    return dictionary
  }

  private static func sessionReviewedIdentifiers() -> Set<String> {
    sessionLock.lock()
    defer { sessionLock.unlock() }
    return sessionIdentifiers
  }

  private static func sessionReviewedIdentifiersAreEmpty() -> Bool {
    sessionLock.lock()
    defer { sessionLock.unlock() }
    return sessionIdentifiers.isEmpty
  }

  private static func insertSessionReviewedIdentifier(_ identifier: String) {
    sessionLock.lock()
    defer { sessionLock.unlock() }
    sessionIdentifiers.insert(identifier)
    while sessionIdentifiers.count > maxIdentifiers, let excessIdentifier = sessionIdentifiers.first {
      sessionIdentifiers.remove(excessIdentifier)
    }
  }

  private static func removeSessionReviewedIdentifier(_ identifier: String) {
    sessionLock.lock()
    defer { sessionLock.unlock() }
    sessionIdentifiers.remove(identifier)
  }

  private static func clearSessionReviewedIdentifiers() {
    sessionLock.lock()
    defer { sessionLock.unlock() }
    sessionIdentifiers.removeAll()
  }

  private static func trimSessionReviewedIdentifiers() {
    sessionLock.lock()
    defer { sessionLock.unlock() }
    while sessionIdentifiers.count > maxIdentifiers, let excessIdentifier = sessionIdentifiers.first {
      sessionIdentifiers.remove(excessIdentifier)
    }
  }
}

extension Notification.Name {
  // Posted on the main actor whenever the photo library — including the
  // limited-access selection — changes, so count-showing views can refresh
  // without polling and regardless of how the change was made.
  static let snipSnapsPhotoLibraryDidChange = Notification.Name("SnipSnapsPhotoLibraryDidChange")
}

// App-lifetime bridge from PHPhotoLibraryChangeObserver to a main-actor
// notification. A limited user can add photos from several places (Home, Settings,
// the review empty state) without backgrounding the app, so scene/status-based
// refresh alone misses those edits — this catches every selection change. Register
// is idempotent; there's no need to unregister since the single instance lives for
// the whole app.
@MainActor
final class PhotoLibraryChangeBroadcaster: NSObject, PHPhotoLibraryChangeObserver {
  static let shared = PhotoLibraryChangeBroadcaster()
  private var isRegistered = false
  private var debounceTask: Task<Void, Never>?

  func startIfNeeded() {
    guard !isRegistered else { return }
    isRegistered = true
    PHPhotoLibrary.shared().register(self)
  }

  nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
    Task { @MainActor in
      self.scheduleBroadcast()
    }
  }

  // A single edit, an iCloud sync, or a run of in-app delete confirmations can
  // each deliver many rapid change callbacks. Coalesce them so observers recount
  // once per burst rather than once per change — each recount can otherwise kick
  // off a full-library scan.
  private func scheduleBroadcast() {
    debounceTask?.cancel()
    debounceTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(400))
      guard !Task.isCancelled else { return }
      NotificationCenter.default.post(name: .snipSnapsPhotoLibraryDidChange, object: nil)
    }
  }
}

enum PhotoLibrary {
  private static let largePhotoMinimumBytes = 8 * 1024 * 1024
  private static let largePhotoMinimumPixels = 24_000_000
  static let imageManager = PHCachingImageManager()
  nonisolated(unsafe) private static let imageCache: NSCache<NSString, NSObject> = {
    let cache = NSCache<NSString, NSObject>()
    cache.countLimit = 12
    cache.totalCostLimit = 64 * 1024 * 1024
    return cache
  }()
  nonisolated(unsafe) private static let estimatedBytesCache: NSCache<NSString, NSNumber> = {
    let cache = NSCache<NSString, NSNumber>()
    cache.countLimit = 5_000
    return cache
  }()
  static func authorizationStatus() -> PHAuthorizationStatus {
    PHPhotoLibrary.authorizationStatus(for: .readWrite)
  }

  static func requestAuthorization() async -> PHAuthorizationStatus {
    await withCheckedContinuation { continuation in
      PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
        continuation.resume(returning: status)
      }
    }
  }

  static func ensureAuthorization() async -> PHAuthorizationStatus {
    let status = authorizationStatus()
    guard status == .notDetermined else { return status }
    return await requestAuthorization()
  }

  static func canAccessPhotos(_ status: PHAuthorizationStatus) -> Bool {
    status == .authorized || status == .limited
  }

  #if os(iOS)
  // Presents the system limited-library picker so a user in .limited mode can add
  // more photos to the selection SnipSnaps can see. iOS/UIKit only — on macOS the
  // picker doesn't exist, so limited access is managed in System Settings instead.
  // Resolves when the picker is dismissed; the callback reports only newly added
  // identifiers, so callers should re-read the status and refresh regardless.
  @MainActor
  static func presentLimitedLibraryPicker() async {
    guard authorizationStatus() == .limited, let controller = topmostViewController() else { return }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller) { _ in
        continuation.resume()
      }
    }
  }

  @MainActor
  private static func topmostViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    var top = scene?.keyWindow?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
  #endif

  static func fetchAssets(
    for mode: ReviewMode,
    limit: Int,
    screenshotSort: ScreenshotSortOption = .recent,
    videoSort: VideoSortOption = .largest,
    reviewMemory: ReviewMemoryOption = .thirtyDays
  ) -> [PHAsset] {
    let reviewedIdentifiers = PhotoReviewHistory.reviewedIdentifiers(for: mode, memoryOption: reviewMemory)
    let options = PHFetchOptions()
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

    switch mode {
    case .today:
      let calendar = Calendar.current
      let start = calendar.startOfDay(for: Date())
      let end = calendar.date(byAdding: .day, value: 1, to: start) ?? Date()
      options.predicate = NSPredicate(
        format: "creationDate >= %@ AND creationDate < %@",
        start as NSDate,
        end as NSDate
      )
      return fetchAssets(options: options, limit: limit, excluding: reviewedIdentifiers)
    case .onThisDay:
      guard let predicate = onThisDayPredicate() else { return [] }
      options.predicate = predicate
      return fetchAssets(options: options, limit: limit, excluding: reviewedIdentifiers)
    case .screenshots:
      options.predicate = NSPredicate(
        format: "(mediaSubtype & %d) != 0",
        PHAssetMediaSubtype.photoScreenshot.rawValue
      )
      return fetchScreenshotAssets(options: options, sort: screenshotSort, limit: limit, excluding: reviewedIdentifiers)
    case .oldScreenshots:
      let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
      options.predicate = NSPredicate(
        format: "(mediaSubtype & %d) != 0 AND creationDate < %@",
        PHAssetMediaSubtype.photoScreenshot.rawValue,
        cutoff as NSDate
      )
      return fetchScreenshotAssets(options: options, sort: screenshotSort, limit: limit, excluding: reviewedIdentifiers)
    case .videos:
      return fetchVideoAssets(options: options, sort: videoSort, limit: limit, excluding: reviewedIdentifiers)
    case .screenRecordings:
      options.predicate = NSPredicate(
        format: "(mediaSubtype & %d) != 0",
        PHAssetMediaSubtype.videoScreenRecording.rawValue
      )
      return fetchVideoAssets(options: options, sort: videoSort, limit: limit, excluding: reviewedIdentifiers)
    case .largePhotos:
      return fetchLargePhotoAssets(options: options, limit: limit, excluding: reviewedIdentifiers)
    case .livePhotos:
      options.predicate = NSPredicate(
        format: "(mediaSubtype & %d) != 0",
        PHAssetMediaSubtype.photoLive.rawValue
      )
      return fetchAssets(options: options, limit: limit, excluding: reviewedIdentifiers)
    case .bursts:
      return fetchBurstAssets(limit: limit, excluding: reviewedIdentifiers)
    case .oldFavorites:
      let cutoff = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
      options.predicate = NSPredicate(
        format: "favorite == YES AND creationDate < %@",
        cutoff as NSDate
      )
      options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
      return fetchAssets(options: options, limit: limit, excluding: reviewedIdentifiers)
    case .similar:
      return fetchAssets(options: options, limit: limit, excluding: reviewedIdentifiers)
    case .random:
      return fetchRandomAssets(options: options, limit: limit, excluding: reviewedIdentifiers)
    }
  }

  static func fetchTodaysPhotoCount() -> Int {
    fetchCount(for: .today)
  }

  static func fetchCount(for mode: ReviewMode) -> Int {
    fetchCounts(for: mode, reviewMemory: .never).total
  }

  static func fetchCounts(for mode: ReviewMode, reviewMemory: ReviewMemoryOption) -> ReviewModeCounts {
    let options = PHFetchOptions()
    let reviewedIdentifiers = PhotoReviewHistory.reviewedIdentifiers(for: mode, memoryOption: reviewMemory)
    switch mode {
    case .today:
      let calendar = Calendar.current
      let start = calendar.startOfDay(for: Date())
      let end = calendar.date(byAdding: .day, value: 1, to: start) ?? Date()
      options.predicate = NSPredicate(
        format: "creationDate >= %@ AND creationDate < %@",
        start as NSDate,
        end as NSDate
      )
    case .onThisDay:
      options.predicate = onThisDayPredicate()
    case .screenshots:
      options.predicate = NSPredicate(
        format: "(mediaSubtype & %d) != 0",
        PHAssetMediaSubtype.photoScreenshot.rawValue
      )
    case .oldScreenshots:
      let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
      options.predicate = NSPredicate(
        format: "(mediaSubtype & %d) != 0 AND creationDate < %@",
        PHAssetMediaSubtype.photoScreenshot.rawValue,
        cutoff as NSDate
      )
    case .videos:
      break
    case .screenRecordings:
      options.predicate = NSPredicate(
        format: "(mediaSubtype & %d) != 0",
        PHAssetMediaSubtype.videoScreenRecording.rawValue
      )
    case .largePhotos:
      return fetchLargePhotoCounts(excluding: reviewedIdentifiers)
    case .livePhotos:
      options.predicate = NSPredicate(
        format: "(mediaSubtype & %d) != 0",
        PHAssetMediaSubtype.photoLive.rawValue
      )
    case .bursts:
      return fetchBurstAssetCounts(excluding: reviewedIdentifiers)
    case .oldFavorites:
      let cutoff = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
      options.predicate = NSPredicate(
        format: "favorite == YES AND creationDate < %@",
        cutoff as NSDate
      )
    case .similar:
      options.fetchLimit = 1_000
    case .random:
      break
    }
    let result = PHAsset.fetchAssets(with: mode.reviewsVideos ? .video : .image, options: options)
    return counts(from: result, excluding: reviewedIdentifiers)
  }

  // Predicate that excludes a media subtype while still keeping assets whose
  // subtype column is NULL. Photos imported without camera metadata (AirDrop,
  // synced/imported photos, or `simctl addmedia` in the simulator) can have a
  // NULL `mediaSubtype` in the Photos store. The intuitive `(mediaSubtype & N)
  // == 0` filter silently drops every such asset, because `NULL & N == 0`
  // evaluates to NULL (not true) — which is why the Similar/Large-photo scans
  // came back empty in the simulator and would skip imported photos for real
  // users too. The negated form keeps NULL-subtype assets (a missing subtype is
  // not the requested subtype) while still excluding real screenshots.
  static func excludingSubtype(_ subtype: PHAssetMediaSubtype) -> NSPredicate {
    NSPredicate(format: "NOT ((mediaSubtype & %d) == %d)", subtype.rawValue, subtype.rawValue)
  }

  static func fetchSimilarPhotoGroups(
    scanLimit: Int,
    maxGroups: Int,
    sort: SimilarSortOption = .recent,
    reviewedIdentifiers: Set<String> = [],
    progressHandler: ((SimilarPhotoScanProgress) async -> Void)? = nil,
    partialGroupsHandler: (([SimilarPhotoGroup]) async -> Void)? = nil
  ) async -> [SimilarPhotoGroup] {
    let options = PHFetchOptions()
    options.sortDescriptors = [
      NSSortDescriptor(key: "creationDate", ascending: sort == .oldest)
    ]
    options.predicate = excludingSubtype(.photoScreenshot)
    // Mirror the other reviewed-excluding fetch paths (fetchAssets, etc.): only
    // cap the DB fetch when nothing is excluded. Once a reviewed set exists,
    // fetch unbounded (PHFetchResult stays lazy) and collect the newest
    // scanLimit UNREVIEWED assets below — so each scan slides deeper into the
    // library instead of shrinking a fixed newest-scanLimit window, which
    // stranded duplicates past that window on libraries larger than scanLimit.
    let scanCap = max(scanLimit, 1)
    options.fetchLimit = reviewedIdentifiers.isEmpty ? scanCap : 0

    let result = PHAsset.fetchAssets(with: .image, options: options)
    guard result.count > 1 else { return [] }

    // Collect the fetched assets, dropping anything reviewed in a prior Similar
    // session so each scan reaches further into the library instead of
    // re-surfacing groups already handled.
    var assets: [PHAsset] = []
    assets.reserveCapacity(min(result.count, scanCap))
    for index in 0..<result.count {
      guard !Task.isCancelled else { return [] }
      let asset = result.object(at: index)
      guard !reviewedIdentifiers.contains(asset.localIdentifier) else { continue }
      assets.append(asset)
      // Hard cap so the unbounded fetch (used when excluding reviewed) still
      // collects at most scanLimit assets — preserving the single-scan memory
      // and fingerprinting bound the rest of this function relies on.
      if assets.count >= scanCap { break }
    }
    if sort == .random {
      assets.shuffle()
    }
    guard assets.count > 1 else { return [] }

    await progressHandler?(SimilarPhotoScanProgress(
      phase: .preparing,
      completedCount: 0,
      totalCount: assets.count,
      groupsFound: 0
    ))

    // The size-ranked sorts must see every candidate before they can rank, so
    // they run the full scan; every other sort stops as soon as the review batch
    // is full.
    let canStopEarly = sort != .largest && sort != .mostMatches

    var usedIdentifiers = Set<String>()
    let burstGroups = burstSimilarGroups(from: assets, usedIdentifiers: &usedIdentifiers)

    // Online, single-pass clustering. Walk the library in the sorted order,
    // fingerprinting each photo as it is reached and matching it against the
    // anchor of every group seen so far (a lone photo is a one-member group, so
    // pairing up an earlier photo and starting a new group is the same code
    // path as extending an existing one). Because it is incremental, groups
    // stream out as they form and the scan can stop the moment the batch is full
    // — without fingerprinting the rest of the library.
    var clusters: [SimilarPhotoCluster] = []
    // Bounded so a large, visually-similar library can't retain tens of
    // thousands of feature vectors (~100 MB+) for the whole scan and get the
    // app jetsammed. NSCache also drops entries under memory pressure; an evicted
    // anchor's print is simply recomputed on next comparison.
    let featurePrints = NSCache<NSString, VNFeaturePrintObservation>()
    featurePrints.countLimit = 5_000
    var groupCount = burstGroups.count

    func currentGroups() -> [SimilarPhotoGroup] {
      var all = burstGroups
      for cluster in clusters where cluster.isGroup {
        all.append(SimilarPhotoGroup(
          assets: orderSimilarAssetsForReview(cluster.members),
          confidence: similarGroupConfidence(
            hashMatches: cluster.members.count,
            closestHashDistance: cluster.closestHashDistance,
            closestFeatureDistance: cluster.closestFeatureDistance
          )
        ))
      }
      return sortedSimilarGroups(all, sort: sort).prefix(maxGroups).map { $0 }
    }

    if !burstGroups.isEmpty {
      await partialGroupsHandler?(currentGroups())
      if canStopEarly, groupCount >= maxGroups {
        let sortedGroups = currentGroups()
        await progressHandler?(SimilarPhotoScanProgress(
          phase: .finishing,
          completedCount: sortedGroups.count,
          totalCount: max(sortedGroups.count, 1),
          groupsFound: sortedGroups.count
        ))
        return sortedGroups
      }
    }

    for (index, asset) in assets.enumerated() {
      guard !Task.isCancelled else { return currentGroups() }
      let reportProgress = index == 0 || index == assets.count - 1 || index.isMultiple(of: 12)

      guard !usedIdentifiers.contains(asset.localIdentifier) else {
        if reportProgress {
          await progressHandler?(SimilarPhotoScanProgress(
            phase: .comparing, completedCount: index + 1, totalCount: assets.count, groupsFound: groupCount
          ))
        }
        continue
      }

      guard let cgImage = thumbnailCGImage(
        for: asset,
        targetSize: CGSize(width: 18, height: 16),
        deliveryMode: .highQualityFormat
      ), let hash = differenceHash(for: cgImage) else {
        if reportProgress {
          await progressHandler?(SimilarPhotoScanProgress(
            phase: .comparing, completedCount: index + 1, totalCount: assets.count, groupsFound: groupCount
          ))
        }
        continue
      }
      let fingerprint = SimilarPhotoFingerprint(asset: asset, hash: hash, aspectRatio: aspectRatio(for: asset))

      // Match against the anchor of each group seen so far. First match wins,
      // which mirrors the previous seed-and-scan behavior where a group was
      // "every photo similar to its anchor."
      var matchedClusterIndex: Int?
      var matchInfo: (hashDistance: Int, featureDistance: Float)?
      for clusterIndex in clusters.indices {
        // Check often: each comparison can run a Vision feature-print inference,
        // so a coarse stride would delay the user's cancel by seconds.
        if clusterIndex.isMultiple(of: 16), Task.isCancelled {
          return currentGroups()
        }
        if let match = similarMatch(fingerprint, clusters[clusterIndex].anchor, cache: featurePrints) {
          matchedClusterIndex = clusterIndex
          matchInfo = match
          break
        }
      }

      if let clusterIndex = matchedClusterIndex, let match = matchInfo {
        let wasGroup = clusters[clusterIndex].isGroup
        clusters[clusterIndex].add(asset, hashDistance: match.hashDistance, featureDistance: match.featureDistance)
        usedIdentifiers.insert(asset.localIdentifier)
        if !wasGroup { groupCount += 1 }
        // Stream the update for the early-stop sorts only. They hold at most
        // maxGroups groups, so rebuilding is cheap and keeps the live preview
        // fresh and complete — important because tapping "Review found so far"
        // reviews exactly the last streamed set. The size-ranked sorts must scan
        // the whole cap before their ranking is meaningful, so they don't stream
        // partial (still-growing) groups; they emit once, complete, at the end.
        if canStopEarly {
          await partialGroupsHandler?(currentGroups())
        }
      } else {
        clusters.append(SimilarPhotoCluster(anchor: fingerprint))
      }

      if reportProgress {
        await progressHandler?(SimilarPhotoScanProgress(
          phase: .comparing, completedCount: index + 1, totalCount: assets.count, groupsFound: groupCount
        ))
      }
      if canStopEarly, groupCount >= maxGroups {
        break
      }
    }

    let sortedGroups = currentGroups()
    await progressHandler?(SimilarPhotoScanProgress(
      phase: .finishing,
      completedCount: sortedGroups.count,
      totalCount: max(sortedGroups.count, 1),
      groupsFound: sortedGroups.count
    ))
    await partialGroupsHandler?(sortedGroups)
    return sortedGroups
  }

  // Tests one photo against a group's anchor using the same two-stage gate the
  // scan has always used: a cheap structural pre-filter (same shape, roughly
  // similar dHash) followed by the authoritative Vision feature print. The
  // feature print's distances are small — ~0 identical, <= ~0.35 genuinely
  // similar, >= ~0.5 different scenes. dHash alone collides on flat/low-detail
  // photos (sky, walls, dark shots), so a hash-only match is allowed only when
  // the feature print can't be computed and the frames are near-identical.
  private static func similarMatch(
    _ candidate: SimilarPhotoFingerprint,
    _ anchor: SimilarPhotoFingerprint,
    cache: NSCache<NSString, VNFeaturePrintObservation>
  ) -> (hashDistance: Int, featureDistance: Float)? {
    let hashDistance = hammingDistance(candidate.hash, anchor.hash)
    guard abs(candidate.aspectRatio - anchor.aspectRatio) < 0.12, hashDistance <= 14 else {
      return nil
    }
    if let distance = featurePrintDistance(from: anchor.asset, to: candidate.asset, cache: cache) {
      guard distance <= similarFeatureMatchThreshold else { return nil }
      return (hashDistance, distance)
    } else if hashDistance <= 4 {
      return (hashDistance, .greatestFiniteMagnitude)
    }
    return nil
  }

  @discardableResult
  static func deleteAssets(_ assets: [PHAsset]) async throws -> Bool {
    guard !assets.isEmpty else { return false }
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
      PHPhotoLibrary.shared().performChanges({
        PHAssetChangeRequest.deleteAssets(assets as NSArray)
      }, completionHandler: { success, error in
        if let error = error {
          if (error as? PHPhotosError)?.code == .userCancelled {
            continuation.resume(returning: false)
            return
          }
          continuation.resume(throwing: error)
          return
        }
        continuation.resume(returning: success)
      })
    }
  }

  static func estimatedBytes(for assets: [PHAsset]) -> Int {
    assets.reduce(0) { $0 + estimatedBytes(for: $1) }
  }

  static func estimatedBytes(for asset: PHAsset) -> Int {
    let cacheKey = metadataCacheKey(for: asset)
    if let cachedBytes = estimatedBytesCache.object(forKey: cacheKey) {
      return cachedBytes.intValue
    }

    let resources = PHAssetResource.assetResources(for: asset)
    var total = 0
    for resource in resources {
      if let fileSize = resource.value(forKey: "fileSize") as? Int {
        total += fileSize
      }
    }
    estimatedBytesCache.setObject(NSNumber(value: total), forKey: cacheKey)
    return total
  }

  static func durationText(for asset: PHAsset) -> String {
    guard asset.mediaType == .video else { return "" }
    let duration = max(asset.duration, 0)
    let totalSeconds = Int(duration.rounded())
    let hours = totalSeconds / 3_600
    let minutes = (totalSeconds % 3_600) / 60
    let seconds = totalSeconds % 60
    if hours > 0 {
      return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
    }
    return "\(minutes):\(String(format: "%02d", seconds))"
  }

  static func startCachingAssets(_ assets: [PHAsset], targetSize: CGSize, contentMode: PHImageContentMode = .aspectFill) {
    guard !assets.isEmpty else { return }
    imageManager.startCachingImages(
      for: assets,
      targetSize: targetSize,
      contentMode: contentMode,
      options: cachingOptions
    )
  }

  static func stopCachingAssets(_ assets: [PHAsset], targetSize: CGSize, contentMode: PHImageContentMode = .aspectFill) {
    guard !assets.isEmpty else { return }
    imageManager.stopCachingImages(
      for: assets,
      targetSize: targetSize,
      contentMode: contentMode,
      options: cachingOptions
    )
  }

  static func clearMemoryCaches() {
    imageCache.removeAllObjects()
    estimatedBytesCache.removeAllObjects()
    imageManager.stopCachingImagesForAllAssets()
  }

  static func preloadImage(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode) {
    let cacheKey = imageCacheKey(for: asset, targetSize: targetSize, contentMode: contentMode)
    guard imageCache.object(forKey: cacheKey) == nil else { return }

    let options = PHImageRequestOptions()
    options.isNetworkAccessAllowed = true
    options.deliveryMode = .highQualityFormat
    options.resizeMode = .exact

    imageManager.requestImage(
      for: asset,
      targetSize: targetSize,
      contentMode: contentMode,
      options: options
    ) { result, info in
      guard let result,
            let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool,
            !isDegraded else { return }
      imageCache.setObject(result, forKey: cacheKey, cost: imageCacheCost(for: result))
    }
  }

  #if canImport(UIKit)
  static func cachedImage(forKey key: NSString) -> UIImage? {
    imageCache.object(forKey: key) as? UIImage
  }

  static func storeCachedImage(_ image: UIImage, forKey key: NSString) {
    imageCache.setObject(image, forKey: key, cost: imageCacheCost(for: image))
  }
  #elseif canImport(AppKit)
  static func cachedImage(forKey key: NSString) -> NSImage? {
    imageCache.object(forKey: key) as? NSImage
  }

  static func storeCachedImage(_ image: NSImage, forKey key: NSString) {
    imageCache.setObject(image, forKey: key, cost: imageCacheCost(for: image))
  }
  #endif

  static func imageCacheKey(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode) -> NSString {
    NSString(
      string: "\(asset.localIdentifier)-\(Int(targetSize.width.rounded()))x\(Int(targetSize.height.rounded()))-\(contentMode.rawValue)"
    )
  }

  #if canImport(UIKit)
  private static func imageCacheCost(for image: UIImage) -> Int {
    let pixelWidth = Int((image.size.width * image.scale).rounded())
    let pixelHeight = Int((image.size.height * image.scale).rounded())
    return max(pixelWidth * pixelHeight * 4, 1)
  }
  #elseif canImport(AppKit)
  private static func imageCacheCost(for image: NSImage) -> Int {
    guard let representation = image.representations.first else { return 1 }
    return max(representation.pixelsWide * representation.pixelsHigh * 4, 1)
  }
  #endif

  private static func metadataCacheKey(for asset: PHAsset) -> NSString {
    let modificationTimestamp = Int((asset.modificationDate ?? .distantPast).timeIntervalSince1970.rounded())
    return NSString(string: "\(asset.localIdentifier)-\(modificationTimestamp)")
  }

  static func scaledSize(for size: CGSize, scale: CGFloat) -> CGSize {
    return CGSize(width: size.width * scale, height: size.height * scale)
  }

  static func fittedSize(for asset: PHAsset, in bounds: CGSize) -> CGSize {
    guard bounds.width > 0, bounds.height > 0 else { return .zero }

    let aspect = aspectRatio(for: asset)
    let boundsAspect = bounds.width / bounds.height
    if aspect > boundsAspect {
      return CGSize(width: bounds.width, height: bounds.width / aspect)
    } else {
      return CGSize(width: bounds.height * aspect, height: bounds.height)
    }
  }

  static func imageRequestSize(for asset: PHAsset, displaySize: CGSize, scale: CGFloat) -> CGSize {
    let scaled = scaledSize(for: displaySize, scale: scale)
    let maxWidth = max(CGFloat(asset.pixelWidth), 1)
    let maxHeight = max(CGFloat(asset.pixelHeight), 1)
    return CGSize(
      width: min(max(scaled.width, 1), maxWidth),
      height: min(max(scaled.height, 1), maxHeight)
    )
  }

  private static func fetchAssets(
    options: PHFetchOptions,
    limit: Int,
    excluding reviewedIdentifiers: Set<String> = []
  ) -> [PHAsset] {
    options.fetchLimit = reviewedIdentifiers.isEmpty ? limit : 0
    let result = PHAsset.fetchAssets(with: .image, options: options)
    return assets(from: result, limit: limit, excluding: reviewedIdentifiers)
  }

  private static func fetchRandomAssets(
    options: PHFetchOptions,
    limit: Int,
    excluding reviewedIdentifiers: Set<String> = []
  ) -> [PHAsset] {
    options.fetchLimit = 0
    let result = PHAsset.fetchAssets(with: .image, options: options)
    return randomAssets(from: result, limit: limit, excluding: reviewedIdentifiers)
  }

  private static func fetchLargePhotoAssets(
    options: PHFetchOptions,
    limit: Int,
    excluding reviewedIdentifiers: Set<String> = []
  ) -> [PHAsset] {
    options.predicate = excludingSubtype(.photoScreenshot)
    options.sortDescriptors = [
      NSSortDescriptor(key: "creationDate", ascending: false)
    ]
    let result = PHAsset.fetchAssets(with: .image, options: options)
    guard result.count > 0 else { return [] }

    var assets: [PHAsset] = []
    assets.reserveCapacity(result.count)
    for index in 0..<result.count {
      assets.append(result.object(at: index))
    }

    assets.sort { lhs, rhs in
      let lhsPixels = lhs.pixelWidth * lhs.pixelHeight
      let rhsPixels = rhs.pixelWidth * rhs.pixelHeight
      if lhsPixels == rhsPixels {
        return (lhs.creationDate ?? .distantPast) > (rhs.creationDate ?? .distantPast)
      }
      return lhsPixels > rhsPixels
    }

    var assetsWithBytes: [(asset: PHAsset, bytes: Int)] = []
    assetsWithBytes.reserveCapacity(assets.count)
    for asset in assets {
      let bytes = estimatedBytes(for: asset)
      if !reviewedIdentifiers.contains(asset.localIdentifier),
         isLargePhoto(asset, estimatedBytes: bytes) {
        assetsWithBytes.append((asset: asset, bytes: bytes))
      }
    }

    assetsWithBytes.sort { lhs, rhs in
      if lhs.bytes == rhs.bytes {
        let lhsPixels = lhs.asset.pixelWidth * lhs.asset.pixelHeight
        let rhsPixels = rhs.asset.pixelWidth * rhs.asset.pixelHeight
        if lhsPixels == rhsPixels {
          return (lhs.asset.creationDate ?? .distantPast) > (rhs.asset.creationDate ?? .distantPast)
        }
        return lhsPixels > rhsPixels
      }
      return lhs.bytes > rhs.bytes
    }

    return Array(assetsWithBytes.prefix(limit).map(\.asset))
  }

  private static func fetchLargePhotoCount() -> Int {
    fetchLargePhotoCounts(excluding: []).total
  }

  private static func fetchLargePhotoCounts(excluding reviewedIdentifiers: Set<String>) -> ReviewModeCounts {
    let options = PHFetchOptions()
    options.predicate = excludingSubtype(.photoScreenshot)
    let result = PHAsset.fetchAssets(with: .image, options: options)
    guard result.count > 0 else { return ReviewModeCounts(total: 0, notReviewed: 0) }

    var count = 0
    var notReviewedCount = 0
    for index in 0..<result.count {
      let asset = result.object(at: index)
      if isLargePhoto(asset, estimatedBytes: estimatedBytes(for: asset)) {
        count += 1
        if !reviewedIdentifiers.contains(asset.localIdentifier) {
          notReviewedCount += 1
        }
      }
    }
    return ReviewModeCounts(total: count, notReviewed: notReviewedCount)
  }

  private static func isLargePhoto(_ asset: PHAsset, estimatedBytes bytes: Int) -> Bool {
    guard !asset.mediaSubtypes.contains(.photoScreenshot) else { return false }
    let pixels = asset.pixelWidth * asset.pixelHeight
    return bytes >= largePhotoMinimumBytes || pixels >= largePhotoMinimumPixels
  }

  private static func fetchBurstAssets(
    limit: Int,
    excluding reviewedIdentifiers: Set<String> = []
  ) -> [PHAsset] {
    let collections = PHAssetCollection.fetchAssetCollections(
      with: .smartAlbum,
      subtype: .smartAlbumBursts,
      options: nil
    )
    guard let collection = collections.firstObject else { return [] }

    let options = PHFetchOptions()
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    options.fetchLimit = reviewedIdentifiers.isEmpty ? limit : 0
    let result = PHAsset.fetchAssets(in: collection, options: options)
    return assets(from: result, limit: limit, excluding: reviewedIdentifiers)
  }

  private static func fetchBurstAssetCount() -> Int {
    fetchBurstAssetCounts(excluding: []).total
  }

  private static func fetchBurstAssetCounts(excluding reviewedIdentifiers: Set<String>) -> ReviewModeCounts {
    let collections = PHAssetCollection.fetchAssetCollections(
      with: .smartAlbum,
      subtype: .smartAlbumBursts,
      options: nil
    )
    guard let collection = collections.firstObject else {
      return ReviewModeCounts(total: 0, notReviewed: 0)
    }
    let result = PHAsset.fetchAssets(in: collection, options: nil)
    return counts(from: result, excluding: reviewedIdentifiers)
  }

  private static func fetchScreenshotAssets(
    options: PHFetchOptions,
    sort: ScreenshotSortOption,
    limit: Int,
    excluding reviewedIdentifiers: Set<String> = []
  ) -> [PHAsset] {
    switch sort {
    case .recent:
      options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
      return fetchAssets(options: options, limit: limit, excluding: reviewedIdentifiers)
    case .oldest:
      options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
      return fetchAssets(options: options, limit: limit, excluding: reviewedIdentifiers)
    case .random:
      return fetchRandomAssets(options: options, limit: limit, excluding: reviewedIdentifiers)
    case .largest, .smallest:
      options.sortDescriptors = nil
      let result = PHAsset.fetchAssets(with: .image, options: options)
      guard result.count > 0 else { return [] }

      var assetsWithBytes: [(asset: PHAsset, bytes: Int)] = []
      assetsWithBytes.reserveCapacity(result.count)
      for index in 0..<result.count {
        let asset = result.object(at: index)
        guard !reviewedIdentifiers.contains(asset.localIdentifier) else { continue }
        assetsWithBytes.append((asset: asset, bytes: estimatedBytes(for: asset)))
      }

      assetsWithBytes.sort { lhs, rhs in
        switch (lhs.bytes, rhs.bytes) {
        case (0, 0):
          return (lhs.asset.creationDate ?? .distantPast) > (rhs.asset.creationDate ?? .distantPast)
        case (0, _):
          return false
        case (_, 0):
          return true
        default:
          if lhs.bytes == rhs.bytes {
            return (lhs.asset.creationDate ?? .distantPast) > (rhs.asset.creationDate ?? .distantPast)
          }
          return sort == .largest ? lhs.bytes > rhs.bytes : lhs.bytes < rhs.bytes
        }
      }

      return assetsWithBytes.prefix(limit).map(\.asset)
    }
  }

  private static func fetchVideoAssets(
    options: PHFetchOptions,
    sort: VideoSortOption,
    limit: Int,
    excluding reviewedIdentifiers: Set<String> = []
  ) -> [PHAsset] {
    switch sort {
    case .recent:
      options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
      return fetchAssets(mediaType: .video, options: options, limit: limit, excluding: reviewedIdentifiers)
    case .oldest:
      options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
      return fetchAssets(mediaType: .video, options: options, limit: limit, excluding: reviewedIdentifiers)
    case .random:
      return fetchRandomAssets(mediaType: .video, options: options, limit: limit, excluding: reviewedIdentifiers)
    case .largest, .shortest, .longest:
      options.sortDescriptors = nil
      let result = PHAsset.fetchAssets(with: .video, options: options)
      guard result.count > 0 else { return [] }

      var assets: [PHAsset] = []
      assets.reserveCapacity(result.count)
      for index in 0..<result.count {
        let asset = result.object(at: index)
        guard !reviewedIdentifiers.contains(asset.localIdentifier) else { continue }
        assets.append(asset)
      }

      assets.sort { lhs, rhs in
        switch sort {
        case .largest:
          let lhsBytes = estimatedBytes(for: lhs)
          let rhsBytes = estimatedBytes(for: rhs)
          if lhsBytes == rhsBytes {
            return lhs.duration > rhs.duration
          }
          return lhsBytes > rhsBytes
        case .shortest:
          if lhs.duration == rhs.duration {
            return (lhs.creationDate ?? .distantPast) > (rhs.creationDate ?? .distantPast)
          }
          return lhs.duration < rhs.duration
        case .longest:
          if lhs.duration == rhs.duration {
            return (lhs.creationDate ?? .distantPast) > (rhs.creationDate ?? .distantPast)
          }
          return lhs.duration > rhs.duration
        case .recent, .oldest, .random:
          return false
        }
      }

      return Array(assets.prefix(limit))
    }
  }

  private static func fetchAssets(
    mediaType: PHAssetMediaType,
    options: PHFetchOptions,
    limit: Int,
    excluding reviewedIdentifiers: Set<String> = []
  ) -> [PHAsset] {
    options.fetchLimit = reviewedIdentifiers.isEmpty ? limit : 0
    let result = PHAsset.fetchAssets(with: mediaType, options: options)
    return assets(from: result, limit: limit, excluding: reviewedIdentifiers)
  }

  private static func fetchRandomAssets(
    mediaType: PHAssetMediaType,
    options: PHFetchOptions,
    limit: Int,
    excluding reviewedIdentifiers: Set<String> = []
  ) -> [PHAsset] {
    options.fetchLimit = 0
    let result = PHAsset.fetchAssets(with: mediaType, options: options)
    return randomAssets(from: result, limit: limit, excluding: reviewedIdentifiers)
  }

  private static func assets(
    from result: PHFetchResult<PHAsset>,
    limit: Int,
    excluding reviewedIdentifiers: Set<String>
  ) -> [PHAsset] {
    guard result.count > 0, limit > 0 else { return [] }

    var assets: [PHAsset] = []
    assets.reserveCapacity(min(result.count, limit))
    for index in 0..<result.count {
      let asset = result.object(at: index)
      guard !reviewedIdentifiers.contains(asset.localIdentifier) else { continue }
      assets.append(asset)
      if assets.count >= limit {
        break
      }
    }
    return assets
  }

  private static func randomAssets(
    from result: PHFetchResult<PHAsset>,
    limit: Int,
    excluding reviewedIdentifiers: Set<String>
  ) -> [PHAsset] {
    let total = result.count
    guard total > 0, limit > 0 else { return [] }

    // Reservoir sampling gives every eligible asset an equal chance while
    // retaining only the requested session size. The previous implementation
    // materialized the entire library before shuffling it, which could briefly
    // retain tens of thousands of PHAsset objects for a 20-photo session.
    var sampledAssets: [PHAsset] = []
    sampledAssets.reserveCapacity(min(total, limit))
    var eligibleCount = 0
    for index in 0..<total {
      guard !Task.isCancelled else { return [] }
      let asset = result.object(at: index)
      guard !reviewedIdentifiers.contains(asset.localIdentifier) else { continue }
      eligibleCount += 1

      if sampledAssets.count < limit {
        sampledAssets.append(asset)
        continue
      }

      let replacementIndex = Int.random(in: 0..<eligibleCount)
      if replacementIndex < limit {
        sampledAssets[replacementIndex] = asset
      }
    }

    sampledAssets.shuffle()
    return sampledAssets
  }

  private static func counts(
    from result: PHFetchResult<PHAsset>,
    excluding reviewedIdentifiers: Set<String>
  ) -> ReviewModeCounts {
    let total = result.count
    guard !reviewedIdentifiers.isEmpty else {
      return ReviewModeCounts(total: total, notReviewed: total)
    }

    var notReviewedCount = 0
    for index in 0..<result.count {
      let asset = result.object(at: index)
      if !reviewedIdentifiers.contains(asset.localIdentifier) {
        notReviewedCount += 1
      }
    }
    return ReviewModeCounts(total: total, notReviewed: notReviewedCount)
  }

  private struct SimilarPhotoFingerprint {
    let asset: PHAsset
    let hash: UInt64
    let aspectRatio: CGFloat
  }

  // A group being accumulated during the incremental scan. The anchor is the
  // first (in sort order) photo; every other member matched it. A cluster with a
  // single member is just a lone photo waiting for a match, and only becomes a
  // reviewable group once a second member is added.
  private struct SimilarPhotoCluster {
    let anchor: SimilarPhotoFingerprint
    var members: [PHAsset]
    var closestHashDistance: Int
    var closestFeatureDistance: Float

    init(anchor: SimilarPhotoFingerprint) {
      self.anchor = anchor
      self.members = [anchor.asset]
      self.closestHashDistance = Int.max
      self.closestFeatureDistance = .greatestFiniteMagnitude
    }

    var isGroup: Bool { members.count > 1 }

    mutating func add(_ asset: PHAsset, hashDistance: Int, featureDistance: Float) {
      members.append(asset)
      closestHashDistance = min(closestHashDistance, hashDistance)
      closestFeatureDistance = min(closestFeatureDistance, featureDistance)
    }
  }

  // Vision feature-print distance below which two photos count as similar. The
  // scale is small: ~0 identical, ~0.35 genuinely similar, ~0.5 unrelated photos
  // of the same general scene. Lower toward 0.3 for stricter matching, raise
  // toward 0.4 for looser.
  private static let similarFeatureMatchThreshold: Float = 0.35

  private static func burstSimilarGroups(
    from assets: [PHAsset],
    usedIdentifiers: inout Set<String>
  ) -> [SimilarPhotoGroup] {
    var burstAssetsByIdentifier: [String: [PHAsset]] = [:]
    for asset in assets {
      guard let burstIdentifier = asset.burstIdentifier,
            !burstIdentifier.isEmpty else {
        continue
      }
      burstAssetsByIdentifier[burstIdentifier, default: []].append(asset)
    }

    return burstAssetsByIdentifier.values.compactMap { assets in
      guard assets.count > 1 else { return nil }
      let orderedAssets = orderSimilarAssetsForReview(assets)
      for asset in orderedAssets {
        usedIdentifiers.insert(asset.localIdentifier)
      }
      return SimilarPhotoGroup(assets: orderedAssets, confidence: .burst)
    }
  }

  private static func orderSimilarAssetsForReview(_ assets: [PHAsset]) -> [PHAsset] {
    assets.sorted { lhs, rhs in
      if lhs.isFavorite != rhs.isFavorite {
        return lhs.isFavorite && !rhs.isFavorite
      }

      let lhsPixels = lhs.pixelWidth * lhs.pixelHeight
      let rhsPixels = rhs.pixelWidth * rhs.pixelHeight
      if lhsPixels != rhsPixels {
        return lhsPixels > rhsPixels
      }

      return (lhs.creationDate ?? .distantPast) > (rhs.creationDate ?? .distantPast)
    }
  }

  private static func similarGroupConfidence(
    hashMatches: Int,
    closestHashDistance: Int,
    closestFeatureDistance: Float
  ) -> SimilarGroupConfidence {
    if hashMatches > 2 || closestHashDistance <= 6 || closestFeatureDistance <= 0.2 {
      return .strong
    }
    return .likely
  }

  private static func sortedSimilarGroups(
    _ groups: [SimilarPhotoGroup],
    sort: SimilarSortOption
  ) -> [SimilarPhotoGroup] {
    switch sort {
    case .random:
      return groups.shuffled()
    case .recent:
      return groups.sorted {
        groupNewestDate($0) > groupNewestDate($1)
      }
    case .oldest:
      return groups.sorted {
        groupOldestDate($0) < groupOldestDate($1)
      }
    case .largest:
      return groups.sorted {
        let lhsBytes = estimatedDuplicateBytes(in: $0)
        let rhsBytes = estimatedDuplicateBytes(in: $1)
        if lhsBytes == rhsBytes {
          return groupNewestDate($0) > groupNewestDate($1)
        }
        return lhsBytes > rhsBytes
      }
    case .mostMatches:
      return groups.sorted {
        if $0.assets.count == $1.assets.count {
          return estimatedDuplicateBytes(in: $0) > estimatedDuplicateBytes(in: $1)
        }
        return $0.assets.count > $1.assets.count
      }
    }
  }

  private static func estimatedDuplicateBytes(in group: SimilarPhotoGroup) -> Int {
    estimatedBytes(for: Array(group.assets.dropFirst()))
  }

  private static func groupNewestDate(_ group: SimilarPhotoGroup) -> Date {
    group.assets.compactMap(\.creationDate).max() ?? .distantPast
  }

  private static func groupOldestDate(_ group: SimilarPhotoGroup) -> Date {
    group.assets.compactMap(\.creationDate).min() ?? .distantFuture
  }

  private static func hammingDistance(_ lhs: UInt64, _ rhs: UInt64) -> Int {
    (lhs ^ rhs).nonzeroBitCount
  }

  // Renders a PHAsset thumbnail straight to a CGImage so the dHash and Vision
  // comparison core is shared across platforms; only the PlatformImage ->
  // CGImage step differs (UIImage.cgImage vs NSImage.cgImage(forProposedRect:)).
  private static func thumbnailCGImage(
    for asset: PHAsset,
    targetSize: CGSize,
    contentMode: PHImageContentMode = .aspectFill,
    deliveryMode: PHImageRequestOptionsDeliveryMode = .fastFormat,
    allowsNetworkAccess: Bool = false
  ) -> CGImage? {
    let options = PHImageRequestOptions()
    options.isNetworkAccessAllowed = allowsNetworkAccess
    options.deliveryMode = deliveryMode
    options.resizeMode = .exact
    options.isSynchronous = true

    var cgImage: CGImage?
    imageManager.requestImage(
      for: asset,
      targetSize: targetSize,
      contentMode: contentMode,
      options: options
    ) { result, info in
      let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
      guard !isCancelled, let result else { return }
      #if canImport(UIKit)
      cgImage = result.cgImage
      #elseif canImport(AppKit)
      var proposedRect = CGRect(origin: .zero, size: result.size)
      cgImage = result.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
      #endif
    }
    return cgImage
  }

  private static func featurePrintDistance(
    from lhs: PHAsset,
    to rhs: PHAsset,
    cache: NSCache<NSString, VNFeaturePrintObservation>
  ) -> Float? {
    guard let lhsPrint = featurePrint(for: lhs, cache: cache),
          let rhsPrint = featurePrint(for: rhs, cache: cache) else {
      return nil
    }

    var distance: Float = 0
    do {
      try lhsPrint.computeDistance(&distance, to: rhsPrint)
      return distance
    } catch {
      return nil
    }
  }

  private static func featurePrint(
    for asset: PHAsset,
    cache: NSCache<NSString, VNFeaturePrintObservation>
  ) -> VNFeaturePrintObservation? {
    if let cached = cache.object(forKey: asset.localIdentifier as NSString) {
      return cached
    }

    guard let cgImage = thumbnailCGImage(
      for: asset,
      targetSize: CGSize(width: 160, height: 160),
      contentMode: .aspectFit
    ) else {
      return nil
    }

    let request = VNGenerateImageFeaturePrintRequest()
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
      try handler.perform([request])
      guard let observation = request.results?.first as? VNFeaturePrintObservation else {
        return nil
      }
      cache.setObject(observation, forKey: asset.localIdentifier as NSString)
      return observation
    } catch {
      return nil
    }
  }

  private static func differenceHash(for cgImage: CGImage) -> UInt64? {
    let width = 9
    let height = 8
    var pixels = [UInt8](repeating: 0, count: width * height)
    let colorSpace = CGColorSpaceCreateDeviceGray()

    let drewImage = pixels.withUnsafeMutableBytes { buffer in
      guard let context = CGContext(
        data: buffer.baseAddress,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.none.rawValue
      ) else {
        return false
      }
      context.interpolationQuality = .low
      context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }

    guard drewImage else { return nil }

    var hash: UInt64 = 0
    for row in 0..<height {
      for column in 0..<(width - 1) {
        hash <<= 1
        let left = pixels[(row * width) + column]
        let right = pixels[(row * width) + column + 1]
        if left > right {
          hash |= 1
        }
      }
    }
    return hash
  }

  private static func onThisDayPredicate(referenceDate: Date = Date()) -> NSPredicate? {
    let calendar = Calendar.current
    let components = calendar.dateComponents([.month, .day], from: referenceDate)
    guard let month = components.month, let day = components.day,
          let yearRange = availablePhotoYearRange(referenceDate: referenceDate) else {
      return nil
    }

    let predicates = yearRange.compactMap { year in
      onThisDayPredicate(year: year, month: month, day: day, calendar: calendar)
    }

    guard !predicates.isEmpty else { return nil }
    return NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
  }

  private static func onThisDayPredicate(year: Int, month: Int, day: Int, calendar: Calendar) -> NSPredicate? {
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    components.year = year
    components.month = month
    components.day = day

    guard let start = calendar.date(from: components),
          let end = calendar.date(byAdding: .day, value: 1, to: start) else {
      return nil
    }

    return NSPredicate(
      format: "creationDate >= %@ AND creationDate < %@",
      start as NSDate,
      end as NSDate
    )
  }

  private static func availablePhotoYearRange(referenceDate: Date) -> ClosedRange<Int>? {
    let options = PHFetchOptions()
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
    options.fetchLimit = 1

    let result = PHAsset.fetchAssets(with: .image, options: options)
    guard let oldestAssetDate = result.firstObject?.creationDate else { return nil }

    let calendar = Calendar.current
    let firstYear = calendar.component(.year, from: oldestAssetDate)
    let currentYear = calendar.component(.year, from: referenceDate)
    guard firstYear < currentYear else { return nil }
    return firstYear...(currentYear - 1)
  }

  private static func aspectRatio(for asset: PHAsset) -> CGFloat {
    let width = CGFloat(asset.pixelWidth)
    let height = CGFloat(asset.pixelHeight)
    guard width > 0, height > 0 else { return 3.0 / 4.0 }
    return width / height
  }

  private static var cachingOptions: PHImageRequestOptions {
    let options = PHImageRequestOptions()
    options.isNetworkAccessAllowed = true
    options.deliveryMode = .opportunistic
    options.resizeMode = .exact
    return options
  }
}
