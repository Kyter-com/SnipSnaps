#if os(macOS)
import SwiftUI
import AppKit

struct FilesView: View {
  @StateObject private var store = FileFolderStore()
  @State private var counts: [FileReviewCategory: Int] = [:]
  @State private var isCounting = false
  @State private var selectedCategory: FileReviewCategory?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          if store.folders.isEmpty {
            onboarding
          } else {
            grantedFoldersSection
            categoriesSection
          }
        }
        .padding(20)
      }
      .background(AppColor.background)
      .navigationTitle("Files")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          if store.folders.isEmpty {
            if isCounting { ProgressView().controlSize(.small) }
          } else {
            Button {
              chooseFolder()
            } label: {
              Label("Add Folder", systemImage: "plus")
            }
          }
        }
      }
      .navigationDestination(item: $selectedCategory) { category in
        FileReviewSessionView(category: category, folders: store.folders.map(\.url))
      }
    }
    .onChange(of: store.folders) { _, _ in refreshCounts() }
    // Re-tally when a review session closes (files may have been trashed), the
    // same way HomeView refreshes counts after a Photos review.
    .onChange(of: selectedCategory) { _, newValue in
      if newValue == nil { refreshCounts() }
    }
    .onAppear { refreshCounts() }
  }

  // MARK: - Onboarding

  private var onboarding: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 8) {
        Image(systemName: "folder.badge.plus")
          .font(.system(size: 44))
          .foregroundStyle(AppColor.primary)
        Text("Clean up your files")
          .font(.title2.weight(.semibold))
        Text("Choose a folder and SnipSnaps helps you review what's inside — big files, old files, leftover screenshots. Only the files you confirm are moved to the Trash, so nothing is deleted permanently.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(spacing: 10) {
        quickFolderButton("Downloads", systemImage: "arrow.down.circle.fill", url: Self.downloadsURL)
        quickFolderButton("Desktop", systemImage: "menubar.dock.rectangle", url: Self.desktopURL)
        quickFolderButton("Documents", systemImage: "doc.fill", url: Self.documentsURL)
        Button {
          chooseFolder()
        } label: {
          Label("Choose Another Folder…", systemImage: "folder")
            .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
      }

      Text("SnipSnaps can only see folders you pick here.")
        .font(.footnote)
        .foregroundStyle(.tertiary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(20)
    .background(AppColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private func quickFolderButton(_ title: String, systemImage: String, url: URL?) -> some View {
    Button {
      chooseFolder(startingAt: url)
    } label: {
      Label("Add \(title)", systemImage: systemImage)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .controlSize(.large)
    .buttonStyle(.borderedProminent)
    .tint(AppColor.primary)
    .disabled(url == nil)
  }

  // MARK: - Granted folders

  private var grantedFoldersSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("FOLDERS")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
      VStack(spacing: 8) {
        ForEach(store.folders) { folder in
          HStack(spacing: 12) {
            Image(systemName: "folder.fill")
              .foregroundStyle(AppColor.primary)
            VStack(alignment: .leading, spacing: 2) {
              Text(folder.name).font(.headline)
              Text(folder.url.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            }
            Spacer()
            Button(role: .destructive) {
              store.remove(folder)
            } label: {
              Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Stop reviewing this folder")
          }
          .padding(12)
          .background(AppColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
      }
    }
  }

  // MARK: - Categories

  private var categoriesSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("REVIEW")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.secondary)
        if isCounting {
          ProgressView().controlSize(.small)
        }
      }
      VStack(spacing: 12) {
        ForEach(FileReviewCategory.allCases) { category in
          Button {
            selectedCategory = category
          } label: {
            FileCategoryCard(category: category, count: counts[category])
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  // MARK: - Folder picking

  private func chooseFolder(startingAt directory: URL? = nil) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = true
    panel.prompt = "Grant Access"
    panel.message = "Choose a folder for SnipSnaps to review. Only files you confirm are moved to the Trash."
    if let directory { panel.directoryURL = directory }
    guard panel.runModal() == .OK else { return }
    for url in panel.urls {
      store.add(url)
    }
  }

  private func refreshCounts() {
    let folders = store.folders.map(\.url)
    guard !folders.isEmpty else {
      counts = [:]
      return
    }
    isCounting = true
    Task {
      let tally = await Task.detached(priority: .utility) {
        FileLibrary.counts(folders: folders)
      }.value
      await MainActor.run {
        counts = tally
        isCounting = false
      }
    }
  }

  private static var downloadsURL: URL? {
    try? FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
  }
  private static var desktopURL: URL? {
    try? FileManager.default.url(for: .desktopDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
  }
  private static var documentsURL: URL? {
    try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
  }
}

private struct FileCategoryCard: View {
  let category: FileReviewCategory
  let count: Int?

  var body: some View {
    HStack(spacing: 16) {
      Image(systemName: category.systemImage)
        .font(.title3.weight(.semibold))
        .foregroundStyle(AppColor.primary)
        .frame(width: 44, height: 44)
        .background(AppColor.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      VStack(alignment: .leading, spacing: 3) {
        Text(category.title)
          .font(.headline)
          .foregroundStyle(AppColor.text)
        Text(category.subtitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Text(countText)
        .font(.title2.weight(.bold))
        .foregroundStyle(.tertiary)
        .monospacedDigit()
    }
    .padding(16)
    .frame(maxWidth: .infinity)
    .background(AppColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private var countText: String {
    guard let count else { return "…" }
    return count > 9999 ? "9999+" : "\(count)"
  }
}
#endif
