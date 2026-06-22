//
//  ContentView.swift
//  SnipSnaps
//
//  Created by Nick Reisenauer on 6/7/25.
//

import SwiftUI

struct ContentView: View {
  @State private var selectedTab = 0

  var body: some View {
    #if DEBUG
    if let screenshotScreen = ProcessInfo.processInfo.environment["SNIPSNAPS_SCREENSHOT_SCREEN"] {
      ScreenshotDemoView(screen: screenshotScreen)
    } else {
      tabView
    }
    #else
    tabView
    #endif
  }

  private var tabView: some View {
    TabView(selection: $selectedTab) {
      HomeView()
        .tabItem {
          Label("Home", systemImage: "house")
        }
        .tag(0)
      SettingsView()
        .tabItem {
          Label("Settings", systemImage: "gearshape")
        }
        .tag(1)
    }
      .accentColor(AppColor.primary)
      .onChange(of: selectedTab) {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
      }
  }
}
