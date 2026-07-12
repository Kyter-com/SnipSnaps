#if os(macOS) && DEBUG
import SwiftUI
import AppKit

/// macOS-only marketing demo. Rendered in place of the real app shell when the
/// process is launched with `SNIPSNAPS_SCREENSHOT_SCREEN=<screen>` (see
/// `ContentView`). It reproduces each marketing screen inside the *real* Mac
/// `NavigationSplitView` sidebar chrome — so the App Store window screenshots
/// carry the native title bar, traffic lights, and sidebar — but fills the
/// detail pane with curated static content instead of the live Photos library
/// or granted folders (which can't be seeded headlessly on the Mac the way the
/// iOS simulator can).
///
/// Screens: `home` (Photos), `review`, `similar`, `files`.
/// The window is pinned to a fixed size so every capture is identical; the
/// capture script (`marketing/app-store-screenshots/capture-mac.sh`) grabs the
/// window with `screencapture` and `generate.py` composites the marketing frame.
struct MacScreenshotDemoView: View {
  let screen: String

  private var sidebarSelection: SidebarItem {
    screen == "files" ? .files : .photos
  }

  private var forcedColorScheme: ColorScheme {
    ProcessInfo.processInfo.environment["SNIPSNAPS_SCREENSHOT_APPEARANCE"]?.lowercased() == "dark" ? .dark : .light
  }

  var body: some View {
    NavigationSplitView {
      List(selection: .constant(sidebarSelection)) {
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
      NavigationStack {
        detail
          .background(AppColor.background)
      }
    }
    .tint(AppColor.primary)
    // The chosen App Store appearance for the Mac shots. Forced so the capture
    // doesn't inherit the machine's Dark Mode. Set SNIPSNAPS_SCREENSHOT_APPEARANCE
    // to `dark` to shoot Dark-Mode shots; defaults to Light.
    .preferredColorScheme(forcedColorScheme)
    // Pin the window to a fixed 16:10-ish size so every capture is identical and
    // composites cleanly onto the 2880×1800 canvas.
    .frame(width: 1200, height: 760)
    // Make the window key/active so the capture shows colored traffic lights and
    // a crisp title bar instead of the dimmed inactive-window chrome.
    .onAppear { NSApp.activate(ignoringOtherApps: true) }
  }

  @ViewBuilder
  private var detail: some View {
    switch screen {
    case "review": DemoReviewScreen()
    case "similar": DemoSimilarScreen()
    case "files": DemoFilesScreen()
    default: DemoPhotosHomeScreen()
    }
  }
}

// MARK: - Photos home

private struct DemoHomeMode: Identifiable {
  let mode: ReviewMode
  let count: String
  var id: String { mode.id }
}

private struct DemoHomeSection: Identifiable {
  let title: String
  let modes: [DemoHomeMode]
  var id: String { title }
}

private struct DemoPhotosHomeScreen: View {
  private let sections: [DemoHomeSection] = [
    DemoHomeSection(title: "Quick Clean", modes: [
      DemoHomeMode(mode: .today, count: "24"),
      DemoHomeMode(mode: .screenshots, count: "143"),
      DemoHomeMode(mode: .oldScreenshots, count: "61"),
      DemoHomeMode(mode: .random, count: "500+"),
    ]),
    DemoHomeSection(title: "Space Savers", modes: [
      DemoHomeMode(mode: .videos, count: "18"),
      DemoHomeMode(mode: .screenRecordings, count: "7"),
      DemoHomeMode(mode: .largePhotos, count: "42"),
      DemoHomeMode(mode: .similar, count: "Scan"),
    ]),
    DemoHomeSection(title: "Library Finds", modes: [
      DemoHomeMode(mode: .onThisDay, count: "88"),
      DemoHomeMode(mode: .livePhotos, count: "33"),
      DemoHomeMode(mode: .bursts, count: "12"),
      DemoHomeMode(mode: .oldFavorites, count: "15"),
    ]),
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        ForEach(sections) { section in
          VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
              .font(.footnote.weight(.semibold))
              .foregroundStyle(.secondary)
              .textCase(.uppercase)
              .padding(.horizontal, 4)
            VStack(spacing: 12) {
              ForEach(section.modes) { item in
                DemoCard(
                  systemImage: item.mode.systemImage,
                  title: item.mode.title,
                  subtitle: item.mode.subtitle,
                  trailing: item.count
                )
              }
            }
          }
        }
      }
      .padding(20)
    }
    .background(AppColor.background)
    .navigationTitle("Photos")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        // A Button (not a bare Image) so it gets the real circular toolbar-button
        // chrome — matching HomeView's Refresh control.
        Button {
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .help("Refresh counts")
      }
    }
  }
}

// MARK: - Photo review

private struct DemoReviewScreen: View {
  var body: some View {
    VStack(spacing: 18) {
      HStack(spacing: 14) {
        Text("7 of 20")
          .font(.callout.weight(.medium))
          .foregroundStyle(.secondary)
          .monospacedDigit()
        ProgressView(value: 0.35)
          .tint(AppColor.primary)
      }
      .padding(.horizontal, 32)
      .padding(.top, 22)

      Spacer(minLength: 0)

      ZStack(alignment: .topTrailing) {
        Image("DemoReview")
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: 448, height: 560)
          .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

        Label("May 8, 2025 · 4.8 MB", systemImage: "info.circle")
          .font(.callout.weight(.medium))
          .foregroundStyle(.white)
          .padding(.horizontal, 14)
          .padding(.vertical, 9)
          .background(.ultraThinMaterial, in: Capsule(style: .continuous))
          .environment(\.colorScheme, .dark)
          .padding(14)
      }

      Spacer(minLength: 0)

      HStack(spacing: 26) {
        DemoDecisionButton(systemName: "xmark", tint: AppColor.delete, background: AppColor.deleteBackground)
        Button("Undo") {}
          .buttonStyle(.bordered)
          .controlSize(.large)
        DemoDecisionButton(systemName: "checkmark", tint: AppColor.success, background: AppColor.keepBackground)
      }
      .padding(.bottom, 28)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AppColor.background)
    .navigationTitle("Today")
  }
}

private struct DemoDecisionButton: View {
  let systemName: String
  let tint: Color
  let background: Color

  var body: some View {
    Circle()
      .fill(background)
      .frame(width: 76, height: 76)
      .overlay(
        Image(systemName: systemName)
          .font(.title.weight(.bold))
          .foregroundStyle(tint)
      )
  }
}

// MARK: - Similar

/// Mirrors the shipping `SimilarReviewSessionView` swipe flow: the near-duplicate
/// group runs as a filmstrip across the top (active shot outlined, kept shots
/// checked), one large card in the middle, and the same X / Skip / Undo / ✓
/// decision bar as the Photos review. The old two-up "Keep / Keep + Mark Extras"
/// comparison was retired from the app, so the marketing shot follows suit.
private struct DemoSimilarScreen: View {
  private struct Thumb: Identifiable {
    let image: String
    let state: DemoThumbState
    let id = UUID()
  }

  private let group: [Thumb] = [
    Thumb(image: "DemoSimilarA", state: .active),
    Thumb(image: "DemoSimilarB", state: .kept),
    Thumb(image: "DemoSimilarA", state: .plain),
    Thumb(image: "DemoSimilarB", state: .plain),
  ]

  var body: some View {
    VStack(spacing: 16) {
      VStack(spacing: 14) {
        HStack(spacing: 14) {
          Text("Group 1 of 8")
            .font(.callout.weight(.medium))
            .foregroundStyle(.secondary)
            .monospacedDigit()
          ProgressView(value: 0.125)
            .tint(AppColor.primary)
        }

        HStack(spacing: 12) {
          ForEach(group) { thumb in
            DemoSimilarThumbnail(imageName: thumb.image, state: thumb.state)
          }
          Spacer(minLength: 0)
        }
      }
      .padding(.horizontal, 28)
      .padding(.top, 20)

      Spacer(minLength: 0)

      Image("DemoSimilarA")
        .resizable()
        .aspectRatio(contentMode: .fill)
        .frame(width: 468, height: 452)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

      Spacer(minLength: 0)

      HStack(spacing: 22) {
        DemoDecisionButton(systemName: "xmark", tint: AppColor.delete, background: AppColor.deleteBackground)
        Button("Skip Group") {}
          .buttonStyle(.bordered)
          .controlSize(.large)
        Button("Undo") {}
          .buttonStyle(.bordered)
          .controlSize(.large)
        DemoDecisionButton(systemName: "checkmark", tint: AppColor.success, background: AppColor.keepBackground)
      }
      .padding(.bottom, 28)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AppColor.background)
    .navigationTitle("Similar")
  }
}

private enum DemoThumbState {
  case active, kept, plain
}

/// One filmstrip cell in the Similar group, matching the shipping within-group
/// strip: the active shot is outlined in the accent, kept shots wear a green
/// check, undecided shots sit under a hairline border.
private struct DemoSimilarThumbnail: View {
  let imageName: String
  let state: DemoThumbState

  var body: some View {
    Image(imageName)
      .resizable()
      .aspectRatio(contentMode: .fill)
      .frame(width: 68, height: 68)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay(alignment: .topTrailing) {
        if state == .kept {
          Image(systemName: "checkmark.circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, AppColor.success)
            .padding(4)
        }
      }
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .strokeBorder(
            state == .active ? AppColor.primary : AppColor.separator,
            lineWidth: state == .active ? 3 : 0.5
          )
      }
  }
}

// MARK: - Files

private struct DemoFilesScreen: View {
  private struct Folder: Identifiable {
    let name: String
    let path: String
    var id: String { path }
  }

  private struct Category: Identifiable {
    let category: FileReviewCategory
    let count: String
    let summary: String?
    var id: String { category.id }
  }

  private let folders: [Folder] = [
    Folder(name: "Downloads", path: "/Users/johnappleseed/Downloads"),
    Folder(name: "Desktop", path: "/Users/johnappleseed/Desktop"),
    Folder(name: "Documents", path: "/Users/johnappleseed/Documents"),
  ]

  // Every card is memory-on and matches the real FilesView: the prominent number
  // is the *not-reviewed* count (displayCount = notReviewed when memory is on),
  // and the summary is the "N not reviewed · M total" form with no thousands
  // separator — exactly how the shipping UI renders. Keep count == the first
  // number in summary on every card.
  private let categories: [Category] = [
    Category(category: .everything, count: "1180", summary: "1180 not reviewed · 1204 total"),
    Category(category: .large, count: "10", summary: "10 not reviewed · 12 total"),
    Category(category: .old, count: "196", summary: "196 not reviewed · 208 total"),
    Category(category: .screenshots, count: "44", summary: "44 not reviewed · 47 total"),
    Category(category: .duplicates, count: "Scan", summary: nil),
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 10) {
          Text("FOLDERS")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
          VStack(spacing: 8) {
            ForEach(folders) { folder in
              HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                  .foregroundStyle(AppColor.primary)
                VStack(alignment: .leading, spacing: 2) {
                  Text(folder.name).font(.headline)
                  Text(folder.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                Spacer()
                Image(systemName: "arrow.up.forward.app")
                  .foregroundStyle(.secondary)
                // Matches the shipping FilesView remove button, which sets the
                // destructive role's red explicitly (borderless macOS icon buttons
                // don't reliably inherit it). The open-in-Finder arrow stays neutral.
                Image(systemName: "minus.circle.fill")
                  .foregroundStyle(AppColor.delete)
              }
              .padding(12)
              .background(AppColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
          }
        }

        VStack(alignment: .leading, spacing: 10) {
          Text("REVIEW")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
          VStack(spacing: 12) {
            ForEach(categories) { item in
              DemoCard(
                systemImage: item.category.systemImage,
                title: item.category.title,
                subtitle: item.category.subtitle,
                trailing: item.count,
                summary: item.summary
              )
            }
          }
        }
      }
      .padding(20)
    }
    .background(AppColor.background)
    .navigationTitle("Files")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        // A Button (not a bare Label) so it gets the real circular toolbar-button
        // chrome — matching FilesView's Add Folder control.
        Button {
        } label: {
          Label("Add Folder", systemImage: "plus")
        }
      }
    }
  }
}

// MARK: - Shared card

/// The raised card used on both the Photos home and Files surfaces — mirrors the
/// real app's `FileCategoryCard` / review-mode card layout so the marketing
/// screens read as the shipping UI.
private struct DemoCard: View {
  let systemImage: String
  let title: String
  let subtitle: String
  var trailing: String
  var summary: String? = nil

  var body: some View {
    HStack(spacing: 16) {
      Image(systemName: systemImage)
        .font(.title3.weight(.semibold))
        .foregroundStyle(AppColor.primary)
        .frame(width: 44, height: 44)
        .background(AppColor.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.headline)
          .foregroundStyle(AppColor.text)
        Text(subtitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
        if let summary {
          Text(summary)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
      }
      Spacer()
      Text(trailing)
        .font(.title2.weight(.bold))
        .foregroundStyle(.tertiary)
        .monospacedDigit()
    }
    .padding(16)
    .frame(maxWidth: .infinity)
    .background(AppColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}
#endif
