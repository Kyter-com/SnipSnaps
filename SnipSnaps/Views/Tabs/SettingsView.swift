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
        Section {
          Stepper(value: $reviewLimit, in: 10...100, step: 5) {
            HStack {
              Text("Review Size")
              Spacer()
              Text("\(reviewLimit)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
          }
        } header: {
          Text("Review")
        } footer: {
          Text("How many photos appear in each session.")
        }

        Section("Lifetime Stats") {
          if totalDeletedCount == 0 {
            Text("No deletions yet.")
              .foregroundStyle(.secondary)
          } else {
            LabeledContent("Deleted photos", value: "\(totalDeletedCount)")
            LabeledContent("Space freed", value: totalDeletedBytesText)
          }
        }
      }
      .navigationTitle("Settings")
    }
  }

  private var totalDeletedBytesText: String {
    guard totalDeletedBytes > 0 else { return "0 KB" }
    return ByteCountFormatter.string(fromByteCount: Int64(totalDeletedBytes), countStyle: .file)
  }
}
