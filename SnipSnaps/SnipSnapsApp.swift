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
    #if os(macOS)
    FileReviewHistory.compact()
    #endif
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .task {
          await ReviewReminderScheduler.restoreIfEnabled()
        }
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
    #if os(macOS)
    .defaultSize(width: 1000, height: 720)
    .windowResizability(.contentMinSize)
    .commands {
      AppCommands()
    }
    #endif

    // Native Settings window, opened by the standard ⌘, menu item.
    #if os(macOS)
    Settings {
      SettingsView()
        .frame(width: 480, height: 560)
    }
    #endif
  }
}
