//
//  HomeView.swift
//  SnipSnaps
//
//  Created by Nick Reisenauer on 6/7/25.
//

import Photos
import SwiftUI

struct HomeView: View {
  @State private var photoAuthStatus: Bool = false

  var body: some View {
    VStack {
      if !photoAuthStatus {
        Button("Request Photo Access") {
          PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
              photoAuthStatus = getPhotoAuthStatus()
            }
          }
        }
      }
      Text(photoAuthStatus ? "Photo access granted" : "Photo access denied")
      Button("Screenshots") {
        // Handle screenshots action
      }
      Button("Random") {
        // Handle random action
      }
    }
    .onAppear {
      Task {
        photoAuthStatus = getPhotoAuthStatus()
      }
    }
  }
}
