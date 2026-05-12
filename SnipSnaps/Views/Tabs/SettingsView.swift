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

        Section("Support") {
          Button {
            if let url = URL(string: "https://github.com/Kyter-com/SnipSnaps") {
              UIApplication.shared.open(url)
            }
          } label: {
            HStack {
              Image("GitHub")
                .font(.title2)
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)

              Text("GitHub")
                .foregroundStyle(.primary)
              Spacer()
              Image(systemName: "arrow.up.forward")
                .font(.footnote)
                .foregroundStyle(Color(UIColor.tertiaryLabel))
            }
          }
          settingsLink(
            title: "Support",
            systemImage: "questionmark.circle.fill",
            tint: .blue,
            url: "https://kyter.com/snipsnaps/support/"
          )
          Button {
            sendFeedback()
          } label: {
            settingsRow(
              title: "Send Feedback",
              systemImage: "envelope.circle.fill",
              tint: .blue,
              trailingSystemImage: "chevron.right"
            )
          }
        }

        Section("Legal") {
          settingsLink(
            title: "End User License Agreement",
            systemImage: "doc.circle.fill",
            tint: .gray,
            url: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
          )
          settingsLink(
            title: "Privacy Policy",
            systemImage: "hand.raised.circle.fill",
            tint: .blue,
            url: "https://kyter.com/snipsnaps/privacy/"
          )
          settingsLink(
            title: "Terms & Conditions",
            systemImage: "checkmark.circle.fill",
            tint: .mint,
            url: "https://kyter.com/snipsnaps/terms/"
          )
        }
      }
      .navigationTitle("Settings")
    }
  }

  private var totalDeletedBytesText: String {
    guard totalDeletedBytes > 0 else { return "0 KB" }
    return ByteCountFormatter.string(fromByteCount: Int64(totalDeletedBytes), countStyle: .file)
  }

  private func settingsLink(
    title: String,
    systemImage: String,
    tint: Color,
    url: String
  ) -> some View {
    Button {
      if let url = URL(string: url) {
        UIApplication.shared.open(url)
      }
    } label: {
      settingsRow(
        title: title,
        systemImage: systemImage,
        tint: tint,
        trailingSystemImage: "arrow.up.forward"
      )
    }
  }

  private func settingsRow(
    title: String,
    systemImage: String,
    tint: Color,
    trailingSystemImage: String
  ) -> some View {
    HStack {
      Image(systemName: systemImage)
        .font(.title2)
        .foregroundStyle(tint)
        .frame(width: 28, height: 28)

      Text(title)
        .foregroundStyle(.primary)
      Spacer()
      Image(systemName: trailingSystemImage)
        .font(.footnote)
        .fontWeight(trailingSystemImage == "chevron.right" ? .semibold : .regular)
        .foregroundStyle(Color(UIColor.tertiaryLabel))
    }
  }

  private func sendFeedback() {
    let email = "dev@kyter.com"
    let subject = "SnipSnaps App Feedback"
    let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

    if let url = URL(string: "mailto:\(email)?subject=\(encodedSubject)") {
      UIApplication.shared.open(url)
    }
  }
}
