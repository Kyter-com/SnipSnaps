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
      Form {
        Section(header: Text("Review Settings")) {
            VStack(alignment: .leading) {
                Text("Review Size")
                Text("Choose how many photos appear in each session.")
                    .font(.caption)
                    .foregroundColor(AppColor.subtext)
            }
            HStack {
                Text("\(reviewLimit) photos")
                Spacer()
                Stepper("", value: $reviewLimit, in: 10...100, step: 5)
                    .labelsHidden()
            }
            Slider(value: reviewLimitBinding, in: 10...100, step: 5)
                .tint(AppColor.primary)
        }
        
        Section(header: Text("Lifetime Stats")) {
            if totalDeletedCount == 0 {
                Text("No deletions yet.")
            } else {
                HStack {
                    Text("Deleted photos")
                    Spacer()
                    Text("\(totalDeletedCount)")
                        .foregroundColor(AppColor.subtext)
                }
                HStack {
                    Text("Estimated space freed")
                    Spacer()
                    Text(totalDeletedBytesText)
                        .foregroundColor(AppColor.subtext)
                }
            }
        }
      }
      .navigationTitle("Settings")
    }
  }

  private var reviewLimitBinding: Binding<Double> {
    Binding(
      get: { Double(reviewLimit) },
      set: { reviewLimit = Int($0.rounded()) }
    )
  }

  private var totalDeletedBytesText: String {
    guard totalDeletedBytes > 0 else { return "0 KB" }
    return ByteCountFormatter.string(fromByteCount: Int64(totalDeletedBytes), countStyle: .file)
  }
}
