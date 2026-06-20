//
//  HomeView.swift
//  SnipSnaps
//
//  Created by Nick Reisenauer on 6/7/25.
//

import Photos
import SwiftUI

private struct ReviewModeSection: Identifiable {
  let title: String
  let modes: [ReviewMode]

  var id: String { title }
}

private struct CachedReviewModeCounts: Codable {
  let total: Int
  let notReviewed: Int
  let updatedAt: TimeInterval

  var counts: ReviewModeCounts {
    ReviewModeCounts(total: total, notReviewed: notReviewed)
  }
}

private enum HomeCountCache {
  private static let keyPrefix = "homeReviewModeCounts"

  static func load(memoryOptionRawValue: String) -> [ReviewMode: ReviewModeCounts] {
    let key = key(for: memoryOptionRawValue)
    guard let data = UserDefaults.standard.data(forKey: key),
          let cached = try? JSONDecoder().decode([String: CachedReviewModeCounts].self, from: data) else {
      return [:]
    }

    return Dictionary(uniqueKeysWithValues: cached.compactMap { rawValue, entry in
      guard let mode = ReviewMode(rawValue: rawValue) else { return nil }
      return (mode, entry.counts)
    })
  }

  static func hasFreshCount(
    for mode: ReviewMode,
    memoryOptionRawValue: String,
    maxAge: TimeInterval
  ) -> Bool {
    let key = key(for: memoryOptionRawValue)
    guard let data = UserDefaults.standard.data(forKey: key),
          let cached = try? JSONDecoder().decode([String: CachedReviewModeCounts].self, from: data),
          let entry = cached[mode.rawValue] else {
      return false
    }

    return Date().timeIntervalSince1970 - entry.updatedAt <= maxAge
  }

  static func store(_ counts: [ReviewMode: ReviewModeCounts], memoryOptionRawValue: String) {
    let key = key(for: memoryOptionRawValue)
    let existing: [String: CachedReviewModeCounts]
    if let data = UserDefaults.standard.data(forKey: key),
       let cached = try? JSONDecoder().decode([String: CachedReviewModeCounts].self, from: data) {
      existing = cached
    } else {
      existing = [:]
    }

    let now = Date().timeIntervalSince1970
    let nextCounts = counts.reduce(into: existing) { result, item in
      result[item.key.rawValue] = CachedReviewModeCounts(
        total: item.value.total,
        notReviewed: item.value.notReviewed,
        updatedAt: now
      )
    }

    if let data = try? JSONEncoder().encode(nextCounts) {
      UserDefaults.standard.set(data, forKey: key)
    }
  }

  private static func key(for memoryOptionRawValue: String) -> String {
    "\(keyPrefix).\(memoryOptionRawValue)"
  }
}

struct HomeView: View {
  @State private var authStatus = PhotoLibrary.authorizationStatus()
  @State private var counts: [ReviewMode: ReviewModeCounts] = [:]
  @State private var selectedMode: ReviewMode?
  @State private var isRefreshingCounts = false
  @State private var countRefreshID = UUID()
  @State private var hasLoadedInitialCounts = false
  @State private var reviewedIdentifierCountsAtReviewStart: [ReviewMode: Int] = [:]
  @AppStorage("reviewLimit") private var reviewLimit: Int = 20
  @AppStorage("screenshotSortOption") private var screenshotSortOptionRawValue: String = ScreenshotSortOption.recent.rawValue
  @AppStorage("videoSortOption") private var videoSortOptionRawValue: String = VideoSortOption.largest.rawValue
  @AppStorage("similarSortOption") private var similarSortOptionRawValue: String = SimilarSortOption.recent.rawValue
  @AppStorage("reviewMemoryOption") private var reviewMemoryOptionRawValue: String = ReviewMemoryOption.thirtyDays.rawValue

  private let reviewSections = [
    ReviewModeSection(title: "Quick Clean", modes: [.today, .screenshots, .oldScreenshots, .random]),
    ReviewModeSection(title: "Space Savers", modes: [.videos, .screenRecordings, .largePhotos, .similar]),
    ReviewModeSection(title: "Library Finds", modes: [.onThisDay, .livePhotos, .bursts, .oldFavorites])
  ]

  private var canAccessPhotos: Bool {
    PhotoLibrary.canAccessPhotos(authStatus)
  }

  private var screenshotSortOption: ScreenshotSortOption {
    get {
      ScreenshotSortOption(rawValue: screenshotSortOptionRawValue) ?? .recent
    }
    nonmutating set {
      screenshotSortOptionRawValue = newValue.rawValue
    }
  }

  private var similarSortOption: SimilarSortOption {
    get {
      SimilarSortOption(rawValue: similarSortOptionRawValue) ?? .recent
    }
    nonmutating set {
      similarSortOptionRawValue = newValue.rawValue
    }
  }

  private var videoSortOption: VideoSortOption {
    get {
      VideoSortOption(rawValue: videoSortOptionRawValue) ?? .largest
    }
    nonmutating set {
      videoSortOptionRawValue = newValue.rawValue
    }
  }

  private var reviewMemoryOption: ReviewMemoryOption {
    ReviewMemoryOption(rawValue: reviewMemoryOptionRawValue) ?? .thirtyDays
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if !canAccessPhotos {
            accessCard
          }

          VStack(alignment: .leading, spacing: 18) {
            ForEach(reviewSections) { section in
              VStack(alignment: .leading, spacing: 10) {
                Text(section.title)
                  .font(.footnote.weight(.semibold))
                  .foregroundStyle(.secondary)
                  .textCase(.uppercase)
                  .padding(.horizontal, 4)

                VStack(spacing: 12) {
                  ForEach(section.modes) { mode in
                    reviewModeCard(for: mode)
                  }
                }
              }
            }
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 32)
      }
      .background(AppColor.background)
      .navigationTitle("SnipSnaps")
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          if isRefreshingCounts {
            updatingCountsIndicator
          }
        }
      }
      .navigationDestination(item: $selectedMode) { mode in
        destination(for: mode)
      }
      .onAppear {
        loadInitialCountsIfNeeded()
      }
      .onChange(of: selectedMode) { oldValue, newValue in
        if newValue == nil, let reviewedMode = oldValue {
          applyReviewedCountDelta(for: reviewedMode)
          refresh(modes: countRefreshModes(afterReviewing: reviewedMode))
        }
      }
      .onChange(of: reviewMemoryOptionRawValue) { _, _ in
        loadCachedCounts()
        refreshForCurrentMemoryOption()
      }
    }
  }

  @ViewBuilder
  private func destination(for mode: ReviewMode) -> some View {
    if mode == .similar {
      SimilarReviewSessionView()
    } else {
      ReviewSessionView(mode: mode)
    }
  }

  private func reviewModeCard(for mode: ReviewMode) -> some View {
    ZStack(alignment: .bottomLeading) {
      Button {
        recordReviewStart(for: mode)
        selectedMode = mode
      } label: {
        ActionCard(
          mode: mode,
          counts: counts[mode],
          isDisabled: !canAccessPhotos,
          reviewMemory: reviewMemoryOption,
          reservesAccessorySpace: mode.usesScreenshotSort || mode.usesVideoSort || mode == .similar
        )
      }
      .buttonStyle(.plain)
      .disabled(!canAccessPhotos)

      if mode.usesScreenshotSort {
        screenshotSortMenu
          .padding(.leading, 16)
          .padding(.bottom, 12)
          .disabled(!canAccessPhotos)
      }

      if mode.usesVideoSort {
        videoSortMenu
          .padding(.leading, 16)
          .padding(.bottom, 12)
          .disabled(!canAccessPhotos)
      }

      if mode == .similar {
        similarSortMenu
          .padding(.leading, 16)
          .padding(.bottom, 12)
          .disabled(!canAccessPhotos)
      }
    }
  }

  private var screenshotSortMenu: some View {
    Menu {
      ForEach(ScreenshotSortOption.allCases) { option in
        Button {
          screenshotSortOption = option
        } label: {
          Label(
            option.title,
            systemImage: option == screenshotSortOption ? "checkmark" : option.systemImage
          )
        }
      }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: screenshotSortOption.systemImage)
        Text(screenshotSortOption.title)
        Image(systemName: "chevron.down")
          .font(.caption2.weight(.bold))
      }
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(Color(.tertiarySystemGroupedBackground), in: Capsule(style: .continuous))
    }
    .accessibilityLabel("Sort screenshots by \(screenshotSortOption.title)")
  }

  private var videoSortMenu: some View {
    Menu {
      ForEach(VideoSortOption.allCases) { option in
        Button {
          videoSortOption = option
        } label: {
          Label(
            option.subtitle,
            systemImage: option == videoSortOption ? "checkmark" : option.systemImage
          )
        }
      }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: videoSortOption.systemImage)
        Text(videoSortOption.title)
        Image(systemName: "chevron.down")
          .font(.caption2.weight(.bold))
      }
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(Color(.tertiarySystemGroupedBackground), in: Capsule(style: .continuous))
    }
    .accessibilityLabel("Sort videos by \(videoSortOption.subtitle)")
  }

  private var similarSortMenu: some View {
    Menu {
      ForEach(SimilarSortOption.allCases) { option in
        Button {
          similarSortOption = option
        } label: {
          Label(
            option.subtitle,
            systemImage: option == similarSortOption ? "checkmark" : option.systemImage
          )
        }
      }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: similarSortOption.systemImage)
        Text(similarSortOption.title)
        Image(systemName: "chevron.down")
          .font(.caption2.weight(.bold))
      }
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(Color(.tertiarySystemGroupedBackground), in: Capsule(style: .continuous))
    }
    .accessibilityLabel("Sort similar groups by \(similarSortOption.subtitle)")
  }

  private var updatingCountsIndicator: some View {
    ProgressView()
      .controlSize(.small)
      .frame(width: 32, height: 32)
      .foregroundStyle(.secondary)
      .accessibilityLabel("Updating counts")
  }

  private var accessCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(accessStatusText)
        .font(.headline)
      Text("SnipSnaps needs photo access to review and delete images.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Button("Enable Photo Access") {
        Task {
          authStatus = await PhotoLibrary.requestAuthorization()
          loadCachedCounts()
          refreshForCurrentMemoryOption()
        }
      }
      .buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(AppColor.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  private var accessStatusText: String {
    switch authStatus {
    case .authorized:
      return "Full photo access enabled"
    case .limited:
      return "Limited photo access enabled"
    case .denied:
      return "Photo access denied"
    case .restricted:
      return "Photo access restricted"
    case .notDetermined:
      return "Photo access not set"
    @unknown default:
      return "Photo access needed"
    }
  }

  private func refresh(modes modesToRefresh: [ReviewMode]? = nil) {
    authStatus = PhotoLibrary.authorizationStatus()
    let refreshID = UUID()
    countRefreshID = refreshID
    guard canAccessPhotos else {
      counts = [:]
      isRefreshingCounts = false
      return
    }
    let modesToRefresh = modesToRefresh ?? allCountModes
    guard !modesToRefresh.isEmpty else {
      isRefreshingCounts = false
      return
    }
    isRefreshingCounts = true
    let reviewMemoryOption = reviewMemoryOption
    let reviewMemoryOptionRawValue = reviewMemoryOptionRawValue
    Task.detached(priority: .userInitiated) {
      var next: [ReviewMode: ReviewModeCounts] = [:]
      for mode in modesToRefresh {
        next[mode] = PhotoLibrary.fetchCounts(for: mode, reviewMemory: reviewMemoryOption)
      }
      let refreshedCounts = next
      HomeCountCache.store(refreshedCounts, memoryOptionRawValue: reviewMemoryOptionRawValue)
      await MainActor.run {
        guard countRefreshID == refreshID else { return }
        counts.merge(refreshedCounts) { _, new in new }
        isRefreshingCounts = false
      }
    }
  }

  private func loadInitialCountsIfNeeded() {
    guard !hasLoadedInitialCounts else { return }
    hasLoadedInitialCounts = true
    loadCachedCounts()
    refreshForCurrentMemoryOption()
  }

  private func loadCachedCounts() {
    counts = HomeCountCache.load(memoryOptionRawValue: reviewMemoryOptionRawValue)
  }

  private func refreshForCurrentMemoryOption() {
    let expensiveModesToRefresh = expensiveCountModes.filter {
      !HomeCountCache.hasFreshCount(
        for: $0,
        memoryOptionRawValue: reviewMemoryOptionRawValue,
        maxAge: 12 * 60 * 60
      )
    }
    refresh(modes: fastCountModes, deferredModes: expensiveModesToRefresh)
  }

  private func recordReviewStart(for mode: ReviewMode) {
    guard PhotoReviewHistory.supportsSkipping(for: mode), reviewMemoryOption != .never else { return }
    reviewedIdentifierCountsAtReviewStart[mode] = PhotoReviewHistory.reviewedIdentifiers(
      for: mode,
      memoryOption: reviewMemoryOption
    ).count
  }

  private func applyReviewedCountDelta(for mode: ReviewMode) {
    guard PhotoReviewHistory.supportsSkipping(for: mode), reviewMemoryOption != .never else { return }
    guard let beforeCount = reviewedIdentifierCountsAtReviewStart.removeValue(forKey: mode) else { return }
    let afterCount = PhotoReviewHistory.reviewedIdentifiers(for: mode, memoryOption: reviewMemoryOption).count
    let reviewedDelta = max(afterCount - beforeCount, 0)
    guard reviewedDelta > 0, let currentCounts = counts[mode] else { return }

    let adjustedCounts = ReviewModeCounts(
      total: currentCounts.total,
      notReviewed: max(currentCounts.notReviewed - reviewedDelta, 0)
    )
    counts[mode] = adjustedCounts
    HomeCountCache.store([mode: adjustedCounts], memoryOptionRawValue: reviewMemoryOptionRawValue)
  }

  private func refresh(
    modes modesToRefresh: [ReviewMode],
    deferredModes: [ReviewMode]
  ) {
    authStatus = PhotoLibrary.authorizationStatus()
    let refreshID = UUID()
    countRefreshID = refreshID
    guard canAccessPhotos else {
      counts = [:]
      isRefreshingCounts = false
      return
    }
    guard !modesToRefresh.isEmpty || !deferredModes.isEmpty else {
      isRefreshingCounts = false
      return
    }

    isRefreshingCounts = !modesToRefresh.isEmpty
    let reviewMemoryOption = reviewMemoryOption
    let reviewMemoryOptionRawValue = reviewMemoryOptionRawValue
    Task.detached(priority: .userInitiated) {
      if !modesToRefresh.isEmpty {
        let refreshedCounts = Self.fetchCounts(for: modesToRefresh, reviewMemoryOption: reviewMemoryOption)
        HomeCountCache.store(refreshedCounts, memoryOptionRawValue: reviewMemoryOptionRawValue)
        await MainActor.run {
          guard countRefreshID == refreshID else { return }
          counts.merge(refreshedCounts) { _, new in new }
          isRefreshingCounts = false
        }
      }

      guard !deferredModes.isEmpty, !Task.isCancelled else { return }
      try? await Task.sleep(for: .seconds(2))
      let deferredCounts = Self.fetchCounts(for: deferredModes, reviewMemoryOption: reviewMemoryOption)
      HomeCountCache.store(deferredCounts, memoryOptionRawValue: reviewMemoryOptionRawValue)
      await MainActor.run {
        guard countRefreshID == refreshID else { return }
        counts.merge(deferredCounts) { _, new in new }
      }
    }
  }

  nonisolated private static func fetchCounts(
    for modes: [ReviewMode],
    reviewMemoryOption: ReviewMemoryOption
  ) -> [ReviewMode: ReviewModeCounts] {
    var next: [ReviewMode: ReviewModeCounts] = [:]
    for mode in modes {
      next[mode] = PhotoLibrary.fetchCounts(for: mode, reviewMemory: reviewMemoryOption)
    }
    return next
  }

  private var allCountModes: [ReviewMode] {
    ReviewMode.allCases.filter { $0 != .similar }
  }

  private var fastCountModes: [ReviewMode] {
    allCountModes.filter { !expensiveCountModes.contains($0) }
  }

  private var expensiveCountModes: [ReviewMode] {
    [.largePhotos]
  }

  private var videoCountModes: [ReviewMode] {
    allCountModes.filter(\.reviewsVideos)
  }

  private func countRefreshModes(afterReviewing mode: ReviewMode) -> [ReviewMode] {
    // Review memory is shared across categories, so reviewing in one mode can
    // change the not-reviewed count of every mode that scans the same media
    // type. Refresh all inexpensive same-type modes immediately. Large Photos
    // is expensive to recount, so it only refreshes when it was the mode just
    // reviewed; after an unrelated image review its card updates on the next
    // launch or memory-setting change rather than mid-session.
    if mode.reviewsVideos {
      return videoCountModes
    }
    var modes = fastCountModes.filter { !$0.reviewsVideos }
    if mode == .largePhotos {
      modes.append(.largePhotos)
    }
    return modes
  }
}

private struct ActionCard: View {
  let mode: ReviewMode
  let counts: ReviewModeCounts?
  let isDisabled: Bool
  let reviewMemory: ReviewMemoryOption
  var reservesAccessorySpace = false

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(AppColor.card)

      Text(displayCount)
        .font(.system(size: 96, weight: .heavy, design: .rounded))
        .foregroundStyle(.quaternary)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 16)
        .allowsHitTesting(false)
        .clipped()

      HStack(alignment: .center, spacing: 16) {
        VStack(alignment: .leading, spacing: 4) {
          Label(mode.title, systemImage: mode.systemImage)
            .labelStyle(.titleAndIcon)
            .font(.headline)
            .foregroundStyle(AppColor.text)
          Text(mode.subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
          if let countSummary {
            Text(countSummary)
              .font(.caption.weight(.medium))
              .foregroundStyle(.tertiary)
              .monospacedDigit()
          }
        }
        .padding(.bottom, reservesAccessorySpace ? 30 : 0)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 16)
    }
    .frame(height: reservesAccessorySpace ? 112 : 96)
    .opacity(isDisabled ? 0.5 : 1.0)
  }

  private var displayCount: String {
    if mode == .similar {
      return "Scan"
    }
    guard let counts else { return "..." }
    let count = PhotoReviewHistory.supportsSkipping(for: mode) && reviewMemory != .never
      ? counts.notReviewed
      : counts.total
    return count > 9999 ? "9999+" : "\(count)"
  }

  private var countSummary: String? {
    guard mode != .similar else { return nil }
    guard let counts else { return nil }
    if PhotoReviewHistory.supportsSkipping(for: mode), reviewMemory != .never {
      return "\(counts.notReviewed) not reviewed · \(counts.total) total"
    }
    return "\(counts.total) total"
  }
}
