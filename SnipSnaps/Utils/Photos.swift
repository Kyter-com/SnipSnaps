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
  private static let legacyModeRawValues = ["recentlyEdited"]
  private static let maxIdentifiersPerMode = 5_000
  private static let maxPersistentHistoryAge: TimeInterval = 5 * 365 * 24 * 60 * 60
  private static let sessionLock = NSLock()
  nonisolated(unsafe) private static var sessionIdentifiersByMode: [ReviewMode: Set<String>] = [:]

  static func supportsSkipping(for mode: ReviewMode) -> Bool {
    switch mode {
    case .today, .onThisDay, .random, .screenshots, .oldScreenshots, .videos, .screenRecordings, .largePhotos, .livePhotos, .bursts, .oldFavorites:
      return true
    case .similar:
      return false
    }
  }

  static func reviewedIdentifiers(for mode: ReviewMode, memoryOption: ReviewMemoryOption) -> Set<String> {
    guard supportsSkipping(for: mode) else { return [] }
    guard memoryOption != .never else { return [] }
    if memoryOption == .session {
      return sessionReviewedIdentifiers(for: mode)
    }

    return Set(filteredPersistentEntries(for: mode, memoryOption: memoryOption).keys)
  }

  static func hasReviewedIdentifiers() -> Bool {
    !sessionReviewedIdentifiersAreEmpty()
      || ReviewMode.allCases.contains { !persistentEntries(for: $0).isEmpty }
      || legacyModeRawValues.contains { UserDefaults.standard.object(forKey: key(forRawValue: $0)) != nil }
  }

  static func markReviewed(_ asset: PHAsset, for mode: ReviewMode, memoryOption: ReviewMemoryOption) {
    guard supportsSkipping(for: mode) else { return }
    guard memoryOption != .never else { return }
    if memoryOption == .session {
      insertSessionReviewedIdentifier(asset.localIdentifier, for: mode)
      return
    }

    var entries = persistentEntries(for: mode)
    entries[asset.localIdentifier] = Date().timeIntervalSince1970
    storePersistentEntries(entries, for: mode)
  }

  static func unmarkReviewed(_ asset: PHAsset, for mode: ReviewMode, memoryOption: ReviewMemoryOption) {
    guard supportsSkipping(for: mode) else { return }
    guard memoryOption != .never else { return }
    if memoryOption == .session {
      removeSessionReviewedIdentifier(asset.localIdentifier, for: mode)
      return
    }

    var entries = persistentEntries(for: mode)
    entries.removeValue(forKey: asset.localIdentifier)
    storePersistentEntries(entries, for: mode)
  }

  static func clearAll() {
    clearSessionReviewedIdentifiers()
    for mode in ReviewMode.allCases where supportsSkipping(for: mode) {
      UserDefaults.standard.removeObject(forKey: key(for: mode))
    }
    clearLegacyModeKeys()
  }

  static func compactStoredHistory() {
    trimSessionReviewedIdentifiers()
    for mode in ReviewMode.allCases {
      if supportsSkipping(for: mode) {
        storePersistentEntries(compactedPersistentEntries(for: mode), for: mode)
      } else {
        UserDefaults.standard.removeObject(forKey: key(for: mode))
      }
    }
    clearLegacyModeKeys()
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

  private static func filteredPersistentEntries(for mode: ReviewMode, memoryOption: ReviewMemoryOption) -> [String: TimeInterval] {
    let entries = persistentEntries(for: mode)
    guard let expirationInterval = memoryOption.expirationInterval, expirationInterval > 0 else {
      return entries
    }

    let cutoff = Date().timeIntervalSince1970 - expirationInterval
    return entries.filter { $0.value >= cutoff }
  }

  private static func persistentEntries(for mode: ReviewMode) -> [String: TimeInterval] {
    let key = key(for: mode)
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

  private static func compactedPersistentEntries(for mode: ReviewMode) -> [String: TimeInterval] {
    compactedPersistentEntries(persistentEntries(for: mode))
  }

  private static func compactedPersistentEntries(_ entries: [String: TimeInterval]) -> [String: TimeInterval] {
    let cutoff = Date().timeIntervalSince1970 - maxPersistentHistoryAge
    return entries.filter { $0.value >= cutoff }
  }

  private static func storePersistentEntries(_ entries: [String: TimeInterval], for mode: ReviewMode) {
    let compactedEntries = compactedPersistentEntries(entries)
    let limitedEntries = compactedEntries.sorted { $0.value > $1.value }.prefix(maxIdentifiersPerMode)
    let dictionary = Dictionary(uniqueKeysWithValues: limitedEntries.map { ($0.key, $0.value) })
    guard !dictionary.isEmpty else {
      UserDefaults.standard.removeObject(forKey: key(for: mode))
      return
    }
    UserDefaults.standard.set(dictionary, forKey: key(for: mode))
  }

  private static func sessionReviewedIdentifiers(for mode: ReviewMode) -> Set<String> {
    sessionLock.lock()
    defer { sessionLock.unlock() }
    return sessionIdentifiersByMode[mode] ?? []
  }

  private static func sessionReviewedIdentifiersAreEmpty() -> Bool {
    sessionLock.lock()
    defer { sessionLock.unlock() }
    return sessionIdentifiersByMode.values.allSatisfy(\.isEmpty)
  }

  private static func insertSessionReviewedIdentifier(_ identifier: String, for mode: ReviewMode) {
    sessionLock.lock()
    defer { sessionLock.unlock() }
    var identifiers = sessionIdentifiersByMode[mode, default: []]
    identifiers.insert(identifier)
    while identifiers.count > maxIdentifiersPerMode, let excessIdentifier = identifiers.first {
      identifiers.remove(excessIdentifier)
    }
    sessionIdentifiersByMode[mode] = identifiers
  }

  private static func removeSessionReviewedIdentifier(_ identifier: String, for mode: ReviewMode) {
    sessionLock.lock()
    defer { sessionLock.unlock() }
    sessionIdentifiersByMode[mode]?.remove(identifier)
  }

  private static func clearSessionReviewedIdentifiers() {
    sessionLock.lock()
    defer { sessionLock.unlock() }
    sessionIdentifiersByMode.removeAll()
  }

  private static func trimSessionReviewedIdentifiers() {
    sessionLock.lock()
    defer { sessionLock.unlock() }
    for mode in sessionIdentifiersByMode.keys {
      var identifiers = sessionIdentifiersByMode[mode] ?? []
      while identifiers.count > maxIdentifiersPerMode, let excessIdentifier = identifiers.first {
        identifiers.remove(excessIdentifier)
      }
      sessionIdentifiersByMode[mode] = identifiers
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

  static func fetchSimilarPhotoGroups(
    scanLimit: Int,
    maxGroups: Int,
    sort: SimilarSortOption = .recent,
    progressHandler: ((SimilarPhotoScanProgress) async -> Void)? = nil,
    partialGroupsHandler: (([SimilarPhotoGroup]) async -> Void)? = nil
  ) async -> [SimilarPhotoGroup] {
    #if canImport(UIKit)
    let options = PHFetchOptions()
    options.sortDescriptors = [
      NSSortDescriptor(key: "creationDate", ascending: sort == .oldest)
    ]
    options.predicate = NSPredicate(
      format: "(mediaSubtype & %d) == 0",
      PHAssetMediaSubtype.photoScreenshot.rawValue
    )
    options.fetchLimit = max(scanLimit, 1)

    let result = PHAsset.fetchAssets(with: .image, options: options)
    guard result.count > 1 else { return [] }
    await progressHandler?(SimilarPhotoScanProgress(
      phase: .preparing,
      completedCount: 0,
      totalCount: result.count,
      groupsFound: 0
    ))

    var assets: [PHAsset] = []
    assets.reserveCapacity(result.count)
    for index in 0..<result.count {
      guard !Task.isCancelled else { return [] }
      assets.append(result.object(at: index))
    }
    if sort == .random {
      assets.shuffle()
    }

    var usedIdentifiers = Set<String>()
    var groups = burstSimilarGroups(from: assets, usedIdentifiers: &usedIdentifiers)
    if !groups.isEmpty {
      let sortedBurstGroups = sortedSimilarGroups(groups, sort: sort).prefix(maxGroups).map { $0 }
      await partialGroupsHandler?(sortedBurstGroups)
      if groups.count >= maxGroups, sort != .largest, sort != .mostMatches {
        return sortedBurstGroups
      }
    }

    var fingerprints: [SimilarPhotoFingerprint] = []
    fingerprints.reserveCapacity(assets.count)
    for (index, asset) in assets.enumerated() {
      guard !Task.isCancelled else { return sortedSimilarGroups(groups, sort: sort).prefix(maxGroups).map { $0 } }
      if !usedIdentifiers.contains(asset.localIdentifier),
         let image = thumbnailImage(
          for: asset,
          targetSize: CGSize(width: 18, height: 16),
          deliveryMode: .highQualityFormat
         ),
         let hash = differenceHash(for: image) {
        fingerprints.append(SimilarPhotoFingerprint(asset: asset, hash: hash, aspectRatio: aspectRatio(for: asset)))
      }
      if index == 0 || index == assets.count - 1 || index.isMultiple(of: 20) {
        await progressHandler?(SimilarPhotoScanProgress(
          phase: .fingerprinting,
          completedCount: index + 1,
          totalCount: assets.count,
          groupsFound: groups.count
        ))
      }
    }

    var featurePrints: [String: VNFeaturePrintObservation] = [:]
    for (index, fingerprint) in fingerprints.enumerated() {
      guard !Task.isCancelled else { return sortedSimilarGroups(groups, sort: sort).prefix(maxGroups).map { $0 } }
      guard !usedIdentifiers.contains(fingerprint.asset.localIdentifier) else {
        if index == 0 || index == fingerprints.count - 1 || index.isMultiple(of: 5) {
          await progressHandler?(SimilarPhotoScanProgress(
            phase: .comparing,
            completedCount: index + 1,
            totalCount: max(fingerprints.count, 1),
            groupsFound: groups.count
          ))
        }
        continue
      }

      var matches = [fingerprint.asset]
      var closestHashDistance = Int.max
      var closestDistance = Float.greatestFiniteMagnitude
      for (candidateIndex, candidate) in fingerprints.enumerated() {
        if candidateIndex.isMultiple(of: 24), Task.isCancelled {
          return sortedSimilarGroups(groups, sort: sort).prefix(maxGroups).map { $0 }
        }
        guard fingerprint.asset.localIdentifier != candidate.asset.localIdentifier,
              !usedIdentifiers.contains(candidate.asset.localIdentifier) else {
          continue
        }

        let hashDistance = hammingDistance(fingerprint.hash, candidate.hash)
        guard abs(fingerprint.aspectRatio - candidate.aspectRatio) < 0.12,
              hashDistance <= 14 else {
          continue
        }

        if hashDistance <= 6 {
          closestHashDistance = min(closestHashDistance, hashDistance)
          matches.append(candidate.asset)
          continue
        }

        guard let distance = featurePrintDistance(
          from: fingerprint.asset,
          to: candidate.asset,
          cache: &featurePrints
        ) else {
          continue
        }
        closestDistance = min(closestDistance, distance)
        guard distance <= 11 else {
          continue
        }
        closestHashDistance = min(closestHashDistance, hashDistance)
        matches.append(candidate.asset)
      }

      guard matches.count > 1 else {
        if index == 0 || index == fingerprints.count - 1 || index.isMultiple(of: 5) {
          await progressHandler?(SimilarPhotoScanProgress(
            phase: .comparing,
            completedCount: index + 1,
            totalCount: max(fingerprints.count, 1),
            groupsFound: groups.count
          ))
        }
        continue
      }
      let orderedMatches = orderSimilarAssetsForReview(matches)
      for asset in orderedMatches {
        usedIdentifiers.insert(asset.localIdentifier)
      }
      groups.append(SimilarPhotoGroup(
        assets: orderedMatches,
        confidence: similarGroupConfidence(
          hashMatches: matches.count,
          closestHashDistance: closestHashDistance,
          closestFeatureDistance: closestDistance
        )
      ))
      await partialGroupsHandler?(sortedSimilarGroups(groups, sort: sort).prefix(maxGroups).map { $0 })
      if index == 0 || index == fingerprints.count - 1 || index.isMultiple(of: 5) {
        await progressHandler?(SimilarPhotoScanProgress(
          phase: .comparing,
          completedCount: index + 1,
          totalCount: max(fingerprints.count, 1),
          groupsFound: groups.count
        ))
      }
      if groups.count >= maxGroups, sort != .largest, sort != .mostMatches {
        break
      }
    }

    let sortedGroups = sortedSimilarGroups(groups, sort: sort).prefix(maxGroups).map { $0 }
    await progressHandler?(SimilarPhotoScanProgress(
      phase: .finishing,
      completedCount: sortedGroups.count,
      totalCount: max(sortedGroups.count, 1),
      groupsFound: sortedGroups.count
    ))
    await partialGroupsHandler?(sortedGroups)
    return sortedGroups
    #else
    return []
    #endif
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
    options.predicate = NSPredicate(
      format: "(mediaSubtype & %d) == 0",
      PHAssetMediaSubtype.photoScreenshot.rawValue
    )
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
    options.predicate = NSPredicate(
      format: "(mediaSubtype & %d) == 0",
      PHAssetMediaSubtype.photoScreenshot.rawValue
    )
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
    guard total > 0 else { return [] }

    var eligibleAssets: [PHAsset] = []
    eligibleAssets.reserveCapacity(total)
    for index in 0..<total {
      let asset = result.object(at: index)
      guard !reviewedIdentifiers.contains(asset.localIdentifier) else { continue }
      eligibleAssets.append(asset)
    }

    guard !eligibleAssets.isEmpty else { return [] }
    eligibleAssets.shuffle()
    return Array(eligibleAssets.prefix(limit))
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
    if hashMatches > 2 || closestHashDistance <= 6 || closestFeatureDistance <= 7 {
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

  #if canImport(UIKit)
  private static func thumbnailImage(
    for asset: PHAsset,
    targetSize: CGSize,
    contentMode: PHImageContentMode = .aspectFill,
    deliveryMode: PHImageRequestOptionsDeliveryMode = .fastFormat,
    allowsNetworkAccess: Bool = false
  ) -> UIImage? {
    let options = PHImageRequestOptions()
    options.isNetworkAccessAllowed = allowsNetworkAccess
    options.deliveryMode = deliveryMode
    options.resizeMode = .exact
    options.isSynchronous = true

    var image: UIImage?
    imageManager.requestImage(
      for: asset,
      targetSize: targetSize,
      contentMode: contentMode,
      options: options
    ) { result, info in
      let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
      guard !isCancelled else { return }
      image = result
    }
    return image
  }

  private static func featurePrintDistance(
    from lhs: PHAsset,
    to rhs: PHAsset,
    cache: inout [String: VNFeaturePrintObservation]
  ) -> Float? {
    guard let lhsPrint = featurePrint(for: lhs, cache: &cache),
          let rhsPrint = featurePrint(for: rhs, cache: &cache) else {
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
    cache: inout [String: VNFeaturePrintObservation]
  ) -> VNFeaturePrintObservation? {
    if let cached = cache[asset.localIdentifier] {
      return cached
    }

    guard let image = thumbnailImage(
      for: asset,
      targetSize: CGSize(width: 160, height: 160),
      contentMode: .aspectFit
    ),
      let cgImage = image.cgImage else {
      return nil
    }

    let request = VNGenerateImageFeaturePrintRequest()
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
      try handler.perform([request])
      guard let observation = request.results?.first as? VNFeaturePrintObservation else {
        return nil
      }
      cache[asset.localIdentifier] = observation
      return observation
    } catch {
      return nil
    }
  }

  private static func differenceHash(for image: UIImage) -> UInt64? {
    guard let cgImage = image.cgImage else { return nil }

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
  #endif

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
