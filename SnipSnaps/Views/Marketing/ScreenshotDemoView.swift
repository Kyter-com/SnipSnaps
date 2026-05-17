#if DEBUG
import SwiftUI

struct ScreenshotDemoView: View {
  let screen: String

  var body: some View {
    Group {
      switch screen {
      case "review":
        demoShell(title: "Screenshots", subtitle: "7 of 20") {
          ScreenshotReviewDemo()
        }
      case "similar":
        demoShell(title: "Similar", subtitle: "2 kept · 3 marked · 1 year ago") {
          ScreenshotSimilarDemo()
        }
      case "details":
        demoShell(title: "Photo Details", subtitle: nil) {
          ScreenshotDetailsDemo()
        }
      case "summary":
        demoShell(title: "Review complete", subtitle: "15 kept · 5 marked") {
          ScreenshotSummaryDemo()
        }
      case "settings":
        ScreenshotSettingsDemo()
      default:
        ScreenshotHomeDemo()
      }
    }
    .background(AppColor.background)
  }

  private func demoShell<Content: View>(
    title: String,
    subtitle: String?,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.title2.weight(.semibold))
          .foregroundStyle(AppColor.text)
        if let subtitle {
          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 18)

      content()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct ScreenshotHomeDemo: View {
  private let cards = [
    ("Today", "Review your newest shots", "24", "sun.max.fill", Color.orange.opacity(0.18)),
    ("On This Day", "Photos from May 8 across the years", "88", "calendar", Color.blue.opacity(0.14)),
    ("Screenshots", "Clear the clutter fast", "143", "rectangle.on.rectangle", Color.red.opacity(0.13)),
    ("Similar Photos", "Review duplicate-looking groups", "SCAN", "square.stack.3d.up", Color.green.opacity(0.14)),
  ]

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text("Swipe fast, keep the best, clear the rest.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)

          VStack(spacing: 12) {
            ForEach(cards, id: \.0) { title, subtitle, count, image, tint in
              ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                  .fill(AppColor.card)
                Text(count)
                  .font(.system(size: 76, weight: .heavy, design: .rounded))
                  .foregroundStyle(.quaternary)
                  .frame(maxWidth: .infinity, alignment: .trailing)
                  .padding(.trailing, 16)
                HStack(spacing: 14) {
                  Image(systemName: image)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppColor.primary)
                    .frame(width: 42, height: 42)
                    .background(tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                  VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                      .font(.headline)
                    Text(subtitle)
                      .font(.subheadline)
                      .foregroundStyle(.secondary)
                    if title == "Screenshots" {
                      HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("Recent")
                        Image(systemName: "chevron.down")
                          .font(.caption2.weight(.bold))
                      }
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(.secondary)
                      .padding(.horizontal, 10)
                      .padding(.vertical, 6)
                      .background(Color(.tertiarySystemGroupedBackground), in: Capsule(style: .continuous))
                      .padding(.top, 2)
                    }
                  }
                  Spacer()
                }
                .padding(.horizontal, 16)
              }
              .frame(height: title == "Screenshots" ? 112 : 96)
            }
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
      }
      .navigationTitle("SnipSnaps")
      .background(AppColor.background)
    }
  }
}

private struct ScreenshotReviewDemo: View {
  var body: some View {
    VStack(spacing: 18) {
      HStack(spacing: 12) {
        Text("7 of 20")
          .font(.footnote.weight(.medium))
          .foregroundStyle(.secondary)
        ProgressView(value: 0.35)
          .tint(AppColor.primary)
      }
      .padding(.horizontal, 20)

      ScreenshotPhoto(seed: 4, label: "May 8, 2025 · 1 year ago")
        .padding(.horizontal, 20)

      Spacer(minLength: 0)

      HStack(spacing: 18) {
        Circle()
          .fill(AppColor.deleteBackground)
          .frame(width: 66, height: 66)
          .overlay(Image(systemName: "xmark").font(.title2.weight(.bold)).foregroundStyle(AppColor.delete))
        Spacer()
        Button("Undo") {}
          .font(.footnote.weight(.semibold))
          .buttonStyle(.bordered)
          .controlSize(.small)
        Spacer()
        Circle()
          .fill(AppColor.keepBackground)
          .frame(width: 66, height: 66)
          .overlay(Image(systemName: "checkmark").font(.title2.weight(.bold)).foregroundStyle(AppColor.success))
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 12)
    }
  }
}

private struct ScreenshotSimilarDemo: View {
  var body: some View {
    VStack(spacing: 16) {
      HStack(spacing: 12) {
        Text("1 of 8")
          .font(.footnote.weight(.medium))
          .foregroundStyle(.secondary)
        ProgressView(value: 0.125)
          .tint(AppColor.primary)
      }
      .padding(.horizontal, 20)

      HStack(spacing: 12) {
        ForEach(0..<2) { index in
          ScreenshotPhoto(seed: index + 8, label: "Keep")
            .overlay {
              RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(index == 0 ? AppColor.primary : AppColor.success, lineWidth: 4)
            }
        }
      }
      .padding(.horizontal, 20)

      Spacer()

      Button {
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "checklist")
            .frame(width: 18)
          Text("Mark Extras")
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .frame(width: 112, alignment: .leading)
          Text("3")
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(AppColor.primary)
            .frame(width: 24, height: 24)
            .background(.white.opacity(0.9), in: Capsule(style: .continuous))
        }
          .font(.headline)
          .frame(maxWidth: .infinity, minHeight: 24)
      }
      .buttonStyle(.borderedProminent)
      .tint(AppColor.primary)
      .controlSize(.large)
      .padding(.horizontal, 20)
      .padding(.bottom, 12)
    }
  }
}

private struct ScreenshotDetailsDemo: View {
  private let rows = [
    ("Date", "May 8, 2025 at 4:12 PM"),
    ("Age", "1 year ago"),
    ("File size", "4.8 MB"),
    ("Resolution", "4032 x 3024"),
    ("Type", "Live Photo"),
  ]

  var body: some View {
    VStack(spacing: 14) {
      ScreenshotPhoto(seed: 14, label: "Details")
        .frame(height: 280)
        .padding(.horizontal, 20)

      VStack(spacing: 10) {
        ForEach(rows, id: \.0) { label, value in
          HStack {
            Text(label)
              .font(.subheadline)
            Spacer()
            Text(value)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.trailing)
          }
          .padding(14)
          .background(AppColor.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
      }
      .padding(.horizontal, 20)
    }
  }
}

private struct ScreenshotSummaryDemo: View {
  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Text("Marked for review")
              .font(.subheadline.weight(.semibold))
            Spacer()
            Text("28.4 MB")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }

          ForEach(0..<2) { group in
            VStack(alignment: .leading, spacing: 8) {
              Text("1 kept · 2 marked")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
              HStack(spacing: 8) {
                ForEach(0..<3) { index in
                  ScreenshotPhoto(seed: group * 4 + index + 20, label: "")
                    .frame(width: 74, height: 74)
                }
                Spacer()
              }
            }
            .padding(10)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
          }
        }
        .padding(16)
        .background(AppColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

        Button(role: .destructive) {
        } label: {
          Label("Delete 5 Photos", systemImage: "trash.fill")
            .font(.headline)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppColor.delete)
        .controlSize(.large)
      }
      .padding(20)
    }
  }
}

private struct ScreenshotSettingsDemo: View {
  var body: some View {
    NavigationStack {
      Form {
        Section {
          HStack {
            Text("Review Size")
            Spacer()
            Text("20")
              .foregroundStyle(.secondary)
          }
        } header: {
          Text("Review")
        } footer: {
          Text("How many photos appear in each session.")
        }

        Section("Lifetime Stats") {
          LabeledContent("Deleted photos", value: "184")
          LabeledContent("Space freed", value: "1.8 GB")
        }

        Section {
          HStack {
            Image(systemName: "arrow.counterclockwise.circle.fill")
              .font(.title2)
              .foregroundStyle(.red)
              .frame(width: 28, height: 28)
            Text("Reset Local Settings")
              .foregroundStyle(.red)
            Spacer()
            Image(systemName: "chevron.right")
              .font(.footnote)
              .fontWeight(.semibold)
              .foregroundStyle(Color(UIColor.tertiaryLabel))
          }
        } footer: {
          Text("Resets review size, screenshot sorting, and lifetime deleted stats on this device. This does not delete photos.")
        }
      }
      .navigationTitle("Settings")
    }
  }
}

private struct ScreenshotPhoto: View {
  let seed: Int
  let label: String

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      LinearGradient(
        colors: palette,
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      GeometryReader { proxy in
        let width = proxy.size.width
        let height = proxy.size.height
        ZStack {
          ForEach(0..<5) { index in
            Circle()
              .fill(.white.opacity(0.18))
              .frame(width: width * CGFloat(0.12 + Double(index) * 0.035))
              .position(x: width * CGFloat(0.16 + Double(index) * 0.17), y: height * CGFloat(0.14 + Double(index % 2) * 0.18))
          }
          ForEach(0..<5) { index in
            Triangle()
              .fill(Color.black.opacity(0.17))
              .frame(width: width * 0.48, height: height * CGFloat(0.26 + Double(index % 3) * 0.04))
              .position(x: width * CGFloat(0.06 + Double(index) * 0.22), y: height * 0.7)
          }
          Rectangle()
            .fill(palette.last?.opacity(0.65) ?? .blue.opacity(0.55))
            .frame(height: height * 0.28)
            .position(x: width / 2, y: height * 0.88)
        }
      }

      if !label.isEmpty {
        Text(label)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white)
          .padding(10)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
  }

  private var palette: [Color] {
    switch seed % 5 {
    case 0:
      return [.orange.opacity(0.34), .blue.opacity(0.5)]
    case 1:
      return [.mint.opacity(0.42), .green.opacity(0.58)]
    case 2:
      return [.yellow.opacity(0.34), .indigo.opacity(0.5)]
    case 3:
      return [.pink.opacity(0.32), .purple.opacity(0.52)]
    default:
      return [.teal.opacity(0.34), .cyan.opacity(0.52)]
    }
  }
}

private struct Triangle: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.midX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}
#endif
