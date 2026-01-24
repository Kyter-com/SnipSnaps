//
//  SettingsView.swift
//  SnipSnaps
//
//  Created by Nick Reisenauer on 6/7/25.
//

import Foundation
import SwiftUI

struct SettingsView: View {
  @AppStorage("reviewLimit") private var reviewLimit: Int = 20
  @AppStorage("totalDeletedCount") private var totalDeletedCount: Int = 0
  @AppStorage("totalDeletedBytes") private var totalDeletedBytes: Int = 0

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          reviewSizeCard
          statsCard
        }
        .padding(16)
      }
      .background(settingsBackground)
      .navigationTitle("Settings")
    }
  }

  private var reviewSizeCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Review size")
        .font(AppFont.display(20, weight: .semibold))
        .foregroundColor(Color(red: 0.12, green: 0.16, blue: 0.22))
      Text("Choose how many photos appear in each session.")
        .font(AppFont.body(14))
        .foregroundColor(Color(red: 0.40, green: 0.46, blue: 0.56))
      HStack {
        Text("\(reviewLimit) photos")
          .font(AppFont.mono(14, weight: .semibold))
          .foregroundColor(Color(red: 0.12, green: 0.16, blue: 0.22))
        Spacer()
        Stepper("", value: $reviewLimit, in: 10...100, step: 5)
          .labelsHidden()
      }
      Slider(value: reviewLimitBinding, in: 10...100, step: 5)
        .tint(Color(red: 0.12, green: 0.58, blue: 0.63))
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(Color.white.opacity(0.92))
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
    )
  }

  private var statsCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Lifetime stats")
        .font(AppFont.display(20, weight: .semibold))
        .foregroundColor(Color(red: 0.12, green: 0.16, blue: 0.22))

      if totalDeletedCount == 0 {
        Text("No deletions yet.")
          .font(AppFont.body(14))
          .foregroundColor(Color(red: 0.40, green: 0.46, blue: 0.56))
      } else {
        Text("Deleted photos: \(totalDeletedCount)")
          .font(AppFont.body(15))
          .foregroundColor(Color(red: 0.38, green: 0.46, blue: 0.54))
        Text("Estimated space freed: \(totalDeletedBytesText)")
          .font(AppFont.body(15))
          .foregroundColor(Color(red: 0.38, green: 0.46, blue: 0.54))
      }
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(Color.white.opacity(0.92))
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
    )
  }

  private var reviewLimitBinding: Binding<Double> {
    Binding(
      get: { Double(reviewLimit) },
      set: { reviewLimit = Int($0.rounded()) }
    )
  }

  private var totalDeletedBytesText: String {
    guard totalDeletedBytes > 0 else { return "Unknown" }
    return ByteCountFormatter.string(fromByteCount: Int64(totalDeletedBytes), countStyle: .file)
  }

  private var settingsBackground: some View {
    LinearGradient(
      colors: [
        Color(red: 0.97, green: 0.97, blue: 0.98),
        Color(red: 0.92, green: 0.96, blue: 0.98),
      ],
      startPoint: .top,
      endPoint: .bottom
    )
    .ignoresSafeArea()
  }
}
