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
  @AppStorage("reviewLimit") private var reviewLimit: Int = 20
  @State private var todaysPhotoCount: Int = 0

  private var canAccessPhotos: Bool {
    PhotoLibrary.canAccessPhotos(authStatus)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          header
          if !canAccessPhotos {
            accessCard
          }
          ForEach(ReviewMode.allCases) { mode in
            NavigationLink {
              ReviewSessionView(mode: mode)
            } label: {
              ActionCard(
                mode: mode,
                reviewLimit: reviewLimit,
                todaysPhotoCount: todaysPhotoCount,
                isDisabled: !canAccessPhotos
              )
            }
            .buttonStyle(.plain)
            .disabled(!canAccessPhotos)
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 32)
      }
      .background(AppColor.background)
      .navigationTitle("SnipSnaps")
      .navigationBarTitleDisplayMode(.large)
      .onAppear {
        authStatus = PhotoLibrary.authorizationStatus()
        if canAccessPhotos {
            todaysPhotoCount = PhotoLibrary.fetchTodaysPhotoCount()
        }
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
        Text("Swipe fast, keep the best, clear the rest.")
            .font(.subheadline)
            .foregroundColor(AppColor.subtext)
    }
  }

  private var accessCard: some View {
      VStack(alignment: .leading, spacing: 10) {
          Text(accessStatusText)
              .font(.headline)
              .foregroundColor(AppColor.text)
          Text("SnipSnaps needs photo access to review and delete images.")
              .font(.subheadline)
              .foregroundColor(AppColor.subtext)
          Button("Enable Photo Access") {
              Task {
                  authStatus = await PhotoLibrary.requestAuthorization()
              }
          }
          .buttonStyle(.borderedProminent)
          .tint(AppColor.primary)
      }
      .padding()
      .background(AppColor.card)
      .cornerRadius(16)
      .shadow(color: AppColor.shadow, radius: 8, x: 0, y: 4)
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
}


private struct ActionCard: View {
  let mode: ReviewMode
  let reviewLimit: Int
  let todaysPhotoCount: Int
  let isDisabled: Bool

  var body: some View {
      ZStack {
          VisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
          
          Image(systemName: mode.systemImage)
              .font(.system(size: 80, weight: .bold))
              .foregroundColor(AppColor.primary.opacity(0.1))
              .rotationEffect(.degrees(-15))
              .offset(x: 80, y: -40)

          VStack(alignment: .leading, spacing: 12) {
              HStack {
                  VStack(alignment: .leading) {
                      Text(mode.title)
                          .font(.title2.weight(.bold))
                      Text(mode.subtitle)
                          .font(.caption)
                          .opacity(0.8)
                  }
                  Spacer()
              }
              
              Spacer()

              HStack(spacing: 8) {
                  if mode == .today {
                      Text("\(todaysPhotoCount) PHOTOS TODAY")
                          .font(.caption.weight(.medium))
                          .padding(.horizontal, 10)
                          .padding(.vertical, 5)
                          .background(Color.black.opacity(0.1))
                          .clipShape(Capsule())
                  } else {
                      Text("\(reviewLimit) PHOTOS")
                          .font(.caption.weight(.medium))
                          .padding(.horizontal, 10)
                          .padding(.vertical, 5)
                          .background(Color.black.opacity(0.1))
                          .clipShape(Capsule())
                  }
                  
                  Text("SWIPE")
                      .font(.caption.weight(.medium))
                      .padding(.horizontal, 10)
                      .padding(.vertical, 5)
                      .background(Color.black.opacity(0.1))
                      .clipShape(Capsule())
              }
          }
          .padding(20)
      }
      .frame(height: 160)
      .foregroundColor(AppColor.text)
      .cornerRadius(20)
      .shadow(color: AppColor.shadow, radius: 10, x: 0, y: 5)
      .opacity(isDisabled ? 0.6 : 1.0)
  }
}

struct VisualEffectView: UIViewRepresentable {
    var effect: UIVisualEffect?
    func makeUIView(context: Context) -> UIVisualEffectView { UIVisualEffectView() }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) { uiView.effect = effect }
}
