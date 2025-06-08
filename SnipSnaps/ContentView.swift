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
    .onChange(of: selectedTab) {
      let generator = UIImpactFeedbackGenerator(style: .light)
      generator.impactOccurred()
    }
  }
}
