//
//  Photos.swift
//  SnipSnaps
//
//  Created by Nick Reisenauer on 6/7/25.
//

import Photos

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

  static func deleteAssets(_ assets: [PHAsset]) async throws {
    guard !assets.isEmpty else { return }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      PHPhotoLibrary.shared().performChanges({
        PHAssetChangeRequest.deleteAssets(assets as NSArray)
      }, completionHandler: { success, error in
        if let error = error {
          continuation.resume(throwing: error)
          return
        }
        guard success else {
          continuation.resume(throwing: PhotoLibraryError.deleteFailed)
          return
        }
        continuation.resume(returning: ())
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
}
