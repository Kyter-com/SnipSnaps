#if os(macOS)
import SwiftUI
import AppKit
import QuickLookThumbnailing

struct FileReviewSessionView: View {
  let category: FileReviewCategory
  let folders: [URL]

  @Environment(\.dismiss) private var dismiss
  @State private var isScanning = true
  @State private var items: [FileItem] = []
  @State private var index = 0
  @State private var kept: [FileItem] = []
  @State private var toDelete: [FileItem] = []
  @State private var lastUndo: UndoStep?
  @State private var showSummary = false
  @State private var deleteInProgress = false
  @State private var resultMessage: String?
  @State private var deletedCount = 0
  @State private var dragOffset: CGSize = .zero
  // Shared with the Photos review so "Review Size" and the lifetime "Space
  // freed" stats behave the same across both surfaces.
  @AppStorage("reviewLimit") private var reviewLimit: Int = 20
  @AppStorage("totalDeletedCount") private var totalDeletedCount: Int = 0
  @AppStorage("totalDeletedBytes") private var totalDeletedBytes: Int = 0
  @AppStorage("reviewMemoryOption") private var reviewMemoryOptionRawValue: String = ReviewMemoryOption.thirtyDays.rawValue

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
    }
    .navigationTitle(category.title)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
        }
        .help("Close review")
      }
    }
    .onAppear(perform: load)
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
      Text("No \(category.title.lowercased()) found in the folders you granted.")
    } actions: {
      Button("Back") { dismiss() }
    }
  }

  private var reviewView: some View {
    VStack(spacing: 16) {
      header
        .padding(.horizontal, 24)
        .padding(.top, 12)
      if let current {
        card(for: current)
          .padding(.horizontal, 24)
      }
      decisionBar
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
    }
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
          .foregroundStyle(.tertiary)
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
    .animation(.snappy(duration: 0.28), value: index)
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
      .disabled(lastUndo == nil)
      .keyboardShortcut("z", modifiers: .command)

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
    .buttonStyle(.borderedProminent)
  }

  private var summaryView: some View {
    ScrollView {
      VStack(spacing: 20) {
        VStack(spacing: 6) {
          Text("Review complete")
            .font(.title2.weight(.semibold))
          Text("\(kept.count) kept · \(toDelete.count + deletedCount) to trash")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 12)

        if let resultMessage {
          Label(resultMessage, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(AppColor.success)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
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
        .buttonStyle(.borderedProminent)
        .tint(AppColor.delete)
        .controlSize(.large)
        .disabled(deleteInProgress)
      }
    }
    .padding(16)
    .background(.bar)
  }

  private var reclaimText: String {
    let bytes = toDelete.reduce(Int64(0)) { $0 + $1.size }
    return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }

  private var totalDeletedBytesText: String {
    guard totalDeletedBytes > 0 else { return "0 KB" }
    return ByteCountFormatter.string(fromByteCount: Int64(totalDeletedBytes), countStyle: .file)
  }

  // MARK: - Actions

  private func load() {
    isScanning = true
    let folders = folders
    let category = category
    let limit = max(5, min(reviewLimit, 200))
    let reviewed = FileReviewHistory.reviewedPaths(memoryOption: reviewMemoryOption)
    Task {
      let scanned = await Task.detached(priority: .userInitiated) {
        FileLibrary.scan(folders: folders, category: category, limit: limit, excluding: reviewed)
      }.value
      await MainActor.run {
        items = scanned
        index = 0
        kept = []
        toDelete = []
        lastUndo = nil
        deletedCount = 0
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
    FileReviewHistory.markReviewed(item.url.path, memoryOption: reviewMemoryOption)
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
    guard let step = lastUndo else { return }
    switch step.decision {
    case .keep: kept.removeAll { $0.id == step.item.id }
    case .delete: toDelete.removeAll { $0.id == step.item.id }
    }
    FileReviewHistory.unmarkReviewed(step.item.url.path, memoryOption: reviewMemoryOption)
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
      withAnimation(.snappy(duration: 0.25)) { dragOffset = .zero }
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
        } else {
          resultMessage = "Moved \(result.trashed) · \(result.failed.count) couldn't be moved"
        }
        deletedCount += result.trashed
        totalDeletedCount += result.trashed
        totalDeletedBytes += Int(result.freedBytes)
        toDelete = []
        lastUndo = nil
      }
    }
  }
}

// Async QuickLook thumbnail for any file type (falls back to the file's icon).
private struct FileThumbnailView: View {
  let url: URL

  @Environment(\.displayScale) private var displayScale
  @State private var image: NSImage?

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
    let target = CGSize(width: max(size.width, 80), height: max(size.height, 80))
    let request = QLThumbnailGenerator.Request(
      fileAt: url,
      size: target,
      scale: displayScale,
      representationTypes: .all
    )
    QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
      guard let nsImage = representation?.nsImage else { return }
      let boxed = UncheckedSendableBox(nsImage)
      Task { @MainActor in image = boxed.value }
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
