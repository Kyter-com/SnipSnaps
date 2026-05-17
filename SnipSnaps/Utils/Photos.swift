//
//  Photos.swift
//  SnipSnaps
//
//  Created by Nick Reisenauer on 6/7/25.
//

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

enum PhotoLibrary {
  static let imageManager = PHCachingImageManager()
  nonisolated(unsafe) private static let imageCache: NSCache<NSString, NSObject> = {
    let cache = NSCache<NSString, NSObject>()
    cache.countLimit = 12
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

  static func fetchAssets(for mode: ReviewMode, limit: Int, screenshotSort: ScreenshotSortOption = .recent) -> [PHAsset] {
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
      options.fetchLimit = limit
      return fetchAssets(options: options, limit: limit)
    case .onThisDay:
      guard let predicate = onThisDayPredicate() else { return [] }
      options.predicate = predicate
      options.fetchLimit = limit
      return fetchAssets(options: options, limit: limit)
    case .screenshots:
      options.predicate = NSPredicate(
        format: "(mediaSubtype & %d) != 0",
        PHAssetMediaSubtype.photoScreenshot.rawValue
      )
      return fetchScreenshotAssets(options: options, sort: screenshotSort, limit: limit)
    case .similar:
      options.fetchLimit = limit
      return fetchAssets(options: options, limit: limit)
    case .random:
      return fetchRandomAssets(options: options, limit: limit)
    }
  }

  static func fetchTodaysPhotoCount() -> Int {
    fetchCount(for: .today)
  }

  static func fetchCount(for mode: ReviewMode) -> Int {
    let options = PHFetchOptions()
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
    case .similar:
      options.fetchLimit = 1_000
    case .random:
      break
    }
    return PHAsset.fetchAssets(with: .image, options: options).count
  }

  static func fetchSimilarPhotoGroups(
    scanLimit: Int,
    maxGroups: Int,
    sort: SimilarSortOption = .recent
  ) async -> [SimilarPhotoGroup] {
    #if canImport(UIKit)
    let options = PHFetchOptions()
    options.sortDescriptors = [
      NSSortDescriptor(key: "creationDate", ascending: sort == .oldest)
    ]
    options.fetchLimit = max(scanLimit, 1)

    let result = PHAsset.fetchAssets(with: .image, options: options)
    guard result.count > 1 else { return [] }

    var assets: [PHAsset] = []
    assets.reserveCapacity(result.count)
    for index in 0..<result.count {
      assets.append(result.object(at: index))
    }
    if sort == .random {
      assets.shuffle()
    }

    var usedIdentifiers = Set<String>()
    var groups = burstSimilarGroups(from: assets, usedIdentifiers: &usedIdentifiers)

    var fingerprints: [SimilarPhotoFingerprint] = []
    fingerprints.reserveCapacity(assets.count)
    for asset in assets where !usedIdentifiers.contains(asset.localIdentifier) {
      guard let image = thumbnailImage(for: asset, targetSize: CGSize(width: 18, height: 16)),
            let hash = differenceHash(for: image) else {
        continue
      }
      fingerprints.append(SimilarPhotoFingerprint(asset: asset, hash: hash, aspectRatio: aspectRatio(for: asset)))
    }

    var featurePrints: [String: VNFeaturePrintObservation] = [:]
    for fingerprint in fingerprints {
      guard !usedIdentifiers.contains(fingerprint.asset.localIdentifier) else { continue }

      var matches = [fingerprint.asset]
      var closestHashDistance = Int.max
      var closestDistance = Float.greatestFiniteMagnitude
      for candidate in fingerprints {
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

      guard matches.count > 1 else { continue }
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
    }

    return sortedSimilarGroups(groups, sort: sort).prefix(maxGroups).map { $0 }
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
    let resources = PHAssetResource.assetResources(for: asset)
    var total = 0
    for resource in resources {
      if let fileSize = resource.value(forKey: "fileSize") as? Int {
        total += fileSize
      }
    }
    return total
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
      imageCache.setObject(result, forKey: cacheKey)
    }
  }

  #if canImport(UIKit)
  static func cachedImage(forKey key: NSString) -> UIImage? {
    imageCache.object(forKey: key) as? UIImage
  }

  static func storeCachedImage(_ image: UIImage, forKey key: NSString) {
    imageCache.setObject(image, forKey: key)
  }
  #elseif canImport(AppKit)
  static func cachedImage(forKey key: NSString) -> NSImage? {
    imageCache.object(forKey: key) as? NSImage
  }

  static func storeCachedImage(_ image: NSImage, forKey key: NSString) {
    imageCache.setObject(image, forKey: key)
  }
  #endif

  static func imageCacheKey(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode) -> NSString {
    NSString(
      string: "\(asset.localIdentifier)-\(Int(targetSize.width.rounded()))x\(Int(targetSize.height.rounded()))-\(contentMode.rawValue)"
    )
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

  private static func fetchAssets(options: PHFetchOptions, limit: Int) -> [PHAsset] {
    let result = PHAsset.fetchAssets(with: .image, options: options)
    let count = min(result.count, limit)
    guard count > 0 else { return [] }

    var assets: [PHAsset] = []
    assets.reserveCapacity(count)
    for index in 0..<count {
      assets.append(result.object(at: index))
    }
    return assets
  }

  private static func fetchRandomAssets(options: PHFetchOptions, limit: Int) -> [PHAsset] {
    let result = PHAsset.fetchAssets(with: .image, options: options)
    let total = result.count
    guard total > 0 else { return [] }

    let target = min(limit, total)
    var indices = Set<Int>()
    while indices.count < target {
      indices.insert(Int.random(in: 0..<total))
    }

    return indices.shuffled().map { result.object(at: $0) }
  }

  private static func fetchScreenshotAssets(
    options: PHFetchOptions,
    sort: ScreenshotSortOption,
    limit: Int
  ) -> [PHAsset] {
    switch sort {
    case .recent:
      options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
      options.fetchLimit = limit
      return fetchAssets(options: options, limit: limit)
    case .oldest:
      options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
      options.fetchLimit = limit
      return fetchAssets(options: options, limit: limit)
    case .random:
      return fetchRandomAssets(options: options, limit: limit)
    case .largest, .smallest:
      options.sortDescriptors = nil
      let result = PHAsset.fetchAssets(with: .image, options: options)
      guard result.count > 0 else { return [] }

      var assetsWithBytes: [(asset: PHAsset, bytes: Int)] = []
      assetsWithBytes.reserveCapacity(result.count)
      for index in 0..<result.count {
        let asset = result.object(at: index)
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
    contentMode: PHImageContentMode = .aspectFill
  ) -> UIImage? {
    let options = PHImageRequestOptions()
    options.isNetworkAccessAllowed = true
    options.deliveryMode = .highQualityFormat
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
    guard firstYear <= currentYear else { return nil }
    return firstYear...currentYear
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
