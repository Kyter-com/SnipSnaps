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

struct HomeView: View {
  @State private var authStatus = PhotoLibrary.authorizationStatus()
  @State private var counts: [ReviewMode: Int] = [:]
  @State private var selectedMode: ReviewMode?
  @AppStorage("reviewLimit") private var reviewLimit: Int = 20
  @AppStorage("screenshotSortOption") private var screenshotSortOptionRawValue: String = ScreenshotSortOption.recent.rawValue
  @AppStorage("videoSortOption") private var videoSortOptionRawValue: String = VideoSortOption.largest.rawValue
  @AppStorage("similarSortOption") private var similarSortOptionRawValue: String = SimilarSortOption.recent.rawValue

  private let reviewSections = [
    ReviewModeSection(title: "Quick Clean", modes: [.today, .screenshots, .oldScreenshots, .random]),
    ReviewModeSection(title: "Space Savers", modes: [.videos, .screenRecordings, .largePhotos, .similar]),
    ReviewModeSection(title: "Memories", modes: [.onThisDay, .livePhotos, .bursts, .recentlyEdited, .oldFavorites])
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

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text("Swipe fast, keep the best, clear the rest.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)

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
      .navigationDestination(item: $selectedMode) { mode in
        destination(for: mode)
      }
      .onAppear(perform: refresh)
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
        selectedMode = mode
      } label: {
        ActionCard(
          mode: mode,
          count: counts[mode] ?? 0,
          isDisabled: !canAccessPhotos,
          reservesAccessorySpace: mode == .screenshots || mode == .videos || mode == .similar
        )
      }
      .buttonStyle(.plain)
      .disabled(!canAccessPhotos)

      if mode == .screenshots {
        screenshotSortMenu
          .padding(.leading, 16)
          .padding(.bottom, 12)
          .disabled(!canAccessPhotos)
      }

      if mode == .videos {
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
          refresh()
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

  private func refresh() {
    authStatus = PhotoLibrary.authorizationStatus()
    guard canAccessPhotos else { return }
    Task.detached(priority: .userInitiated) {
      var next: [ReviewMode: Int] = [:]
      for mode in ReviewMode.allCases {
        next[mode] = mode == .similar ? 0 : PhotoLibrary.fetchCount(for: mode)
      }
      let refreshedCounts = next
      await MainActor.run { counts = refreshedCounts }
    }
  }
}

private struct ActionCard: View {
  let mode: ReviewMode
  let count: Int
  let isDisabled: Bool
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
      return "SCAN"
    }
    return count > 9999 ? "9999+" : "\(count)"
  }
}
