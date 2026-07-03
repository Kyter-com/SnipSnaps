//
//  PhotoAccessButtons.swift
//  SnipSnaps
//
//  Created by Nick Reisenauer on 6/7/25.
//

import Photos
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// Renders the right photo-access action(s) for the current authorization status so
// the Home card, the review access/empty states, and the Settings section share one
// code path. Limited users can add more photos (iOS in-app picker) or open Settings
// for full access; denied users are sent to Settings. Authorized and restricted
// intentionally show nothing.
struct PhotoAccessButtons: View {
  let status: PHAuthorizationStatus
  // Called after the access level or selection may have changed, so the host can
  // re-read the status and refresh its counts / reload its assets.
  var refresh: () -> Void

  @Environment(\.openURL) private var openURL

  var body: some View {
    switch status {
    case .notDetermined:
      Button("Enable Photo Access") {
        Task {
          _ = await PhotoLibrary.requestAuthorization()
          refresh()
        }
      }
      .prominentActionButton()
    case .limited:
      #if os(iOS)
      Button("Add More Photos") {
        Task {
          await PhotoLibrary.presentLimitedLibraryPicker()
          refresh()
        }
      }
      .prominentActionButton()
      Button("Allow Full Access") {
        openPhotoSettings()
      }
      .secondaryActionButton()
      #else
      Button("Open Photo Settings") {
        openPhotoSettings()
      }
      .prominentActionButton()
      #endif
    case .denied:
      Button(openSettingsButtonTitle) {
        openPhotoSettings()
      }
      .prominentActionButton()
    case .restricted, .authorized:
      EmptyView()
    @unknown default:
      EmptyView()
    }
  }

  private var openSettingsButtonTitle: String {
    #if os(iOS)
    return "Open Settings"
    #else
    return "Open Photo Settings"
    #endif
  }

  // iOS: SnipSnaps' own Settings page (the only App-Store-safe deep link). macOS:
  // the Photos privacy pane in System Settings — an undocumented anchor, so fall
  // back to opening System Settings generally if it fails to resolve.
  private func openPhotoSettings() {
    #if os(iOS)
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    openURL(url)
    #elseif os(macOS)
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") else { return }
    openURL(url) { accepted in
      if !accepted, let fallback = URL(string: "x-apple.systempreferences:") {
        openURL(fallback)
      }
    }
    #endif
  }
}
