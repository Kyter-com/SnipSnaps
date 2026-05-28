//
//  SnipSnapsApp.swift
//  SnipSnaps
//
//  Created by Nick Reisenauer on 6/7/25.
//

import SwiftUI

@main
struct SnipSnapsApp: App {
  @Environment(\.scenePhase) private var scenePhase

  init() {
    PhotoReviewHistory.compactStoredHistory()
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .onChange(of: scenePhase) { _, newPhase in
          switch newPhase {
          case .active:
            PhotoReviewHistory.compactStoredHistory()
          case .background:
            PhotoReviewHistory.compactStoredHistory()
            PhotoLibrary.clearMemoryCaches()
          case .inactive:
            break
          @unknown default:
            break
          }
        }
    }
  }
}
