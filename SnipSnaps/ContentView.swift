//
//  ContentView.swift
//  SnipSnaps
//
//  Created by Nick Reisenauer on 6/7/25.
//

import SwiftUI

struct ContentView: View {
  var body: some View {
    #if DEBUG
    if let screenshotScreen = ProcessInfo.processInfo.environment["SNIPSNAPS_SCREENSHOT_SCREEN"] {
      #if os(macOS)
      MacScreenshotDemoView(screen: screenshotScreen)
      #else
      ScreenshotDemoView(screen: screenshotScreen)
      #endif
    } else {
      shell
    }
    #else
    shell
    #endif
  }

  @ViewBuilder
  private var shell: some View {
    #if os(macOS)
    // Mac uses a native sidebar instead of the iOS bottom tab bar; Settings lives
    // in the ⌘, Settings scene (see SnipSnapsApp), so it's not a sidebar row.
    MacSidebarShell()
      .tint(AppColor.primary)
      .frame(minWidth: 720, minHeight: 480)
    #else
    tabView
    #endif
  }

  #if os(iOS)
  @State private var selectedTab = 0

  private var tabView: some View {
    // Modern Tab API (the .tabItem builder is soft-deprecated). On iOS 26+ the
    // bar renders as floating Liquid Glass and collapses while scrolling.
    TabView(selection: $selectedTab) {
      Tab("Home", systemImage: "house", value: 0) {
        HomeView()
      }
      Tab("Settings", systemImage: "gearshape", value: 1) {
        SettingsView()
      }
    }
    .tint(AppColor.primary)
    .adaptiveTabBarMinimize()
    .sensoryFeedback(.selection, trigger: selectedTab)
  }
  #endif
}

#if os(macOS)
enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
  case photos
  case files

  var id: String { rawValue }

  var title: String {
    switch self {
    case .photos: return "Photos"
    case .files: return "Files"
    }
  }

  var systemImage: String {
    switch self {
    case .photos: return "photo.on.rectangle.angled"
    case .files: return "folder"
    }
  }
}

private struct MacSidebarShell: View {
  // Persist the selection across launches; never let it resolve to nil so the
  // detail pane is always populated.
  @SceneStorage("sidebarSelection") private var selectionRaw: String = SidebarItem.photos.rawValue

  private var selection: SidebarItem {
    SidebarItem(rawValue: selectionRaw) ?? .photos
  }

  private var selectionBinding: Binding<SidebarItem?> {
    Binding(
      get: { selection },
      set: { newValue in
        if let newValue { selectionRaw = newValue.rawValue }
      }
    )
  }

  var body: some View {
    NavigationSplitView {
      List(selection: selectionBinding) {
        Section("Clean Up") {
          ForEach(SidebarItem.allCases) { item in
            Label(item.title, systemImage: item.systemImage)
              .tag(item)
          }
        }
      }
      .navigationSplitViewColumnWidth(min: 188, ideal: 210, max: 280)
      .navigationTitle("SnipSnaps")
    } detail: {
      switch selection {
      case .photos: HomeView()
      case .files: FilesView()
      }
    }
  }
}
#endif
