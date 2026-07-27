#if os(macOS)
import SwiftUI
import AppKit

struct FilesView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @StateObject private var store = FileFolderStore()
  @State private var counts: [FileReviewCategory: FileCounts] = [:]
  @State private var isCounting = false
  @State private var didTruncateCounts = false
  @State private var countAccessErrorCount = 0
  @State private var selectedCategory: FileReviewCategory?
  @State private var folderPendingRemoval: FileFolderStore.Folder?
  @State private var exclusionErrorMessage: String?
  @State private var isDropTargeted = false
  // Tracks the in-flight tally so a superseded count can't overwrite a newer one
  // when several triggers (.onChange/.onAppear) fire close together.
  @State private var countTask: Task<Void, Never>?
  @AppStorage("reviewMemoryOption") private var reviewMemoryOptionRawValue: String = ReviewMemoryOption.thirtyDays.rawValue

  private var reviewMemoryOption: ReviewMemoryOption {
    ReviewMemoryOption(rawValue: reviewMemoryOptionRawValue) ?? .thirtyDays
  }

  private var categoryColumns: [GridItem] {
    [
      GridItem(
        .adaptive(
          minimum: dynamicTypeSize >= .accessibility1 ? 420 : 320,
          maximum: 520
        ),
        spacing: 12,
        alignment: .top
      )
    ]
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          if store.folders.isEmpty {
            onboarding
          } else {
            grantedFoldersSection
            excludedFoldersSection
            categoriesSection
          }
        }
        .padding(20)
        .frame(maxWidth: 1080, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .top)
      }
      .background(AppColor.background)
      .navigationTitle("Files")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          if store.folders.isEmpty {
            if isCounting { ProgressView().controlSize(.small) }
          } else {
            Menu {
              Button {
                chooseFolder()
              } label: {
                Label("Add Review Folder…", systemImage: "folder.badge.plus")
              }
              Button {
                chooseExcludedFolder()
              } label: {
                Label("Exclude Subfolder…", systemImage: "folder.badge.minus")
              }
            } label: {
              Label("Manage Folders", systemImage: "plus")
            }
          }
        }
      }
      .navigationDestination(item: $selectedCategory) { category in
        FileReviewSessionView(
          category: category,
          folders: store.folders.map(\.url),
          excludedFolderPaths: store.excludedPaths,
          excludeFolder: { store.exclude($0) }
        )
      }
    }
    .focusedSceneValue(\.addFolderAction, { chooseFolder() })
    .confirmationDialog(
      "Stop reviewing this folder?",
      isPresented: Binding(
        get: { folderPendingRemoval != nil },
        set: { if !$0 { folderPendingRemoval = nil } }
      ),
      presenting: folderPendingRemoval
    ) { folder in
      Button("Stop Reviewing", role: .destructive) { store.remove(folder) }
      Button("Cancel", role: .cancel) {}
    } message: { folder in
      Text("SnipSnaps will lose access to “\(folder.name)”. No files are deleted — you can grant access again anytime.")
    }
    .alert("Folder Can't Be Excluded", isPresented: exclusionErrorBinding) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(exclusionErrorMessage ?? "Choose a subfolder inside one of your review folders.")
    }
    .onChange(of: store.folders) { _, _ in refreshCounts() }
    .onChange(of: store.excludedFolders) { _, _ in refreshCounts() }
    // Re-tally when a review session closes (files may have been trashed), the
    // same way HomeView refreshes counts after a Photos review.
    .onChange(of: selectedCategory) { _, newValue in
      if newValue == nil { refreshCounts() }
    }
    .onChange(of: reviewMemoryOptionRawValue) { _, _ in refreshCounts() }
    .onAppear { refreshCounts() }
    .onDisappear { countTask?.cancel() }
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

      Text("SnipSnaps can only see folders you pick here. You can also drag a folder here from Finder.")
        .font(.footnote)
        .foregroundStyle(.tertiary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(20)
    .background(AppColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(AppColor.primary, style: StrokeStyle(lineWidth: 2, dash: [7]))
        .opacity(isDropTargeted ? 1 : 0)
    )
    .dropDestination(for: URL.self) { urls, _ in
      addDroppedFolders(urls)
    } isTargeted: { isDropTargeted = $0 }
  }

  // A folder dragged from Finder carries an implicit user-selected grant, so we
  // can bookmark it immediately. Normalize first, then accept only directories.
  private func addDroppedFolders(_ urls: [URL]) -> Bool {
    var added = false
    for url in urls {
      let standardized = url.standardizedFileURL
      let isDirectory = (try? standardized.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
      if isDirectory {
        store.add(standardized)
        added = true
      }
    }
    return added
  }

  private func quickFolderButton(_ title: String, systemImage: String, url: URL?) -> some View {
    Button {
      chooseFolder(startingAt: url)
    } label: {
      Label("Add \(title)", systemImage: systemImage)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .controlSize(.large)
    .prominentActionButton()
    .tint(AppColor.primary)
    .disabled(url == nil)
  }

  // MARK: - Granted folders

  private var grantedFoldersSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("REVIEWED FOLDERS")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
      VStack(spacing: 8) {
        ForEach(store.folders) { folder in
          HStack(spacing: 12) {
            Image(systemName: "folder.fill")
              .foregroundStyle(AppColor.primary)
            VStack(alignment: .leading, spacing: 2) {
              Text(folder.name).font(.headline)
              if store.inaccessiblePaths.contains(folder.url.path) {
                Label("Couldn't access — remove and re-add this folder", systemImage: "exclamationmark.triangle.fill")
                  .font(.caption)
                  .foregroundStyle(.orange)
                  .lineLimit(1)
              } else {
                Text(folder.url.path)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
                  .truncationMode(.middle)
              }
            }
            Spacer()
            Button {
              FinderActions.revealInFinder(folder.url)
            } label: {
              Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
            Button(role: .destructive) {
              folderPendingRemoval = folder
            } label: {
              Image(systemName: "minus.circle.fill")
                // Borderless icon buttons on macOS don't reliably pick up the
                // destructive role's red, so set it explicitly (adapts Light/Dark).
                .foregroundStyle(AppColor.delete)
            }
            .buttonStyle(.borderless)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .help("Stop reviewing this folder")
            .accessibilityLabel("Stop reviewing \(folder.name)")
          }
          .padding(12)
          .background(AppColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
          .contextMenu {
            Button("Reveal in Finder") { FinderActions.revealInFinder(folder.url) }
            Button("Open in Finder") { FinderActions.open(folder.url) }
            Divider()
            Button("Stop Reviewing", role: .destructive) { folderPendingRemoval = folder }
          }
        }
      }
    }
  }

  private var excludedFoldersSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("EXCLUDED FOLDERS")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.secondary)
        Spacer()
        Button {
          chooseExcludedFolder()
        } label: {
          Label("Exclude Subfolder", systemImage: "plus")
        }
        .buttonStyle(.borderless)
        .help("Choose a subfolder SnipSnaps should never scan")
      }

      if store.excludedFolders.isEmpty {
        HStack(spacing: 12) {
          Image(systemName: "folder.badge.minus")
            .font(.title3)
            .foregroundStyle(.secondary)
          VStack(alignment: .leading, spacing: 2) {
            Text("No folders excluded")
              .font(.headline)
            Text("Exclude projects or other folders you already know you want to keep.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
        }
        .padding(12)
        .background(AppColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      } else {
        VStack(spacing: 8) {
          ForEach(store.excludedFolders) { folder in
            HStack(spacing: 12) {
              Image(systemName: "folder.fill.badge.minus")
                .foregroundStyle(.secondary)
              VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                  .font(.headline)
                Text(folder.url.path)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
                  .truncationMode(.middle)
              }
              Spacer()
              Button {
                FinderActions.revealInFinder(folder.url)
              } label: {
                Image(systemName: "arrow.up.forward.app")
              }
              .buttonStyle(.borderless)
              .help("Reveal in Finder")
              Button {
                store.include(folder)
              } label: {
                Image(systemName: "arrow.uturn.backward.circle.fill")
              }
              .buttonStyle(.borderless)
              .frame(width: 28, height: 28)
              .contentShape(Rectangle())
              .help("Review this folder again")
              .accessibilityLabel("Review \(folder.name) again")
            }
            .padding(12)
            .background(AppColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contextMenu {
              Button("Reveal in Finder") { FinderActions.revealInFinder(folder.url) }
              Button("Review This Folder Again") { store.include(folder) }
            }
          }
        }
      }

      Text("Excluded folders stay on your Mac and are skipped by every Files count, review, and duplicate scan.")
        .font(.footnote)
        .foregroundStyle(.tertiary)
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
      if let countWarningText {
        Label(countWarningText, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      LazyVGrid(columns: categoryColumns, alignment: .leading, spacing: 12) {
        ForEach(FileReviewCategory.allCases) { category in
          Button {
            selectedCategory = category
          } label: {
            FileCategoryCard(
              category: category,
              counts: counts[category],
              memoryActive: reviewMemoryOption != .never
            )
          }
          .buttonStyle(.plain)
          .interactiveCardHover()
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

  private func chooseExcludedFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = true
    panel.prompt = "Exclude"
    panel.message = "Choose subfolders SnipSnaps should skip in every Files scan."
    panel.directoryURL = store.folders.first?.url
    guard panel.runModal() == .OK else { return }

    let rejected = panel.urls.filter { !store.exclude($0) }
    if !rejected.isEmpty {
      exclusionErrorMessage = "Choose a subfolder inside a reviewed folder that isn't itself—or doesn't contain—another reviewed root. To stop reviewing a top-level folder, remove it from Reviewed Folders instead."
    }
  }

  private var exclusionErrorBinding: Binding<Bool> {
    Binding(
      get: { exclusionErrorMessage != nil },
      set: { if !$0 { exclusionErrorMessage = nil } }
    )
  }

  private func refreshCounts() {
    // Supersede any in-flight tally so its (now-stale) result is discarded rather
    // than racing to overwrite this one.
    countTask?.cancel()
    let folders = store.folders.map(\.url)
    let excludedFolderPaths = store.excludedPaths
    guard !folders.isEmpty else {
      counts = [:]
      didTruncateCounts = false
      countAccessErrorCount = 0
      isCounting = false
      return
    }
    isCounting = true
    didTruncateCounts = false
    countAccessErrorCount = 0
    let reviewed = FileReviewHistory.reviewedPaths(memoryOption: reviewMemoryOption)
    countTask = Task {
      let worker = Task.detached(priority: .utility) {
        FileLibrary.counts(
          folders: folders,
          reviewedPaths: reviewed,
          excludedFolderPaths: excludedFolderPaths
        )
      }
      let tally = await withTaskCancellationHandler(operation: {
        await worker.value
      }, onCancel: {
        worker.cancel()
      })
      if Task.isCancelled { return }
      await MainActor.run {
        counts = tally.counts
        didTruncateCounts = tally.truncated
        countAccessErrorCount = tally.accessErrorCount
        isCounting = false
      }
    }
  }

  private var countWarningText: String? {
    switch (didTruncateCounts, countAccessErrorCount > 0) {
    case (true, true):
      return "Counts are partial: scanned the first \(FileLibrary.maxFilesExamined.formatted()) files and skipped some inaccessible subfolders."
    case (true, false):
      return "Counts are partial: scanned the first \(FileLibrary.maxFilesExamined.formatted()) files."
    case (false, true):
      return "Some subfolders couldn't be scanned because macOS denied access."
    case (false, false):
      return nil
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
  let counts: FileCounts?
  let memoryActive: Bool

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
        if let summary = countSummary {
          Text(summary)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
      }
      Spacer()
      Text(displayCount)
        .font(.title2.weight(.bold))
        .foregroundStyle(.tertiary)
        .monospacedDigit()
    }
    .padding(16)
    .frame(maxWidth: .infinity)
    .background(AppColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    // Consolidate into one VoiceOver element with a clean label/value/hint so the
    // title, subtitle, count summary, and trailing count aren't read as fragments.
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(category.title)
    .accessibilityValue(countSummary ?? category.subtitle)
    .accessibilityHint(category.showsScanAction ? "Scans this folder set for duplicates" : "Opens \(category.title) review")
  }

  private var displayCount: String {
    if category.showsScanAction { return "Scan" }
    guard let counts else { return "…" }
    let value = memoryActive ? counts.notReviewed : counts.total
    return value > 9999 ? "9999+" : "\(value)"
  }

  private var countSummary: String? {
    guard !category.showsScanAction, let counts else { return nil }
    if memoryActive {
      return "\(counts.notReviewed) not reviewed · \(counts.total) total"
    }
    return "\(counts.total) total"
  }
}
#endif
