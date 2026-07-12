//
//  SettingsView.swift
//  SnipSnaps
//
//  Created by Nick Reisenauer on 6/7/25.
//

import Foundation
import Photos
import SwiftUI

struct SettingsView: View {
  private let defaultReviewLimit = 20

  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase
  @State private var authStatus = PhotoLibrary.authorizationStatus()
  @AppStorage("reviewLimit") private var reviewLimit: Int = 20
  @AppStorage("screenshotSortOption") private var screenshotSortOptionRawValue: String = ScreenshotSortOption.recent.rawValue
  @AppStorage("videoSortOption") private var videoSortOptionRawValue: String = VideoSortOption.largest.rawValue
  @AppStorage("similarSortOption") private var similarSortOptionRawValue: String = SimilarSortOption.recent.rawValue
  #if os(macOS)
  @AppStorage("fileSortOption") private var fileSortOptionRawValue: String = FileSortOption.largest.rawValue
  #endif
  @AppStorage("reviewMemoryOption") private var reviewMemoryOptionRawValue: String = ReviewMemoryOption.thirtyDays.rawValue
  @AppStorage("totalDeletedCount") private var totalDeletedCount: Int = 0
  @AppStorage("totalDeletedBytes") private var totalDeletedBytes: Int = 0
  @State private var showResetLocalSettingsAlert = false

  var body: some View {
    #if os(macOS)
    // Rendered inside the native ⌘, Settings window — no NavigationStack/title.
    settingsForm
    #else
    NavigationStack {
      settingsForm
        .navigationTitle("Settings")
    }
    #endif
  }

  private var settingsForm: some View {
    Form {
        Section {
          LabeledContent("Access", value: photoAccessValueText)
          PhotoAccessButtons(status: authStatus) {
            authStatus = PhotoLibrary.authorizationStatus()
          }
        } header: {
          Text("Photo Access")
        } footer: {
          Text(photoAccessFooterText)
        }

        Section {
          Stepper(value: $reviewLimit, in: 10...100, step: 5) {
            HStack {
              Text("Review Size")
              Spacer()
              Text("\(reviewLimit)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
          }

          Picker("Remember Reviewed", selection: $reviewMemoryOptionRawValue) {
            ForEach(ReviewMemoryOption.allCases) { option in
              Text(option.title).tag(option.rawValue)
            }
          }
        } header: {
          Text("Review")
        } footer: {
          Text("Review size controls how many items appear in each session. Remember Reviewed skips items you've already reviewed so they don't show up again in any category.")
        }

        Section("Lifetime Stats") {
          if totalDeletedCount == 0 {
            Text("No deletions yet.")
              .foregroundStyle(.secondary)
          } else {
            LabeledContent("Deleted items", value: "\(totalDeletedCount)")
            LabeledContent("Space freed", value: totalDeletedBytesText)
          }
        }

        Section {
          Button(role: .destructive) {
            showResetLocalSettingsAlert = true
          } label: {
            settingsRow(
              title: "Reset Local Settings",
              systemImage: "arrow.counterclockwise.circle.fill",
              tint: .red,
              titleTint: .red,
              trailingSystemImage: "chevron.right"
            )
          }
          .settingsRowButtonStyle()
          .disabled(!hasLocalSettingsToReset)
        } footer: {
          Text("Resets review size, Photos and Files sorting, review memory, and lifetime deleted stats on this device. This does not delete photos or files.")
        }

        Section("Support") {
          Button {
            if let url = URL(string: "https://github.com/Kyter-com/SnipSnaps") {
              openURL(url)
            }
          } label: {
            HStack {
              Image("GitHub")
                .font(.title2)
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)

              Text("GitHub")
                .foregroundStyle(.primary)
              Spacer()
              Image(systemName: "arrow.up.forward")
                .font(.footnote)
                .foregroundStyle(.tertiary)
            }
          }
          .settingsRowButtonStyle()
          settingsLink(
            title: "Support",
            systemImage: "questionmark.circle.fill",
            tint: .blue,
            url: "https://kyter.com/snipsnaps/support/"
          )
          Button {
            sendFeedback()
          } label: {
            settingsRow(
              title: "Send Feedback",
              systemImage: "envelope.circle.fill",
              tint: .blue,
              trailingSystemImage: "chevron.right"
            )
          }
          .settingsRowButtonStyle()
        }

        Section("Legal") {
          settingsLink(
            title: "End User License Agreement",
            systemImage: "doc.circle.fill",
            tint: .gray,
            url: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
          )
          settingsLink(
            title: "Privacy Policy",
            systemImage: "hand.raised.circle.fill",
            tint: .blue,
            url: "https://kyter.com/snipsnaps/privacy/"
          )
          settingsLink(
            title: "Terms & Conditions",
            systemImage: "checkmark.circle.fill",
            tint: .mint,
            url: "https://kyter.com/snipsnaps/terms/"
          )
        }
      }
      .formStyle(.grouped)
      .alert("Reset Local Settings?", isPresented: $showResetLocalSettingsAlert) {
        Button("Reset", role: .destructive) {
          resetLocalSettings()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This clears your review size preference, Photos and Files sorting, review memory, and lifetime deleted stats on this device. Your photo library and files will not be changed.")
      }
      .onAppear { authStatus = PhotoLibrary.authorizationStatus() }
      .onChange(of: scenePhase) { _, newPhase in
        if newPhase == .active {
          authStatus = PhotoLibrary.authorizationStatus()
        }
      }
  }

  private var photoAccessValueText: String {
    switch authStatus {
    case .authorized:
      return "All Photos"
    case .limited:
      return "Selected Photos"
    case .denied:
      return "Denied"
    case .restricted:
      return "Restricted"
    case .notDetermined:
      return "Not Set"
    @unknown default:
      return "Unknown"
    }
  }

  private var photoAccessFooterText: String {
    switch authStatus {
    case .authorized:
      return "SnipSnaps can review your whole photo library."
    case .limited:
      return "SnipSnaps only sees the photos you've selected. Add more or allow full access anytime."
    case .denied:
      return "Turn on photo access in Settings to review and delete photos."
    case .restricted:
      return "Photo access is restricted on this device and can't be changed here."
    default:
      return "SnipSnaps needs photo access to review and delete photos."
    }
  }

  private var hasLocalSettingsToReset: Bool {
    reviewLimit != defaultReviewLimit
      || screenshotSortOptionRawValue != ScreenshotSortOption.recent.rawValue
      || videoSortOptionRawValue != VideoSortOption.largest.rawValue
      || similarSortOptionRawValue != SimilarSortOption.recent.rawValue
      || hasFileSettingsToReset
      || reviewMemoryOptionRawValue != ReviewMemoryOption.thirtyDays.rawValue
      || PhotoReviewHistory.hasReviewedIdentifiers()
      || totalDeletedCount != 0
      || totalDeletedBytes != 0
  }

  private var hasFileSettingsToReset: Bool {
    #if os(macOS)
    return fileSortOptionRawValue != FileSortOption.largest.rawValue || FileReviewHistory.hasReviewedPaths()
    #else
    return false
    #endif
  }

  private var totalDeletedBytesText: String {
    guard totalDeletedBytes > 0 else { return "0 KB" }
    return ByteCountFormatter.string(fromByteCount: Int64(totalDeletedBytes), countStyle: .file)
  }

  private func settingsLink(
    title: String,
    systemImage: String,
    tint: Color,
    url: String
  ) -> some View {
    Button {
      if let url = URL(string: url) {
        openURL(url)
      }
    } label: {
      settingsRow(
        title: title,
        systemImage: systemImage,
        tint: tint,
        trailingSystemImage: "arrow.up.forward"
      )
    }
    .settingsRowButtonStyle()
  }

  private func settingsRow(
    title: String,
    systemImage: String,
    tint: Color,
    titleTint: Color = .primary,
    trailingSystemImage: String
  ) -> some View {
    HStack {
      Image(systemName: systemImage)
        .font(.title2)
        .foregroundStyle(tint)
        .frame(width: 28, height: 28)

      Text(title)
        .foregroundStyle(titleTint)
      Spacer()
      if let trailing = resolvedTrailingSymbol(trailingSystemImage) {
        Image(systemName: trailing)
          .font(.footnote)
          .fontWeight(trailing == "chevron.right" ? .semibold : .regular)
          .foregroundStyle(.tertiary)
      }
    }
  }

  // chevron.right is an iOS push-navigation cue; on macOS these rows open alerts
  // or external URLs, so the disclosure chevron is meaningless — drop it there.
  private func resolvedTrailingSymbol(_ symbol: String) -> String? {
    #if os(macOS)
    return symbol == "chevron.right" ? nil : symbol
    #else
    return symbol
    #endif
  }

  private func resetLocalSettings() {
    reviewLimit = defaultReviewLimit
    screenshotSortOptionRawValue = ScreenshotSortOption.recent.rawValue
    videoSortOptionRawValue = VideoSortOption.largest.rawValue
    similarSortOptionRawValue = SimilarSortOption.recent.rawValue
    #if os(macOS)
    fileSortOptionRawValue = FileSortOption.largest.rawValue
    #endif
    reviewMemoryOptionRawValue = ReviewMemoryOption.thirtyDays.rawValue
    PhotoReviewHistory.clearAll()
    #if os(macOS)
    FileReviewHistory.clearAll()
    #endif
    totalDeletedCount = 0
    totalDeletedBytes = 0
  }

  private func sendFeedback() {
    let email = "dev@kyter.com"
    let subject = "SnipSnaps App Feedback"
    let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

    if let url = URL(string: "mailto:\(email)?subject=\(encodedSubject)") {
      openURL(url)
    }
  }
}

private extension View {
  // On macOS a Form Button with a custom row label picks up default button
  // chrome (a tinted fill), so action rows look perpetually highlighted and
  // inconsistent with the plain LabeledContent/Picker rows. .plain restores a
  // flat, full-width row; a no-op on iOS, where the row style already reads right.
  @ViewBuilder
  func settingsRowButtonStyle() -> some View {
    #if os(macOS)
    buttonStyle(.plain).contentShape(Rectangle())
    #else
    self
    #endif
  }
}
