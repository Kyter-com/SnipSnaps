//
//  Photos.swift
//  SnipSnaps
//
//  Created by Nick Reisenauer on 6/7/25.
//

import Photos

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

  static func fetchAssets(for mode: ReviewMode, limit: Int) -> [PHAsset] {
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
    case .random:
      break
    }
    return PHAsset.fetchAssets(with: .image, options: options).count
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
