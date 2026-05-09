//
//  HomeView.swift
//  SnipSnaps
//
//  Created by Nick Reisenauer on 6/7/25.
//

import Photos
import SwiftUI

struct HomeView: View {
  @State private var authStatus = PhotoLibrary.authorizationStatus()
  @State private var counts: [ReviewMode: Int] = [:]
  @AppStorage("reviewLimit") private var reviewLimit: Int = 20

  private var canAccessPhotos: Bool {
    PhotoLibrary.canAccessPhotos(authStatus)
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

          VStack(spacing: 12) {
            ForEach(ReviewMode.allCases) { mode in
              NavigationLink {
                destination(for: mode)
              } label: {
                ActionCard(
                  mode: mode,
                  count: counts[mode] ?? 0,
                  isDisabled: !canAccessPhotos
                )
              }
              .buttonStyle(.plain)
              .disabled(!canAccessPhotos)
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
      await MainActor.run { counts = next }
    }
  }
}

private struct ActionCard: View {
  let mode: ReviewMode
  let count: Int
  let isDisabled: Bool

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
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 16)
    }
    .frame(height: 96)
    .opacity(isDisabled ? 0.5 : 1.0)
  }

  private var displayCount: String {
    if mode == .similar {
      return "SCAN"
    }
    return count > 9999 ? "9999+" : "\(count)"
  }
}
