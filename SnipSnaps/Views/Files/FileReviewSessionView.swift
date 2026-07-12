#if os(macOS)
import SwiftUI
import AppKit
import QuickLook
import QuickLookThumbnailing

struct FileReviewSessionView: View {
  let category: FileReviewCategory
  let folders: [URL]

  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isScanning = true
  @State private var items: [FileItem] = []
  @State private var index = 0
  @State private var kept: [FileItem] = []
  @State private var toDelete: [FileItem] = []
  @State private var lastUndo: UndoStep?
  @State private var showSummary = false
  @State private var deleteInProgress = false
  @State private var resultMessage: String?
  @State private var resultIsWarning = false
  @State private var deletedCount = 0
  @State private var dragOffset: CGSize = .zero
  @State private var quickLookURL: URL?
  @State private var scanTask: Task<Void, Never>?
  @State private var didTruncate = false
  @State private var accessErrorCount = 0
  @State private var trashFailures: [String] = []
  // Real in-Trash locations of everything this session moved, so "Show in Trash"
  // can select them in the actual Trash (the sandbox hides the ~/.Trash path).
  @State private var trashedURLs: [URL] = []
  // The Remember-Reviewed window in effect when this scan started. Snapshotting it
  // keeps the scan exclusion and mark/unmark consistent even if the user changes
  // the setting mid-session (the .session and persistent stores are different).
  @State private var sessionMemoryOption: ReviewMemoryOption = .thirtyDays
  // Shared with the Photos review so "Review Size" and the lifetime "Space
  // freed" stats behave the same across both surfaces.
  @AppStorage("reviewLimit") private var reviewLimit: Int = 20
  @AppStorage("totalDeletedCount") private var totalDeletedCount: Int = 0
  @AppStorage("totalDeletedBytes") private var totalDeletedBytes: Int = 0
  @AppStorage("reviewMemoryOption") private var reviewMemoryOptionRawValue: String = ReviewMemoryOption.thirtyDays.rawValue
  @AppStorage("fileSortOption") private var fileSortOptionRawValue: String = FileSortOption.largest.rawValue

  private var fileSortOption: FileSortOption {
    FileSortOption(rawValue: fileSortOptionRawValue) ?? .largest
  }

  private struct UndoStep {
    let item: FileItem
    let decision: FileDecision
    let index: Int
  }

  private var reviewMemoryOption: ReviewMemoryOption {
    ReviewMemoryOption(rawValue: reviewMemoryOptionRawValue) ?? .thirtyDays
  }

  private var current: FileItem? {
    items.indices.contains(index) ? items[index] : nil
  }

  var body: some View {
    ZStack {
      AppColor.background.ignoresSafeArea()
      if isScanning {
        scanningView
      } else if items.isEmpty {
        emptyView
      } else if showSummary {
        summaryView
      } else {
        reviewView
      }
      // The pushed NavigationStack already shows a Back chevron, so no visible close
      // button is needed; keep Esc as an invisible accelerator on every state.
      Button("Close") { dismiss() }
        .keyboardShortcut(.cancelAction)
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
    .navigationTitle(category.title)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        // Re-sorting re-scans from scratch, which would discard in-progress
        // decisions (and leave them marked reviewed). Lock it once the user has
        // started deciding so no queued keep/trash choices are silently lost.
        sortMenu
          .disabled(isScanning || !kept.isEmpty || !toDelete.isEmpty)
      }
    }
    .onAppear(perform: load)
    .onDisappear { scanTask?.cancel() }
    .onChange(of: fileSortOptionRawValue) { _, _ in
      if isScanning || (kept.isEmpty && toDelete.isEmpty) { load() }
    }
    .focusedSceneValue(\.reviewActions, reviewActions)
    .quickLookPreview($quickLookURL)
    .alert("Some files couldn't be moved", isPresented: trashFailureBinding) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(trashFailureMessage)
    }
  }

  private var trashFailureBinding: Binding<Bool> {
    Binding(get: { !trashFailures.isEmpty }, set: { if !$0 { trashFailures = [] } })
  }

  private var trashFailureMessage: String {
    let names = trashFailures.prefix(5).joined(separator: "\n")
    let extra = trashFailures.count > 5 ? "\n…and \(trashFailures.count - 5) more" : ""
    return "These items are still in place (they may be locked or in use):\n\(names)\(extra)"
  }

  private var sortMenu: some View {
    Menu {
      Picker("Sort By", selection: $fileSortOptionRawValue) {
        ForEach(FileSortOption.allCases) { option in
          Label(option.title, systemImage: option.systemImage).tag(option.rawValue)
        }
      }
      .pickerStyle(.inline)
    } label: {
      Label("Sort", systemImage: "arrow.up.arrow.down")
    }
    .help("Change the review order")
  }

  // Desktop file keys (Quick Look / Reveal / Open) live on hidden buttons so they
  // fire from anywhere in the review window without stealing focus.
  private var fileKeyboardShortcuts: some View {
    ZStack {
      // Forward-delete is the second Trash key (← is bound on the visible button),
      // matching the Photos review where both ← and Delete trash the current item.
      Button("Move to Trash") { applyDecision(.delete) }
        .keyboardShortcut(.delete, modifiers: [])
      Button("Quick Look") { toggleQuickLook() }
        .keyboardShortcut(.space, modifiers: [])
      Button("Reveal in Finder") { if let current { FinderActions.revealInFinder(current.url) } }
        .keyboardShortcut("r", modifiers: .command)
      Button("Open") { if let current { FinderActions.open(current.url) } }
        .keyboardShortcut("o", modifiers: .command)
    }
    .opacity(0)
    .frame(width: 0, height: 0)
    .accessibilityHidden(true)
  }

  private func toggleQuickLook() {
    if quickLookURL == nil {
      quickLookURL = current?.url
    } else {
      quickLookURL = nil
    }
  }

  // Right-click menu shared by the review card and (lighter) the summary rows.
  @ViewBuilder
  private func fileContextMenu(for item: FileItem) -> some View {
    Button("Quick Look") { quickLookURL = item.url }
    Button("Open") { FinderActions.open(item.url) }
    Button("Reveal in Finder") { FinderActions.revealInFinder(item.url) }
    Divider()
    Button("Keep") { if item.id == current?.id { applyDecision(.keep) } }
      .disabled(item.id != current?.id)
    Button("Move to Trash", role: .destructive) { if item.id == current?.id { applyDecision(.delete) } }
      .disabled(item.id != current?.id)
  }

  // Published to the menu bar (Review ▸ … and Edit ▸ Undo) while this review is
  // on screen. ⌘Z routes here; Keep/Delete disable on the summary screen.
  private var reviewActions: ReviewActions {
    let reviewing = !isScanning && !items.isEmpty && !showSummary && !deleteInProgress
    return ReviewActions(
      keep: reviewing ? { applyDecision(.keep) } : nil,
      delete: reviewing ? { applyDecision(.delete) } : nil,
      undo: deleteInProgress ? nil : { undo() },
      skipGroup: nil,
      canUndo: lastUndo != nil && !deleteInProgress
    )
  }

  // MARK: - States

  private var scanningView: some View {
    VStack(spacing: 12) {
      ProgressView().controlSize(.large)
      Text("Scanning your folders…")
        .font(.headline)
        .foregroundStyle(.secondary)
    }
  }

  private var emptyView: some View {
    ContentUnavailableView {
      Label("Nothing to review", systemImage: category.systemImage)
    } description: {
      Text(emptyDescription)
    } actions: {
      Button("Back") { dismiss() }
    }
  }

  private var emptyDescription: String {
    if didTruncate && accessErrorCount > 0 {
      return "Scanned the first \(FileLibrary.maxFilesExamined.formatted()) files and skipped some inaccessible subfolders without finding any \(category.title.lowercased()). Try a more specific folder or adjust folder permissions."
    }
    if didTruncate {
      return "Scanned the first \(FileLibrary.maxFilesExamined.formatted()) files without finding any \(category.title.lowercased()). These folders are very large — try a more specific folder."
    }
    if accessErrorCount > 0 {
      return "No \(category.title.lowercased()) found in the folders SnipSnaps could access. Some subfolders couldn't be scanned because macOS denied access."
    }
    return "No \(category.title.lowercased()) found in the folders you granted."
  }

  private var scanWarningBanner: some View {
    Label(
      scanWarningText,
      systemImage: "exclamationmark.triangle.fill"
    )
    .font(.caption)
    .foregroundStyle(.secondary)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var scanWarningText: String {
    if didTruncate && accessErrorCount > 0 {
      return "Showing matches from the first \(FileLibrary.maxFilesExamined.formatted()) files scanned; some subfolders couldn't be accessed."
    }
    if didTruncate {
      return "Showing matches from the first \(FileLibrary.maxFilesExamined.formatted()) files scanned."
    }
    return "Some subfolders couldn't be scanned because macOS denied access."
  }

  private var reviewView: some View {
    VStack(spacing: 16) {
      header
        .padding(.horizontal, 24)
        .padding(.top, 12)
      if didTruncate || accessErrorCount > 0 {
        scanWarningBanner
          .padding(.horizontal, 24)
      }
      if let current {
        card(for: current)
          .padding(.horizontal, 24)
      }
    }
    // Pin the decision bar in a .bar footer, matching the Photos review and this
    // view's own summary screen so the primary actions sit in a consistent strip.
    .safeAreaInset(edge: .bottom, spacing: 0) {
      decisionBar
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }
    .background(fileKeyboardShortcuts)
  }

  private var header: some View {
    HStack(spacing: 12) {
      Text("\(min(index + 1, items.count)) of \(items.count)")
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .monospacedDigit()
      ProgressView(value: Double(index), total: Double(max(items.count, 1)))
        .tint(AppColor.primary)
      if !toDelete.isEmpty {
        Label("\(toDelete.count)", systemImage: "trash")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(AppColor.delete)
      }
    }
  }

  private func card(for item: FileItem) -> some View {
    VStack(spacing: 0) {
      FileThumbnailView(url: item.url)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 260)
        .background(AppColor.elevatedCard)
        .clipped()

      VStack(alignment: .leading, spacing: 6) {
        Text(item.name)
          .font(.headline)
          .lineLimit(2)
          .truncationMode(.middle)
        HStack(spacing: 10) {
          Label(item.sizeText, systemImage: "internaldrive")
          Label(item.modified.formatted(.relative(presentation: .named)), systemImage: "calendar")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        Text(item.parentPath)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(14)
      .background(AppColor.card)
    }
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .strokeBorder(AppColor.separator.opacity(0.4), lineWidth: 0.5)
    )
    .overlay(swipeBadge)
    .offset(dragOffset)
    .rotationEffect(.degrees(Double(dragOffset.width / 28)))
    .gesture(
      DragGesture(minimumDistance: 6)
        .onChanged { dragOffset = $0.translation }
        .onEnded(handleDragEnd)
    )
    .onTapGesture(count: 2) { FinderActions.open(item.url) }
    .contextMenu { fileContextMenu(for: item) }
    .help("Space to preview · double-click to open")
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(item.name), \(item.sizeText), modified \(item.modified.formatted(.relative(presentation: .named)))")
    .accessibilityActions {
      Button("Keep") { applyDecision(.keep) }
      Button("Move to Trash") { applyDecision(.delete) }
      Button("Quick Look") { quickLookURL = item.url }
      Button("Reveal in Finder") { FinderActions.revealInFinder(item.url) }
    }
    .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: index)
    .id(item.id)
  }

  private var swipeBadge: some View {
    ZStack {
      if dragOffset.width < -24 {
        badge(systemImage: "trash.fill", tint: AppColor.delete, alignment: .topLeading)
      } else if dragOffset.width > 24 {
        badge(systemImage: "checkmark", tint: AppColor.success, alignment: .topTrailing)
      }
    }
    .allowsHitTesting(false)
  }

  private func badge(systemImage: String, tint: Color, alignment: Alignment) -> some View {
    Image(systemName: systemImage)
      .font(.system(size: 26, weight: .bold))
      .foregroundStyle(.white)
      .padding(16)
      .background(tint, in: Circle())
      .padding(20)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
      .opacity(min(abs(dragOffset.width) / 120, 1))
  }

  private var decisionBar: some View {
    HStack(spacing: 18) {
      Button {
        applyDecision(.delete)
      } label: {
        Label("Trash", systemImage: "xmark")
          .frame(maxWidth: .infinity)
      }
      .tint(AppColor.delete)
      .keyboardShortcut(.leftArrow, modifiers: [])

      Button {
        undo()
      } label: {
        Image(systemName: "arrow.uturn.backward")
      }
      // Keep Undo visually secondary (the HStack makes Keep/Trash prominent); this
      // override mirrors the Photos review, where Undo is a secondary action.
      .secondaryActionButton()
      .disabled(lastUndo == nil || deleteInProgress)
      .help("Undo (⌘Z)")

      Button {
        applyDecision(.keep)
      } label: {
        Label("Keep", systemImage: "checkmark")
          .frame(maxWidth: .infinity)
      }
      .tint(AppColor.success)
      .keyboardShortcut(.rightArrow, modifiers: [])
    }
    .controlSize(.large)
    .prominentActionButton()
  }

  private var summaryView: some View {
    ScrollView {
      VStack(spacing: 20) {
        VStack(spacing: 6) {
          Text("Review complete")
            .font(.title2.weight(.semibold))
          Text(summarySubtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 12)

        if let resultMessage {
          Label(resultMessage, systemImage: resultIsWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(resultIsWarning ? .orange : AppColor.success)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }

        if deletedCount > 0 {
          Button {
            FinderActions.revealInTrash(trashedURLs)
          } label: {
            Label("Show in Trash", systemImage: "trash")
              .frame(maxWidth: .infinity)
          }
          .secondaryActionButton()
          .controlSize(.large)
          .help("Open the Trash in Finder to review or restore")
        }

        if !toDelete.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("To move to Trash")
                .font(.subheadline.weight(.semibold))
              Spacer()
              Text(reclaimText)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            ForEach(toDelete) { item in
              HStack(spacing: 10) {
                FileThumbnailView(url: item.url)
                  .frame(width: 40, height: 40)
                  .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(item.name)
                  .font(.callout)
                  .lineLimit(1)
                  .truncationMode(.middle)
                Spacer()
                Text(item.sizeText)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              .contentShape(Rectangle())
              .contextMenu {
                Button("Quick Look") { quickLookURL = item.url }
                Button("Reveal in Finder") { FinderActions.revealInFinder(item.url) }
              }
            }
          }
          .padding(16)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(AppColor.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }

        if totalDeletedCount > 0 {
          VStack(alignment: .leading, spacing: 4) {
            Text("Lifetime")
              .font(.footnote.weight(.semibold))
              .foregroundStyle(.secondary)
            HStack {
              Text("\(totalDeletedCount) deleted")
              Spacer()
              Text(totalDeletedBytesText)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
          }
          .padding(16)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(AppColor.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
      }
      .padding(20)
    }
    .safeAreaInset(edge: .bottom) {
      summaryActionBar
    }
  }

  private var summaryActionBar: some View {
    Group {
      if toDelete.isEmpty {
        Button {
          dismiss()
        } label: {
          Text("Done").fontWeight(.semibold).frame(maxWidth: .infinity)
        }
        .prominentActionButton()
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
      } else {
        Button(role: .destructive) {
          performDelete()
        } label: {
          HStack {
            if deleteInProgress {
              ProgressView().controlSize(.small)
            } else {
              Image(systemName: "trash.fill")
            }
            Text("Move \(toDelete.count) to Trash")
              .fontWeight(.semibold)
          }
          .frame(maxWidth: .infinity)
        }
        .prominentActionButton()
        .tint(AppColor.delete)
        .controlSize(.large)
        .disabled(deleteInProgress)
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(16)
    .background(.bar)
  }

  private var reclaimText: String {
    let bytes = toDelete.reduce(Int64(0)) { $0 + $1.size }
    return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }

  private var summarySubtitle: String {
    if deletedCount > 0, !toDelete.isEmpty {
      return "\(kept.count) kept · \(deletedCount) moved · \(toDelete.count) still to trash"
    }
    if deletedCount > 0 {
      return "\(kept.count) kept · \(deletedCount) moved to Trash"
    }
    return "\(kept.count) kept · \(toDelete.count) to trash"
  }

  private var totalDeletedBytesText: String {
    guard totalDeletedBytes > 0 else { return "0 KB" }
    return ByteCountFormatter.string(fromByteCount: Int64(totalDeletedBytes), countStyle: .file)
  }

  // MARK: - Actions

  private func load() {
    scanTask?.cancel()
    isScanning = true
    let folders = folders
    let category = category
    let limit = max(5, min(reviewLimit, 200))
    sessionMemoryOption = reviewMemoryOption
    let memory = sessionMemoryOption
    let reviewed = FileReviewHistory.reviewedPaths(memoryOption: memory)
    let sort = fileSortOption
    scanTask = Task.detached(priority: .userInitiated) {
      let result = FileLibrary.scan(folders: folders, category: category, limit: limit, excluding: reviewed, sort: sort)
      if Task.isCancelled { return }
      await MainActor.run {
        items = result.items
        didTruncate = result.truncated
        accessErrorCount = result.accessErrorCount
        index = 0
        kept = []
        toDelete = []
        lastUndo = nil
        deletedCount = 0
        resultMessage = nil
        resultIsWarning = false
        trashFailures = []
        showSummary = false
        isScanning = false
      }
    }
  }

  private func applyDecision(_ decision: FileDecision) {
    guard let item = current else { return }
    lastUndo = UndoStep(item: item, decision: decision, index: index)
    switch decision {
    case .keep: kept.append(item)
    case .delete: toDelete.append(item)
    }
    FileReviewHistory.markReviewed(item.url.path, memoryOption: sessionMemoryOption)
    dragOffset = .zero
    advance()
  }

  private func advance() {
    index += 1
    if index >= items.count {
      showSummary = true
    }
  }

  private func undo() {
    guard let step = lastUndo, !deleteInProgress else { return }
    switch step.decision {
    case .keep: kept.removeAll { $0.id == step.item.id }
    case .delete: toDelete.removeAll { $0.id == step.item.id }
    }
    FileReviewHistory.unmarkReviewed(step.item.url.path, memoryOption: sessionMemoryOption)
    showSummary = false
    index = step.index
    lastUndo = nil
  }

  private func handleDragEnd(_ value: DragGesture.Value) {
    let threshold: CGFloat = 110
    if value.translation.width < -threshold {
      applyDecision(.delete)
    } else if value.translation.width > threshold {
      applyDecision(.keep)
    } else {
      withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { dragOffset = .zero }
    }
  }

  private func performDelete() {
    guard !toDelete.isEmpty, !deleteInProgress else { return }
    deleteInProgress = true
    let targets = toDelete
    Task {
      let result = await Task.detached(priority: .userInitiated) {
        FileLibrary.moveToTrash(targets)
      }.value
      await MainActor.run {
        deleteInProgress = false
        let freed = ByteCountFormatter.string(fromByteCount: result.freedBytes, countStyle: .file)
        if result.failed.isEmpty {
          resultMessage = "Moved \(result.trashed) to Trash · \(freed) freed"
          resultIsWarning = false
          toDelete = []
        } else {
          resultMessage = "Moved \(result.trashed) · \(result.failed.count) couldn't be moved"
          resultIsWarning = true
          toDelete = result.failed
          for item in result.failed {
            FileReviewHistory.unmarkReviewed(item.url.path, memoryOption: sessionMemoryOption)
          }
        }
        deletedCount += result.trashed
        totalDeletedCount += result.trashed
        totalDeletedBytes += Int(result.freedBytes)
        trashedURLs.append(contentsOf: result.trashedURLs)
        lastUndo = nil
        trashFailures = result.failed.map(\.name)
      }
    }
  }
}

// Async QuickLook thumbnail for any file type (falls back to the file's icon).
private struct FileThumbnailView: View {
  let url: URL

  @Environment(\.displayScale) private var displayScale
  @State private var image: NSImage?
  @State private var requestedURL: URL?

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        if let image {
          Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          Image(systemName: "doc")
            .font(.system(size: 32))
            .foregroundStyle(.secondary)
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
      .onAppear { load(into: proxy.size) }
      .onChange(of: url) { _, _ in load(into: proxy.size) }
    }
  }

  private func load(into size: CGSize) {
    let requestURL = url
    image = nil
    requestedURL = requestURL
    let target = CGSize(width: max(size.width, 80), height: max(size.height, 80))
    let request = QLThumbnailGenerator.Request(
      fileAt: requestURL,
      size: target,
      scale: displayScale,
      representationTypes: .all
    )
    QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
      guard let nsImage = representation?.nsImage else { return }
      let boxed = UncheckedSendableBox(nsImage)
      Task { @MainActor in
        if requestedURL == requestURL { image = boxed.value }
      }
    }
  }
}

// Hands a known-safe non-Sendable value (the rendered thumbnail) from QuickLook's
// completion queue to the main actor without tripping Swift 6's data-race check.
private struct UncheckedSendableBox<T>: @unchecked Sendable {
  let value: T
  init(_ value: T) { self.value = value }
}
#endif
