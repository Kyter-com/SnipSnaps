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
      .background(homeBackground)
      .navigationTitle("SnipSnaps")
      .onAppear {
        authStatus = PhotoLibrary.authorizationStatus()
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("SNIPSNAPS")
        .font(AppFont.mono(12, weight: .semibold))
        .tracking(2)
        .foregroundColor(Color(red: 0.25, green: 0.45, blue: 0.62))
      Text("Choose a sprint")
        .font(AppFont.display(30, weight: .semibold))
        .foregroundColor(Color(red: 0.08, green: 0.12, blue: 0.18))
      Text("Swipe fast, keep the best, clear the rest.")
        .font(AppFont.body(14))
        .foregroundColor(Color(red: 0.38, green: 0.46, blue: 0.56))
    }
  }

  private var accessCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(accessStatusText)
        .font(AppFont.body(15, weight: .semibold))
        .foregroundColor(Color(red: 0.15, green: 0.20, blue: 0.28))
      Text("SnipSnaps needs photo access to review and delete images.")
        .font(AppFont.body(13))
        .foregroundColor(Color(red: 0.40, green: 0.46, blue: 0.56))
      Button("Enable Photo Access") {
        Task {
          authStatus = await PhotoLibrary.requestAuthorization()
        }
      }
      .buttonStyle(.borderedProminent)
      .tint(Color(red: 0.20, green: 0.74, blue: 0.88))
      .font(AppFont.body(15, weight: .semibold))
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(Color.white.opacity(0.8))
        .shadow(color: Color.black.opacity(0.10), radius: 14, x: 0, y: 8)
    )
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

  private var homeBackground: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(red: 0.96, green: 0.98, blue: 1.0),
          Color(red: 0.90, green: 0.95, blue: 0.99),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      RoundedRectangle(cornerRadius: 40, style: .continuous)
        .fill(Color(red: 0.28, green: 0.82, blue: 0.95).opacity(0.22))
        .frame(width: 260, height: 110)
        .blur(radius: 10)
        .rotationEffect(.degrees(-18))
        .offset(x: -120, y: -170)
      Circle()
        .fill(Color(red: 0.36, green: 0.98, blue: 0.78).opacity(0.22))
        .frame(width: 200, height: 200)
        .blur(radius: 6)
        .offset(x: 140, y: -60)
      Circle()
        .fill(Color(red: 0.22, green: 0.50, blue: 0.90).opacity(0.20))
        .frame(width: 240, height: 240)
        .blur(radius: 8)
        .offset(x: 120, y: 260)
    }
    .ignoresSafeArea()
  }
}

private struct ActionCard: View {
  let mode: ReviewMode
  let reviewLimit: Int
  let isDisabled: Bool

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 26, style: .continuous)
        .fill(mode.gradient)
        .overlay(
          RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(Color.black.opacity(0.16))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 26, style: .continuous)
            .stroke(
              LinearGradient(
                colors: [Color.white.opacity(0.7), Color.white.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              ),
              lineWidth: 1
            )
        )
        .overlay(
          Circle()
            .fill(Color.white.opacity(0.2))
            .frame(width: 160, height: 160)
            .offset(x: 120, y: -110)
        )
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 8) {
            Text(mode.title)
              .font(AppFont.display(22, weight: .semibold))
            Text(mode.subtitle)
              .font(AppFont.body(13))
              .opacity(0.85)
          }
          Spacer()
          Image(systemName: mode.systemImage)
            .font(.system(size: 22, weight: .semibold))
        }
        HStack(spacing: 8) {
          Text("\(reviewLimit) PHOTOS")
            .font(AppFont.mono(11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.2))
            .clipShape(Capsule())
          Text("SWIPE")
            .font(AppFont.mono(11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.14))
            .clipShape(Capsule())
        }
      }
      .foregroundColor(.white)
      .padding(20)
    }
    .frame(height: 160)
    .shadow(color: mode.accentColor.opacity(0.35), radius: 18, x: 0, y: 10)
    .opacity(isDisabled ? 0.55 : 1.0)
  }
}
