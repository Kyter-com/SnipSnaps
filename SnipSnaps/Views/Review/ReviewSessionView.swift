import Foundation
import Photos
import SwiftUI

#if canImport(AVFoundation) && canImport(UIKit)
import AVFoundation
#endif

#if canImport(MapKit)
import MapKit
#endif

#if canImport(PhotosUI)
import PhotosUI
#endif

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

#if os(macOS)
// A concise, fetch-free VoiceOver label for a review card (media type + capture date).
private extension PHAsset {
  var reviewAccessibilityLabel: String {
    var parts: [String] = []
    if mediaType == .video {
      parts.append("Video")
    } else if mediaSubtypes.contains(.photoScreenshot) {
      parts.append("Screenshot")
    } else {
      parts.append("Photo")
    }
    if mediaSubtypes.contains(.photoLive) { parts.append("Live Photo") }
    if let date = creationDate {
      parts.append(date.formatted(date: .abbreviated, time: .omitted))
    }
    return parts.joined(separator: ", ")
  }
}
#endif

enum PhotoDecision {
  case keep
  case delete
}

private struct CachedAssetRequest: Equatable, Hashable {
  let asset: PHAsset
  let targetSize: CGSize
  let contentMode: PHImageContentMode

  static func == (lhs: CachedAssetRequest, rhs: CachedAssetRequest) -> Bool {
    lhs.asset.localIdentifier == rhs.asset.localIdentifier && lhs.targetSize == rhs.targetSize && lhs.contentMode == rhs.contentMode
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(asset.localIdentifier)
    hasher.combine(targetSize.width)
    hasher.combine(targetSize.height)
    hasher.combine(contentMode.rawValue)
  }
}

private struct ReviewPhotoDetails {
  let estimatedBytes: Int
  let captureDateText: String
  let captureAgeText: String
  let captureDateSummaryText: String
  let captureTimestampText: String
  let fileSizeText: String
  let resolutionText: String
  let aspectRatioText: String
  let fileName: String?
  let isLivePhoto: Bool
  let typeText: String
  let durationText: String?

  init(asset: PHAsset) {
    let creationDate = asset.creationDate
    captureDateText = creationDate.map(Self.dateFormatter.string(from:)) ?? "Unknown date"
    captureAgeText = creationDate.map(Self.relativeAgeText(for:)) ?? "Unknown age"
    captureDateSummaryText = "\(captureDateText) · \(captureAgeText)"
    captureTimestampText = creationDate.map(Self.timestampFormatter.string(from:)) ?? "Unknown"

    estimatedBytes = PhotoLibrary.estimatedBytes(for: asset)
    if estimatedBytes > 0 {
      fileSizeText = ByteCountFormatter.string(fromByteCount: Int64(estimatedBytes), countStyle: .file)
    } else {
      fileSizeText = "Unavailable"
    }

    resolutionText = "\(asset.pixelWidth) × \(asset.pixelHeight)"
    aspectRatioText = Self.aspectRatioText(width: asset.pixelWidth, height: asset.pixelHeight)
    fileName = PHAssetResource.assetResources(for: asset).first?.originalFilename
    isLivePhoto = asset.mediaSubtypes.contains(.photoLive)
    typeText = Self.typeText(for: asset)
    durationText = asset.mediaType == .video ? PhotoLibrary.durationText(for: asset) : nil
  }

  private static func aspectRatioText(width: Int, height: Int) -> String {
    guard width > 0, height > 0 else { return "Unknown" }
    let gcdValue = gcd(width, height)
    return "\(width / gcdValue):\(height / gcdValue)"
  }

  private static func typeText(for asset: PHAsset) -> String {
    var labels: [String] = []
    if asset.mediaType == .video {
      labels.append("Video")
    }
    if asset.mediaSubtypes.contains(.photoScreenshot) {
      labels.append("Screenshot")
    }
    if asset.mediaSubtypes.contains(.photoLive) {
      labels.append("Live Photo")
    }
    if labels.isEmpty {
      labels.append("Photo")
    }
    return labels.joined(separator: " • ")
  }

  private static func relativeAgeText(for date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: Date())
  }

  private static func gcd(_ lhs: Int, _ rhs: Int) -> Int {
    var a = abs(lhs)
    var b = abs(rhs)
    while b != 0 {
      let remainder = a % b
      a = b
      b = remainder
    }
    return max(a, 1)
  }

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
  }()

  private static let timestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
  }()

}

private struct PhotoReviewUndo {
  let asset: PHAsset
  let decision: PhotoDecision
  let index: Int
}

// One reversible review action in the Similar flow. A normal swipe/keep-one
// records the asset it added to kept or delete; a "Skip group" records the
// in-group decisions it cleared so Undo can restore them. groupIndex/photoCursor
// capture where to return to.
private struct SimilarUndoStep {
  let groupIndex: Int
  let photoCursor: Int
  let addedKeptIDs: [String]
  let addedDeleteIDs: [String]
  let restoredKept: [PHAsset]
  let restoredDelete: [PHAsset]
}

struct ReviewSessionView: View {
  let mode: ReviewMode

  @Environment(\.dismiss) private var dismiss
  @Environment(\.displayScale) private var displayScale
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var authStatus = PhotoLibrary.authorizationStatus()
  @State private var isLoading = true
  @State private var assets: [PHAsset] = []
  @State private var currentIndex = 0
  @State private var keptAssets: [PHAsset] = []
  @State private var deleteAssets: [PHAsset] = []
  @GestureState private var gestureOffset: CGSize = .zero
  @State private var cardDepartureOffset: CGSize = .zero
  @State private var isAnimatingCard = false
  @State private var showSummary = false
  @State private var showError = false
  @State private var errorMessage = ""
  @State private var deleteInProgress = false
  @State private var deletedCount = 0
  @State private var showMetadataSheet = false
  @State private var cardSize: CGSize = .zero
  @State private var cachedRequests: [CachedAssetRequest] = []
  @State private var currentPhotoDetails: ReviewPhotoDetails?
  @State private var lastReviewUndo: PhotoReviewUndo?
  @AppStorage("reviewLimit") private var reviewLimit: Int = 20
  @AppStorage("screenshotSortOption") private var screenshotSortOptionRawValue: String = ScreenshotSortOption.recent.rawValue
  @AppStorage("videoSortOption") private var videoSortOptionRawValue: String = VideoSortOption.largest.rawValue
  @AppStorage("reviewMemoryOption") private var reviewMemoryOptionRawValue: String = ReviewMemoryOption.thirtyDays.rawValue
  @AppStorage("totalDeletedCount") private var totalDeletedCount: Int = 0
  @AppStorage("totalDeletedBytes") private var totalDeletedBytes: Int = 0

  private var canAccessPhotos: Bool {
    PhotoLibrary.canAccessPhotos(authStatus)
  }

  private var currentAsset: PHAsset? {
    guard assets.indices.contains(currentIndex) else { return nil }
    return assets[currentIndex]
  }

  private var nextAsset: PHAsset? {
    let nextIndex = currentIndex + 1
    guard assets.indices.contains(nextIndex) else { return nil }
    return assets[nextIndex]
  }

  private var upcomingAssets: [PHAsset] {
    guard !assets.isEmpty, currentIndex < assets.count else { return [] }
    let endIndex = min(currentIndex + 3, assets.count)
    return Array(assets[currentIndex..<endIndex])
  }

  private var swipeProgress: CGFloat {
    min(abs(activeCardOffset.width) / 140, 1)
  }

  private var directionalSwipeProgress: CGFloat {
    activeCardOffset.width == 0 ? 0 : swipeProgress * (activeCardOffset.width > 0 ? 1 : -1)
  }

  private var activeCardOffset: CGSize {
    let dragOffset = interactiveOffset(for: gestureOffset)
    return CGSize(
      width: dragOffset.width + cardDepartureOffset.width,
      height: dragOffset.height + cardDepartureOffset.height
    )
  }

  private var swipeRotation: Double {
    Double(activeCardOffset.width / 24)
  }

  private var activeCardScale: CGFloat {
    1 - (swipeProgress * 0.024)
  }

  private var activeCardLift: CGFloat {
    -swipeProgress * 10
  }

  private var progressValue: Double {
    guard !assets.isEmpty else { return 0 }
    return Double(currentIndex + 1) / Double(assets.count)
  }

  private var sessionLimit: Int {
    max(5, min(reviewLimit, 200))
  }

  private var screenshotSortOption: ScreenshotSortOption {
    ScreenshotSortOption(rawValue: screenshotSortOptionRawValue) ?? .recent
  }

  private var videoSortOption: VideoSortOption {
    VideoSortOption(rawValue: videoSortOptionRawValue) ?? .largest
  }

  private var reviewMemoryOption: ReviewMemoryOption {
    ReviewMemoryOption(rawValue: reviewMemoryOptionRawValue) ?? .thirtyDays
  }

  private var estimatedDeleteBytes: Int {
    PhotoLibrary.estimatedBytes(for: deleteAssets)
  }

  private var estimatedDeleteBytesText: String {
    let bytes = estimatedDeleteBytes
    guard bytes > 0 else { return "Unknown" }
    return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
  }

  private var totalDeletedBytesText: String {
    guard totalDeletedBytes > 0 else { return "Unknown" }
    return ByteCountFormatter.string(fromByteCount: Int64(totalDeletedBytes), countStyle: .file)
  }

  private var shouldAutoplayVideo: Bool {
    scenePhase == .active && !showMetadataSheet && !showSummary && !isAnimatingCard
  }

  private var assetSingularName: String {
    mode.reviewsVideos ? "video" : "photo"
  }

  private var assetPluralName: String {
    mode.reviewsVideos ? "videos" : "photos"
  }

  var body: some View {
    ZStack {
      AppColor.background.ignoresSafeArea()
      if !canAccessPhotos {
        accessView
      } else if isLoading {
        loadingView
      } else if assets.isEmpty {
        emptyView
      } else if showSummary {
        summaryView
      } else {
        reviewView
      }
      #if os(macOS)
      // The pushed NavigationStack shows a Back chevron; keep Esc as an invisible
      // accelerator on every state instead of a redundant visible close button.
      Button("Close") { dismiss() }
        .keyboardShortcut(.cancelAction)
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
      #endif
    }
    .navigationTitle(mode.title)
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(true)
    #endif
    .sheet(isPresented: $showMetadataSheet) {
      if let asset = currentAsset,
         let currentPhotoDetails {
        PhotoMetadataSheet(asset: asset, details: currentPhotoDetails)
      }
    }
    // iOS hides the back button, so the explicit close stays there; macOS uses the
    // native Back chevron + the Esc accelerator above.
    #if os(iOS)
    .toolbar {
      if !showSummary || !deleteAssets.isEmpty {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .accessibilityLabel(showSummary ? "Close without deleting" : "Close review")
        }
      }
    }
    .toolbar(.hidden, for: .tabBar)
    #endif
    .onAppear { loadAssets() }
    .onChange(of: currentIndex) { _, _ in
      updateCaching()
      refreshCurrentPhotoDetails()
    }
    .onChange(of: assets.count) { _, _ in
      updateCaching()
      refreshCurrentPhotoDetails()
    }
    .alert("Something went wrong", isPresented: $showError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
    #if os(macOS)
    .focusedSceneValue(\.reviewActions, reviewActions)
    #endif
  }

  #if os(macOS)
  // Published to the menu bar so Review ▸ … and Edit ▸ Undo drive this review
  // while it's on screen. Keep/Delete are nil off the review surface so the menu
  // items disable; ⌘Z routes here via the focused Undo.
  private var reviewActions: ReviewActions {
    let reviewing = canAccessPhotos && !isLoading && !assets.isEmpty && !showSummary && !deleteInProgress
    return ReviewActions(
      keep: reviewing ? { applyDecision(.keep) } : nil,
      delete: reviewing ? { applyDecision(.delete) } : nil,
      undo: deleteInProgress ? nil : { undoLastReviewDecision() },
      skipGroup: nil,
      canUndo: lastReviewUndo != nil && !isAnimatingCard && !deleteInProgress
    )
  }

  // Hidden buttons own the bare review keys (proven pattern). Present only while
  // the review card is showing, so Return is free for the summary's default action.
  private var reviewKeyboardShortcuts: some View {
    ZStack {
      Button("Delete") { applyDecision(.delete) }
        .keyboardShortcut(.leftArrow, modifiers: [])
      Button("Delete") { applyDecision(.delete) }
        .keyboardShortcut(.delete, modifiers: [])
      Button("Keep") { applyDecision(.keep) }
        .keyboardShortcut(.rightArrow, modifiers: [])
      Button("Details") { showMetadataSheet = true }
        .keyboardShortcut(.space, modifiers: [])
    }
    .opacity(0)
    .frame(width: 0, height: 0)
    .accessibilityHidden(true)
  }
  #endif

  private var reviewView: some View {
    VStack(spacing: 18) {
      reviewHeader
        .padding(.horizontal, 20)
        .padding(.top, 8)

      cardStack
        .padding(.horizontal, 20)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      decisionBar
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }
    #if os(macOS)
    .background(reviewKeyboardShortcuts)
    #endif
  }

  private var reviewHeader: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        Text("\(currentIndex + 1) of \(assets.count)")
          .font(.footnote.weight(.medium))
          .foregroundStyle(.secondary)
          .monospacedDigit()
          .contentTransition(.numericText())
        ProgressView(value: progressValue)
          .tint(AppColor.primary)
          .animation(.snappy(duration: 0.28, extraBounce: 0.02), value: progressValue)
      }

      if let currentPhotoDetails {
        Button {
          showMetadataSheet = true
        } label: {
          HStack(spacing: 12) {
            Label(currentPhotoDetails.captureDateSummaryText, systemImage: "calendar")
              .lineLimit(1)
            Spacer(minLength: 0)
            Label(currentPhotoDetails.fileSizeText, systemImage: "internaldrive")
              .lineLimit(1)
            Image(systemName: "info.circle")
              .foregroundStyle(AppColor.primary)
          }
          .font(.footnote.weight(.medium))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 14)
          .padding(.vertical, 12)
          .frame(maxWidth: .infinity)
          .infoChipBackground()
        }
        .id(currentAsset?.localIdentifier)
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
        .buttonStyle(.plain)
      }
    }
    .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.86), value: currentAsset?.localIdentifier)
  }

  private var cardStack: some View {
    GeometryReader { proxy in
      ZStack {
        if upcomingAssets.count > 2 {
          CardBackdropView(bounds: proxy.size)
            .allowsHitTesting(false)
            .scaleEffect(0.914 + (swipeProgress * 0.02))
            .offset(x: directionalSwipeProgress * 8, y: 24 - (swipeProgress * 9))
            .opacity(0.16 + (swipeProgress * 0.12))
        }

        if nextAsset != nil {
          CardBackdropView(bounds: proxy.size)
            .allowsHitTesting(false)
            .scaleEffect(0.962 + (swipeProgress * 0.02))
            .offset(x: directionalSwipeProgress * 6, y: 14 - (swipeProgress * 8))
            .opacity(0.18 + (swipeProgress * 0.12))
            .overlay {
              RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.28 + (1 - Double(swipeProgress)) * 0.2)
            }
        }

        if let asset = currentAsset {
          reviewCard(asset, bounds: proxy.size)
            .zIndex(1)
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
      .onAppear {
        cardSize = proxy.size
        updateCaching()
      }
      .onChange(of: proxy.size) { _, newSize in
        cardSize = newSize
        updateCaching()
      }
    }
  }

  @ViewBuilder
  private func reviewCard(_ asset: PHAsset, bounds: CGSize) -> some View {
    PhotoCardView(
      asset: asset,
      bounds: bounds,
      enableLivePhotoPlayback: true,
      autoplaysVideo: shouldAutoplayVideo
    )
      .scaleEffect(activeCardScale)
      .offset(x: activeCardOffset.width, y: activeCardOffset.height + activeCardLift)
      .rotationEffect(.degrees(swipeRotation))
      .overlay {
        SwipeOverlayView(offset: activeCardOffset.width)
      }
      .onTapGesture {
        showMetadataSheet = true
      }
      #if os(macOS)
      // VoiceOver: label the otherwise-unlabeled photo and expose its tap (Details)
      // as a rotor action. Keep/Delete stay on the labeled decision buttons.
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(asset.reviewAccessibilityLabel)
      .accessibilityAction(named: "Details") { showMetadataSheet = true }
      #endif
      .gesture(
        DragGesture(minimumDistance: 4)
          .updating($gestureOffset) { value, state, _ in
            guard !isAnimatingCard else { return }
            state = value.translation
          }
          .onEnded { value in
            guard !isAnimatingCard else { return }
            handleSwipe(value)
          }
      )
  }

  private var decisionBar: some View {
    HStack(spacing: 18) {
      ReviewActionButton(
        systemImage: "xmark",
        tint: AppColor.delete,
        backgroundTint: AppColor.deleteBackground,
        accessibilityLabel: "Delete \(assetSingularName)"
      ) {
        applyDecision(.delete)
      }
      #if os(macOS)
      .help("Delete (← or Delete)")
      #endif

      Spacer(minLength: 0)

      if lastReviewUndo != nil {
        Button("Undo") {
          undoLastReviewDecision()
        }
        .font(.footnote.weight(.semibold))
        .secondaryActionButton()
        .controlSize(.small)
        #if os(macOS)
        .help("Undo (⌘Z)")
        #endif
      } else {
        Text(macSwipeHint)
          .font(.footnote.weight(.medium))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 0)

      ReviewActionButton(
        systemImage: "checkmark",
        tint: AppColor.success,
        backgroundTint: AppColor.keepBackground,
        accessibilityLabel: "Keep \(assetSingularName)"
      ) {
        applyDecision(.keep)
      }
      #if os(macOS)
      .help("Keep (→)")
      #endif
    }
    .frame(maxWidth: .infinity)
  }

  private var macSwipeHint: String {
    #if os(macOS)
    return "← delete · → keep"
    #else
    return "Swipe or tap"
    #endif
  }

  private var summaryView: some View {
    ScrollView {
      VStack(spacing: 20) {
        VStack(spacing: 6) {
          Text("Review complete")
            .font(.title2.weight(.semibold))
          Text("\(keptAssets.count) kept · \(deleteAssets.count + deletedCount) marked")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 8)

        if deletedCount > 0 {
          summaryBanner(
            title: "Deleted \(deletedCount) \(deletedCount == 1 ? assetSingularName : assetPluralName)",
            subtitle: "Space has been freed up in your library.",
            systemImage: "checkmark.circle.fill",
            tint: AppColor.success
          )
        }

        if !deleteAssets.isEmpty {
          VStack(alignment: .leading, spacing: 10) {
            HStack {
              Text("To delete")
                .font(.subheadline.weight(.semibold))
              Spacer()
              Text(estimatedDeleteBytesText)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            let columns = [GridItem(.adaptive(minimum: 80), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
              ForEach(deleteAssets, id: \.localIdentifier) { asset in
                PhotoThumbnailView(asset: asset)
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

        if lastReviewUndo != nil {
          Button {
            undoLastReviewDecision()
          } label: {
            Text("Undo Last Choice")
              .fontWeight(.semibold)
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .controlSize(.large)
          .disabled(deleteInProgress)
        }
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 32)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      summaryActionBar
    }
  }

  // Pinned to the bottom so the primary action is always reachable without
  // scrolling. When items are marked, the destructive Delete is the only
  // bottom action; once nothing is left to delete it becomes Done.
  private var summaryActionBar: some View {
    Group {
      if !deleteAssets.isEmpty {
        Button(role: .destructive) {
          deleteSelected()
        } label: {
          HStack {
            if deleteInProgress {
              ProgressView().tint(.white)
            } else {
              Image(systemName: "trash.fill")
            }
            Text("Delete \(deleteAssets.count) \(deleteAssets.count == 1 ? assetSingularName.capitalized : assetPluralName.capitalized)")
              .fontWeight(.semibold)
          }
          .frame(maxWidth: .infinity)
        }
        .prominentActionButton()
        .tint(AppColor.delete)
        .controlSize(.large)
        .disabled(deleteInProgress)
        #if os(macOS)
        .keyboardShortcut(.defaultAction)
        #endif
      } else {
        Button {
          dismiss()
        } label: {
          Text("Done")
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
        }
        .prominentActionButton()
        .controlSize(.large)
        #if os(macOS)
        .keyboardShortcut(.defaultAction)
        #endif
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 12)
    .padding(.bottom, 8)
    .background(.bar)
  }

  private func summaryBanner(title: String, subtitle: String, systemImage: String, tint: Color) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: systemImage)
        .font(.title3)
        .foregroundStyle(tint)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.subheadline.weight(.semibold))
        Text(subtitle).font(.footnote).foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(AppColor.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  private var accessView: some View {
    ContentUnavailableView {
      Label("Photo access required", systemImage: "photo.stack")
    } description: {
      Text("Enable access to review and delete \(assetPluralName).")
    } actions: {
      PhotoAccessButtons(status: authStatus, refresh: reloadAfterAccessChange)
    }
  }

  private var loadingView: some View {
    ProgressView()
      .controlSize(.large)
  }

  private var emptyView: some View {
    ContentUnavailableView {
      Label("No \(assetPluralName.capitalized) Found", systemImage: mode.reviewsVideos ? "video" : "photo.on.rectangle.angled")
    } description: {
      Text(emptyViewDescription)
    } actions: {
      // A limited user who reviewed all their selected photos dead-ends here;
      // let them replenish the queue instead of only offering Back.
      if authStatus == .limited {
        PhotoAccessButtons(status: authStatus, refresh: reloadAfterAccessChange)
      }
      Button("Back") { dismiss() }
    }
  }

  private var emptyViewDescription: String {
    if authStatus == .limited {
      return "SnipSnaps can only see the photos you've selected. Add more, or allow full access, to review your whole library."
    }
    if PhotoReviewHistory.supportsSkipping(for: mode), reviewMemoryOption != .never {
      return "Everything in this category may already be reviewed for your current memory setting. Change Remember Reviewed in Settings to revisit items."
    }
    return "Try a different review mode, or check your photo library."
  }

  private func reloadAfterAccessChange() {
    authStatus = PhotoLibrary.authorizationStatus()
    loadAssets()
  }

  private func loadAssets() {
    isLoading = true
    Task {
      let status = await PhotoLibrary.ensureAuthorization()
      await MainActor.run { authStatus = status }
      guard PhotoLibrary.canAccessPhotos(status) else {
        await MainActor.run { isLoading = false }
        return
      }
      let fetched = PhotoLibrary.fetchAssets(
        for: mode,
        limit: sessionLimit,
        screenshotSort: screenshotSortOption,
        videoSort: videoSortOption,
        reviewMemory: reviewMemoryOption
      )
      await MainActor.run {
        assets = fetched
        currentIndex = 0
        keptAssets = []
        deleteAssets = []
        lastReviewUndo = nil
        deletedCount = 0
        currentPhotoDetails = fetched.first.map(ReviewPhotoDetails.init)
        showSummary = fetched.isEmpty
        isLoading = false
      }
    }
  }

  private func handleSwipe(_ value: DragGesture.Value) {
    let threshold = min(max(cardSize.width * 0.24, 104), 136)
    let width = value.translation.width
    let projectedWidth = value.predictedEndTranslation.width
    let resolvedWidth = width + ((projectedWidth - width) * 0.18)

    if resolvedWidth > threshold {
      applyDecision(.keep, startingOffset: interactiveOffset(for: value.translation))
    } else if resolvedWidth < -threshold {
      applyDecision(.delete, startingOffset: interactiveOffset(for: value.translation))
    } else {
      withAnimation(.spring(duration: 0.34, bounce: 0.22)) {
        cardDepartureOffset = .zero
      }
    }
  }

  private func applyDecision(_ decision: PhotoDecision, startingOffset: CGSize = .zero) {
    guard let asset = currentAsset, !isAnimatingCard else { return }
    isAnimatingCard = true
    lastReviewUndo = PhotoReviewUndo(asset: asset, decision: decision, index: currentIndex)
    triggerDecisionHaptic(decision)
    switch decision {
    case .keep:
      keptAssets.append(asset)
    case .delete:
      deleteAssets.append(asset)
    }
    PhotoReviewHistory.markReviewed(asset, for: mode, memoryOption: reviewMemoryOption)
    #if os(macOS)
    if reduceMotion {
      // Skip the card fling; advance with a brief cross-fade and release the lock.
      cardDepartureOffset = .zero
      withAnimation(.easeInOut(duration: 0.15)) { advance() }
      isAnimatingCard = false
      return
    }
    #endif
    let direction: CGFloat = decision == .keep ? 1 : -1
    let exitDistance = max(cardSize.width, 500) * 1.35
    cardDepartureOffset = startingOffset
    withAnimation(.smooth(duration: 0.22)) {
      cardDepartureOffset = CGSize(
        width: direction * exitDistance,
        height: startingOffset.height * 0.25
      )
    }
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(220))
      var resetTransaction = Transaction()
      resetTransaction.disablesAnimations = true
      withTransaction(resetTransaction) {
        cardDepartureOffset = .zero
      }
      withAnimation(.spring(duration: 0.4, bounce: 0.16)) {
        advance()
      }
      isAnimatingCard = false
    }
  }

  private func advance() {
    currentIndex += 1
    if currentIndex >= assets.count {
      showSummary = true
    }
  }

  private func undoLastReviewDecision() {
    guard let undo = lastReviewUndo, !isAnimatingCard, !deleteInProgress else { return }
    switch undo.decision {
    case .keep:
      keptAssets.removeAll { $0.localIdentifier == undo.asset.localIdentifier }
    case .delete:
      deleteAssets.removeAll { $0.localIdentifier == undo.asset.localIdentifier }
    }
    PhotoReviewHistory.unmarkReviewed(undo.asset, for: mode, memoryOption: reviewMemoryOption)
    showSummary = false
    currentIndex = undo.index
    lastReviewUndo = nil
    refreshCurrentPhotoDetails()
    triggerUndoHaptic()
  }

  private func updateCaching() {
    guard cardSize != .zero else { return }
    let nextRequests = upcomingAssets.map { asset in
      let fittedSize = PhotoLibrary.fittedSize(for: asset, in: cardSize)
      return CachedAssetRequest(
        asset: asset,
        targetSize: PhotoLibrary.imageRequestSize(for: asset, displaySize: fittedSize, scale: displayScale),
        contentMode: .aspectFit
      )
    }

    guard nextRequests != cachedRequests else { return }

    let previousRequests = Set(cachedRequests)
    let incomingRequests = Set(nextRequests)

    for request in previousRequests.subtracting(incomingRequests) {
      PhotoLibrary.stopCachingAssets([request.asset], targetSize: request.targetSize, contentMode: request.contentMode)
    }

    for request in incomingRequests.subtracting(previousRequests) {
      PhotoLibrary.startCachingAssets([request.asset], targetSize: request.targetSize, contentMode: request.contentMode)
    }

    for request in nextRequests.dropFirst() {
      PhotoLibrary.preloadImage(for: request.asset, targetSize: request.targetSize, contentMode: request.contentMode)
    }

    cachedRequests = nextRequests
  }

  private func refreshCurrentPhotoDetails() {
    currentPhotoDetails = currentAsset.map(ReviewPhotoDetails.init)
  }

  private func deleteSelected() {
    guard !deleteAssets.isEmpty, !deleteInProgress else { return }
    deleteInProgress = true
    let targetAssets = deleteAssets
    let estimatedBytes = estimatedDeleteBytes
    Task {
      do {
        let success = try await PhotoLibrary.deleteAssets(targetAssets)
        await MainActor.run {
          deleteInProgress = false
          guard success else { return }
          deletedCount += targetAssets.count
          deleteAssets.removeAll { asset in
            targetAssets.contains(where: { $0.localIdentifier == asset.localIdentifier })
          }
          lastReviewUndo = nil
          totalDeletedCount += targetAssets.count
          totalDeletedBytes += estimatedBytes
          triggerDeleteHaptic()
        }
      } catch {
        await MainActor.run {
          errorMessage = error.localizedDescription
          showError = true
          deleteInProgress = false
        }
      }
    }
  }

  private func triggerDecisionHaptic(_ decision: PhotoDecision) {
    #if canImport(UIKit)
    let generator = UIImpactFeedbackGenerator(style: decision == .keep ? .light : .medium)
    generator.prepare()
    generator.impactOccurred()
    #endif
  }

  private func triggerDeleteHaptic() {
    #if canImport(UIKit)
    let generator = UINotificationFeedbackGenerator()
    generator.prepare()
    generator.notificationOccurred(.success)
    #endif
  }

  private func triggerUndoHaptic() {
    #if canImport(UIKit)
    let generator = UIImpactFeedbackGenerator(style: .soft)
    generator.prepare()
    generator.impactOccurred()
    #endif
  }

  private func interactiveOffset(for translation: CGSize) -> CGSize {
    CGSize(
      width: translation.width,
      height: (translation.height * 0.08) - min(abs(translation.width) * 0.03, 14)
    )
  }
}

struct SimilarReviewSessionView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.displayScale) private var displayScale
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var authStatus = PhotoLibrary.authorizationStatus()
  @State private var isScanning = true
  @State private var groups: [SimilarPhotoGroup] = []
  @State private var currentGroupIndex = 0
  @State private var photoCursor = 0
  @State private var keptAssets: [PHAsset] = []
  @State private var deleteAssets: [PHAsset] = []
  @State private var undoStack: [SimilarUndoStep] = []
  @State private var showSummary = false
  @State private var showError = false
  @State private var errorMessage = ""
  @State private var deleteInProgress = false
  @State private var deletedCount = 0
  @State private var scanProgress = SimilarPhotoScanProgress(
    phase: .preparing,
    completedCount: 0,
    totalCount: 0,
    groupsFound: 0
  )
  @State private var scanTask: Task<Void, Never>?
  @State private var detailsByIdentifier: [String: ReviewPhotoDetails] = [:]
  @State private var bytesByIdentifier: [String: Int] = [:]
  @State private var cachedRequests: [CachedAssetRequest] = []
  @State private var zoomTarget: ZoomTarget?
  @State private var metadataTarget: MetadataTarget?
  @GestureState private var gestureOffset: CGSize = .zero
  @State private var cardDepartureOffset: CGSize = .zero
  @State private var isAnimatingCard = false
  @State private var cardSize: CGSize = .zero
  @AppStorage("reviewLimit") private var reviewLimit: Int = 20
  @AppStorage("similarSortOption") private var similarSortOptionRawValue: String = SimilarSortOption.recent.rawValue
  @AppStorage("reviewMemoryOption") private var reviewMemoryOptionRawValue: String = ReviewMemoryOption.thirtyDays.rawValue
  @AppStorage("totalDeletedCount") private var totalDeletedCount: Int = 0
  @AppStorage("totalDeletedBytes") private var totalDeletedBytes: Int = 0

  private struct ZoomTarget: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
  }

  private struct MetadataTarget: Identifiable {
    let asset: PHAsset
    let details: ReviewPhotoDetails
    var id: String { asset.localIdentifier }
  }

  // MARK: - Derived state

  private var canAccessPhotos: Bool {
    PhotoLibrary.canAccessPhotos(authStatus)
  }

  private var currentGroup: SimilarPhotoGroup? {
    guard groups.indices.contains(currentGroupIndex) else { return nil }
    return groups[currentGroupIndex]
  }

  private var groupAssets: [PHAsset] {
    currentGroup?.assets ?? []
  }

  private var currentPhoto: PHAsset? {
    guard groupAssets.indices.contains(photoCursor) else { return nil }
    return groupAssets[photoCursor]
  }

  private var nextPhoto: PHAsset? {
    let next = photoCursor + 1
    guard groupAssets.indices.contains(next) else { return nil }
    return groupAssets[next]
  }

  private var upcomingInGroup: [PHAsset] {
    guard !groupAssets.isEmpty, photoCursor < groupAssets.count else { return [] }
    let end = min(photoCursor + 3, groupAssets.count)
    return Array(groupAssets[photoCursor..<end])
  }

  private var progressValue: Double {
    guard !groups.isEmpty else { return 0 }
    return Double(currentGroupIndex + 1) / Double(groups.count)
  }

  private var similarSortOption: SimilarSortOption {
    SimilarSortOption(rawValue: similarSortOptionRawValue) ?? .recent
  }

  private var reviewMemoryOption: ReviewMemoryOption {
    ReviewMemoryOption(rawValue: reviewMemoryOptionRawValue) ?? .thirtyDays
  }

  // How many photos a scan is willing to examine. Independent of the review
  // size: the scan walks newest-first and stops as soon as it has enough groups
  // to review (see maxGroups), so it only reaches this ceiling on libraries with
  // few or no near-duplicates. The cap keeps the pairwise comparison bounded and
  // matches the review-history identifier ceiling.
  private var scanLimit: Int { 20_000 }

  // How many groups one review session surfaces. This is the review size — it
  // governs the batch you review at a time, not how deep the scan looks.
  private var maxGroups: Int {
    max(5, min(reviewLimit, 60))
  }

  private var estimatedDeleteBytes: Int {
    estimatedBytes(for: deleteAssets)
  }

  private var estimatedDeleteBytesText: String {
    let bytes = estimatedDeleteBytes
    guard bytes > 0 else { return "Unknown" }
    return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
  }

  private var totalDeletedBytesText: String {
    guard totalDeletedBytes > 0 else { return "Unknown" }
    return ByteCountFormatter.string(fromByteCount: Int64(totalDeletedBytes), countStyle: .file)
  }

  private var shouldAutoplayVideo: Bool {
    scenePhase == .active && zoomTarget == nil && metadataTarget == nil && !showSummary && !isAnimatingCard
  }

  // MARK: - Swipe geometry

  private var swipeProgress: CGFloat {
    min(abs(activeCardOffset.width) / 140, 1)
  }

  private var directionalSwipeProgress: CGFloat {
    activeCardOffset.width == 0 ? 0 : swipeProgress * (activeCardOffset.width > 0 ? 1 : -1)
  }

  private var activeCardOffset: CGSize {
    let dragOffset = interactiveOffset(for: gestureOffset)
    return CGSize(
      width: dragOffset.width + cardDepartureOffset.width,
      height: dragOffset.height + cardDepartureOffset.height
    )
  }

  private var swipeRotation: Double {
    Double(activeCardOffset.width / 24)
  }

  private var activeCardScale: CGFloat {
    1 - (swipeProgress * 0.024)
  }

  private var activeCardLift: CGFloat {
    -swipeProgress * 10
  }

  // MARK: - Body

  var body: some View {
    ZStack {
      AppColor.background.ignoresSafeArea()
      if !canAccessPhotos {
        accessView
      } else if isScanning {
        scanningView
      } else if groups.isEmpty {
        emptyView
      } else if showSummary {
        summaryView
      } else {
        reviewView
      }
      #if os(macOS)
      // The pushed NavigationStack shows a Back chevron; keep Esc as an invisible
      // accelerator (cancelling any in-flight scan) instead of a visible close.
      Button("Close") { cancelScan(); dismiss() }
        .keyboardShortcut(.cancelAction)
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
      #endif
    }
    .navigationTitle("Similar")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(true)
    .toolbar {
      if !showSummary || !deleteAssets.isEmpty {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            cancelScan()
            dismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .accessibilityLabel(showSummary ? "Close without deleting" : "Close similar review")
        }
      }
    }
    .toolbar(.hidden, for: .tabBar)
    #endif
    #if os(iOS)
    .fullScreenCover(item: $zoomTarget) { target in
      FullScreenPhotoView(asset: target.asset)
    }
    #else
    .sheet(item: $zoomTarget) { target in
      FullScreenPhotoView(asset: target.asset)
    }
    #endif
    .sheet(item: $metadataTarget) { target in
      PhotoMetadataSheet(asset: target.asset, details: target.details)
    }
    .onAppear { loadGroups() }
    .onDisappear { cancelScan() }
    .onChange(of: photoCursor) { _, _ in updateCaching() }
    .onChange(of: currentGroupIndex) { _, _ in updateCaching() }
    .alert("Something went wrong", isPresented: $showError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
    #if os(macOS)
    .focusedSceneValue(\.reviewActions, reviewActions)
    #endif
  }

  #if os(macOS)
  private var reviewActions: ReviewActions {
    let reviewing = canAccessPhotos && !isScanning && !groups.isEmpty && !showSummary && !deleteInProgress
    return ReviewActions(
      keep: reviewing ? { applyPhotoDecision(.keep) } : nil,
      delete: reviewing ? { applyPhotoDecision(.delete) } : nil,
      undo: deleteInProgress ? nil : { undo() },
      skipGroup: reviewing ? { skipGroup() } : nil,
      canUndo: !undoStack.isEmpty && !isAnimatingCard && !deleteInProgress
    )
  }

  private var similarKeyboardShortcuts: some View {
    ZStack {
      Button("Delete") { applyPhotoDecision(.delete) }
        .keyboardShortcut(.leftArrow, modifiers: [])
      Button("Delete") { applyPhotoDecision(.delete) }
        .keyboardShortcut(.delete, modifiers: [])
      Button("Keep") { applyPhotoDecision(.keep) }
        .keyboardShortcut(.rightArrow, modifiers: [])
      Button("Skip Group") { skipGroup() }
        .keyboardShortcut("s", modifiers: [])
      if let asset = currentPhoto {
        Button("Details") { metadataTarget = MetadataTarget(asset: asset, details: details(for: asset)) }
          .keyboardShortcut(.space, modifiers: [])
      }
    }
    .opacity(0)
    .frame(width: 0, height: 0)
    .accessibilityHidden(true)
  }
  #endif

  // MARK: - Review

  private var reviewView: some View {
    #if os(macOS)
    swipeReviewView
      .background(similarKeyboardShortcuts)
    #else
    swipeReviewView
    #endif
  }

  private var groupHeader: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        Text("Group \(currentGroupIndex + 1) of \(groups.count)")
          .font(.footnote.weight(.medium))
          .foregroundStyle(.secondary)
          .monospacedDigit()
        ProgressView(value: progressValue)
          .tint(AppColor.primary)
          .animation(.snappy(duration: 0.28, extraBounce: 0.02), value: progressValue)
      }

      if let asset = currentPhoto {
        let detail = details(for: asset)
        Button {
          metadataTarget = MetadataTarget(asset: asset, details: detail)
        } label: {
          HStack(spacing: 12) {
            Label(detail.captureDateSummaryText, systemImage: "calendar")
              .lineLimit(1)
            Spacer(minLength: 0)
            Label(detail.fileSizeText, systemImage: "internaldrive")
              .lineLimit(1)
            Image(systemName: "info.circle")
              .foregroundStyle(AppColor.primary)
          }
          .font(.footnote.weight(.medium))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 14)
          .padding(.vertical, 12)
          .frame(maxWidth: .infinity)
          .infoChipBackground()
        }
        .id(asset.localIdentifier)
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
        .buttonStyle(.plain)
      }
    }
    .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.86), value: currentPhoto?.localIdentifier)
  }

  // MARK: - Swipe flow (3+ photos)

  private var swipeReviewView: some View {
    VStack(spacing: 14) {
      groupHeader
        .padding(.horizontal, 20)
        .padding(.top, 8)

      withinGroupStrip
        .padding(.horizontal, 20)

      cardStack
        .padding(.horizontal, 20)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      swipeDecisionBar
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }
  }

  // Shows every photo in the current group so siblings stay visible while you
  // decide. The active photo is outlined; decided ones show a keep check or a
  // dimmed delete mark. Tap any thumbnail to open it full screen.
  private var withinGroupStrip: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(groupAssets, id: \.localIdentifier) { asset in
            let assetDecision = decision(for: asset)
            let isActive = asset.localIdentifier == currentPhoto?.localIdentifier
            Button {
              zoomTarget = ZoomTarget(asset: asset)
              selectionHaptic()
            } label: {
            PhotoAssetImageView(asset: asset, targetSize: CGSize(width: 84, height: 84), contentMode: .fill)
              .frame(width: 64, height: 64)
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
              .overlay {
                if assetDecision == .delete {
                  ZStack {
                    Color.black.opacity(0.45)
                    Image(systemName: "xmark")
                      .font(.subheadline.weight(.bold))
                      .foregroundStyle(.white)
                  }
                  .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
              }
              .overlay(alignment: .topTrailing) {
                if assetDecision == .keep {
                  Image(systemName: "checkmark.circle.fill")
                    .font(.footnote)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, AppColor.success)
                    .padding(3)
                }
              }
              .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                  .strokeBorder(isActive ? AppColor.primary : AppColor.separator, lineWidth: isActive ? 2.5 : 0.5)
              }
          }
          .buttonStyle(.plain)
          .interactiveCardHover()
          .id(asset.localIdentifier)
        }
      }
      .padding(.horizontal, 2)
      .padding(.vertical, 2)
      }
      .frame(height: 72)
      .onChange(of: photoCursor) { _, _ in
        scrollToActivePhoto(proxy)
      }
      .onChange(of: currentGroupIndex) { _, _ in
        scrollToActivePhoto(proxy)
      }
    }
  }

  private func scrollToActivePhoto(_ proxy: ScrollViewProxy) {
    guard let id = currentPhoto?.localIdentifier else { return }
    withAnimation(.snappy(duration: 0.25)) {
      proxy.scrollTo(id, anchor: .center)
    }
  }

  private var cardStack: some View {
    GeometryReader { proxy in
      ZStack {
        if upcomingInGroup.count > 2 {
          CardBackdropView(bounds: proxy.size)
            .allowsHitTesting(false)
            .scaleEffect(0.914 + (swipeProgress * 0.02))
            .offset(x: directionalSwipeProgress * 8, y: 24 - (swipeProgress * 9))
            .opacity(0.16 + (swipeProgress * 0.12))
        }

        if nextPhoto != nil {
          CardBackdropView(bounds: proxy.size)
            .allowsHitTesting(false)
            .scaleEffect(0.962 + (swipeProgress * 0.02))
            .offset(x: directionalSwipeProgress * 6, y: 14 - (swipeProgress * 8))
            .opacity(0.18 + (swipeProgress * 0.12))
            .overlay {
              RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.28 + (1 - Double(swipeProgress)) * 0.2)
            }
        }

        if let asset = currentPhoto {
          reviewCard(asset, bounds: proxy.size)
            .zIndex(1)
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
      .onAppear {
        cardSize = proxy.size
        updateCaching()
      }
      .onChange(of: proxy.size) { _, newSize in
        cardSize = newSize
        updateCaching()
      }
    }
  }

  @ViewBuilder
  private func reviewCard(_ asset: PHAsset, bounds: CGSize) -> some View {
    PhotoCardView(
      asset: asset,
      bounds: bounds,
      enableLivePhotoPlayback: true,
      autoplaysVideo: shouldAutoplayVideo
    )
    .scaleEffect(activeCardScale)
    .offset(x: activeCardOffset.width, y: activeCardOffset.height + activeCardLift)
    .rotationEffect(.degrees(swipeRotation))
    .overlay {
      SwipeOverlayView(offset: activeCardOffset.width)
    }
    .onTapGesture {
      metadataTarget = MetadataTarget(asset: asset, details: details(for: asset))
    }
    #if os(macOS)
    // VoiceOver: label the photo and expose its tap (Details) as a rotor action.
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(asset.reviewAccessibilityLabel)
    .accessibilityAction(named: "Details") { metadataTarget = MetadataTarget(asset: asset, details: details(for: asset)) }
    #endif
    .gesture(
      DragGesture(minimumDistance: 4)
        .updating($gestureOffset) { value, state, _ in
          guard !isAnimatingCard else { return }
          state = value.translation
        }
        .onEnded { value in
          guard !isAnimatingCard else { return }
          handleSwipe(value)
        }
    )
  }

  private var swipeDecisionBar: some View {
    HStack(spacing: 18) {
      ReviewActionButton(
        systemImage: "xmark",
        tint: AppColor.delete,
        backgroundTint: AppColor.deleteBackground,
        accessibilityLabel: "Delete photo"
      ) {
        applyPhotoDecision(.delete)
      }

      Spacer(minLength: 0)

      HStack(spacing: 10) {
        Button("Skip group") {
          skipGroup()
        }
        .font(.footnote.weight(.semibold))
        .buttonStyle(.bordered)
        .controlSize(.small)

        if !undoStack.isEmpty {
          Button("Undo") {
            undo()
          }
          .font(.footnote.weight(.semibold))
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
      }

      Spacer(minLength: 0)

      ReviewActionButton(
        systemImage: "checkmark",
        tint: AppColor.success,
        backgroundTint: AppColor.keepBackground,
        accessibilityLabel: "Keep photo"
      ) {
        applyPhotoDecision(.keep)
      }
    }
    .frame(maxWidth: .infinity)
  }

  // MARK: - Non-review states

  private var accessView: some View {
    ContentUnavailableView {
      Label("Photo access required", systemImage: "photo.stack")
    } description: {
      Text("Enable access to find and review similar photos.")
    } actions: {
      PhotoAccessButtons(status: authStatus, refresh: reloadAfterAccessChange)
    }
  }

  private func reloadAfterAccessChange() {
    authStatus = PhotoLibrary.authorizationStatus()
    loadGroups()
  }

  private var scanningView: some View {
    VStack(spacing: 14) {
      if let fractionCompleted = scanProgress.fractionCompleted {
        ProgressView(value: fractionCompleted)
          .tint(AppColor.primary)
          .frame(maxWidth: 220)
      } else {
        ProgressView()
          .controlSize(.large)
      }

      Text(scanProgress.phase.title)
        .font(.headline)

      Text(scanStatusText)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)

      if !groups.isEmpty {
        Button {
          reviewCurrentPartialGroups()
        } label: {
          Label(reviewFoundTitle, systemImage: "square.stack.3d.up")
            .fontWeight(.semibold)
        }
        .prominentActionButton()
        .tint(AppColor.primary)
        .controlSize(.large)
        .padding(.top, 4)
      }
    }
  }

  private var scanStatusText: String {
    guard scanProgress.totalCount > 0 else {
      return "Preparing scan. \(similarSortOption.subtitle)."
    }

    let countText = "\(scanProgress.completedCount) of \(scanProgress.totalCount)"
    if groups.isEmpty {
      return "Comparing \(countText) photos. \(similarSortOption.subtitle)."
    }

    return "Comparing \(countText) photos. \(groups.count) groups found."
  }

  private var reviewFoundTitle: String {
    groups.count == 1 ? "Review 1 Group" : "Review \(groups.count) Groups"
  }

  private var emptyView: some View {
    ContentUnavailableView {
      Label("No Similar Photos Found", systemImage: "square.stack.3d.up")
    } description: {
      Text(emptyViewDescription)
    } actions: {
      if authStatus == .limited {
        PhotoAccessButtons(status: authStatus, refresh: reloadAfterAccessChange)
      }
      Button("Back") { dismiss() }
    }
  }

  private var emptyViewDescription: String {
    if authStatus == .limited {
      return "SnipSnaps can only compare the photos you've selected. Add more, or allow full access, to find similar shots."
    }
    if reviewMemoryOption != .never {
      return "No near-duplicates left to review. Groups you've already reviewed are skipped — change Remember Reviewed in Settings to revisit them. Screenshots are reviewed separately."
    }
    return "No near-duplicate photos found. Screenshots are reviewed separately."
  }

  // MARK: - Summary

  private var summaryView: some View {
    ScrollView {
      VStack(spacing: 20) {
        VStack(spacing: 6) {
          Text("Review complete")
            .font(.title2.weight(.semibold))
          Text("\(keptAssets.count) kept · \(deleteAssets.count + deletedCount) marked")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 8)

        if deletedCount > 0 {
          summaryBanner(
            title: "Deleted \(deletedCount) \(deletedCount == 1 ? "photo" : "photos")",
            subtitle: "Space has been freed up in your library.",
            systemImage: "checkmark.circle.fill",
            tint: AppColor.success
          )
        }

        if !deleteAssets.isEmpty {
          VStack(alignment: .leading, spacing: 10) {
            HStack {
              Text("To delete")
                .font(.subheadline.weight(.semibold))
              Spacer()
              Text(estimatedDeleteBytesText)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            let columns = [GridItem(.adaptive(minimum: 80), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
              ForEach(deleteAssets, id: \.localIdentifier) { asset in
                PhotoThumbnailView(asset: asset)
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

        if !undoStack.isEmpty {
          Button {
            undo()
          } label: {
            Text("Undo Last Choice")
              .fontWeight(.semibold)
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .controlSize(.large)
          .disabled(deleteInProgress)
        }
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 32)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      summaryActionBar
    }
  }

  private var summaryActionBar: some View {
    Group {
      if !deleteAssets.isEmpty {
        Button(role: .destructive) {
          deleteSelected()
        } label: {
          HStack {
            if deleteInProgress {
              ProgressView().tint(.white)
            } else {
              Image(systemName: "trash.fill")
            }
            Text("Delete \(deleteAssets.count) \(deleteAssets.count == 1 ? "Photo" : "Photos")")
              .fontWeight(.semibold)
          }
          .frame(maxWidth: .infinity)
        }
        .prominentActionButton()
        .tint(AppColor.delete)
        .controlSize(.large)
        .disabled(deleteInProgress)
        #if os(macOS)
        .keyboardShortcut(.defaultAction)
        #endif
      } else {
        Button {
          dismiss()
        } label: {
          Text("Done")
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
        }
        .prominentActionButton()
        .controlSize(.large)
        #if os(macOS)
        .keyboardShortcut(.defaultAction)
        #endif
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 12)
    .padding(.bottom, 8)
    .background(.bar)
  }

  private func summaryBanner(title: String, subtitle: String, systemImage: String, tint: Color) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: systemImage)
        .font(.title3)
        .foregroundStyle(tint)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.subheadline.weight(.semibold))
        Text(subtitle).font(.footnote).foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(AppColor.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  // MARK: - Scanning

  private func loadGroups() {
    guard groups.isEmpty else { return }
    scanTask?.cancel()
    isScanning = true
    scanProgress = SimilarPhotoScanProgress(
      phase: .preparing,
      completedCount: 0,
      totalCount: 0,
      groupsFound: 0
    )
    scanTask = Task {
      let status = await PhotoLibrary.ensureAuthorization()
      await MainActor.run { authStatus = status }
      guard PhotoLibrary.canAccessPhotos(status) else {
        await MainActor.run {
          isScanning = false
          scanTask = nil
        }
        return
      }

      let scanLimit = scanLimit
      let maxGroups = maxGroups
      let similarSortOption = similarSortOption
      let reviewMemoryOption = reviewMemoryOption
      let worker = Task.detached(priority: .userInitiated) {
        // Decode the (up to 20k) reviewed-identifier store off the main thread.
        let reviewedIdentifiers = PhotoReviewHistory.similarReviewedIdentifiers(memoryOption: reviewMemoryOption)
        return await PhotoLibrary.fetchSimilarPhotoGroups(
          scanLimit: scanLimit,
          maxGroups: maxGroups,
          sort: similarSortOption,
          reviewedIdentifiers: reviewedIdentifiers,
          progressHandler: { progress in
            await MainActor.run {
              guard isScanning else { return }
              scanProgress = progress
            }
          },
          partialGroupsHandler: { partialGroups in
            await MainActor.run {
              guard isScanning else { return }
              applyScannedGroups(partialGroups, resetSession: false)
            }
          }
        )
      }
      let fetchedGroups = await withTaskCancellationHandler(operation: {
        await worker.value
      }, onCancel: {
        worker.cancel()
      })
      guard !Task.isCancelled else { return }
      await MainActor.run {
        applyScannedGroups(fetchedGroups, resetSession: true)
        deletedCount = 0
        isScanning = false
        scanTask = nil
      }
    }
  }

  private func applyScannedGroups(_ scannedGroups: [SimilarPhotoGroup], resetSession: Bool) {
    groups = scannedGroups
    updateSimilarMetadataCache(for: scannedGroups)

    if resetSession {
      currentGroupIndex = 0
      photoCursor = 0
      keptAssets = []
      deleteAssets = []
      undoStack = []
    } else if currentGroupIndex >= scannedGroups.count {
      currentGroupIndex = max(scannedGroups.count - 1, 0)
      photoCursor = 0
    }
  }

  private func updateSimilarMetadataCache(for groups: [SimilarPhotoGroup]) {
    var nextDetails = detailsByIdentifier
    var nextBytes = bytesByIdentifier

    for asset in groups.flatMap(\.assets) where nextDetails[asset.localIdentifier] == nil {
      let details = ReviewPhotoDetails(asset: asset)
      nextDetails[asset.localIdentifier] = details
      nextBytes[asset.localIdentifier] = details.estimatedBytes
    }

    detailsByIdentifier = nextDetails
    bytesByIdentifier = nextBytes
  }

  private func reviewCurrentPartialGroups() {
    guard !groups.isEmpty else { return }
    scanTask?.cancel()
    scanTask = nil
    isScanning = false
  }

  private func cancelScan() {
    scanTask?.cancel()
    scanTask = nil
  }

  // MARK: - Metadata helpers

  private func details(for asset: PHAsset) -> ReviewPhotoDetails {
    detailsByIdentifier[asset.localIdentifier] ?? ReviewPhotoDetails(asset: asset)
  }

  private func estimatedBytes(for asset: PHAsset) -> Int {
    bytesByIdentifier[asset.localIdentifier] ?? PhotoLibrary.estimatedBytes(for: asset)
  }

  private func estimatedBytes(for assets: [PHAsset]) -> Int {
    assets.reduce(0) { $0 + estimatedBytes(for: $1) }
  }

  private func decision(for asset: PHAsset) -> PhotoDecision? {
    if keptAssets.contains(where: { $0.localIdentifier == asset.localIdentifier }) {
      return .keep
    }
    if deleteAssets.contains(where: { $0.localIdentifier == asset.localIdentifier }) {
      return .delete
    }
    return nil
  }

  // MARK: - Decisions

  private func handleSwipe(_ value: DragGesture.Value) {
    let threshold = min(max(cardSize.width * 0.24, 104), 136)
    let width = value.translation.width
    let projectedWidth = value.predictedEndTranslation.width
    let resolvedWidth = width + ((projectedWidth - width) * 0.18)

    if resolvedWidth > threshold {
      applyPhotoDecision(.keep, startingOffset: interactiveOffset(for: value.translation))
    } else if resolvedWidth < -threshold {
      applyPhotoDecision(.delete, startingOffset: interactiveOffset(for: value.translation))
    } else {
      withAnimation(.spring(duration: 0.34, bounce: 0.22)) {
        cardDepartureOffset = .zero
      }
    }
  }

  private func applyPhotoDecision(_ decision: PhotoDecision, startingOffset: CGSize = .zero) {
    guard let asset = currentPhoto, !isAnimatingCard else { return }
    isAnimatingCard = true
    pushUndo(
      addedKept: decision == .keep ? [asset] : [],
      addedDelete: decision == .delete ? [asset] : [],
      restoredKept: [],
      restoredDelete: []
    )
    decisionHaptic(decision)
    switch decision {
    case .keep:
      appendUnique([asset], to: &keptAssets)
    case .delete:
      appendUnique([asset], to: &deleteAssets)
    }
    // Remember this photo so the next scan skips it and reaches deeper into the
    // library. Deleted photos leave the library anyway; recording kept ones is
    // what stops a kept group from re-forming and reappearing.
    PhotoReviewHistory.markSimilarReviewed(asset.localIdentifier, memoryOption: reviewMemoryOption)
    #if os(macOS)
    if reduceMotion {
      cardDepartureOffset = .zero
      withAnimation(.easeInOut(duration: 0.15)) { advancePhoto() }
      isAnimatingCard = false
      return
    }
    #endif
    let direction: CGFloat = decision == .keep ? 1 : -1
    let exitDistance = max(cardSize.width, 500) * 1.35
    cardDepartureOffset = startingOffset
    withAnimation(.smooth(duration: 0.22)) {
      cardDepartureOffset = CGSize(
        width: direction * exitDistance,
        height: startingOffset.height * 0.25
      )
    }
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(220))
      var resetTransaction = Transaction()
      resetTransaction.disablesAnimations = true
      withTransaction(resetTransaction) {
        cardDepartureOffset = .zero
      }
      withAnimation(.spring(duration: 0.4, bounce: 0.16)) {
        advancePhoto()
      }
      isAnimatingCard = false
    }
  }

  // Defers the entire current group: clears any decisions already made for its
  // photos so nothing is kept or deleted, then moves on. Skipping does not
  // record review memory, so the group reappears on the next scan — any photos
  // that were already decided get un-remembered here so they come back too.
  private func skipGroup() {
    guard let group = currentGroup, !isAnimatingCard else { return }
    let identifiers = Set(group.assets.map(\.localIdentifier))
    let restoredKept = keptAssets.filter { identifiers.contains($0.localIdentifier) }
    let restoredDelete = deleteAssets.filter { identifiers.contains($0.localIdentifier) }
    pushUndo(addedKept: [], addedDelete: [], restoredKept: restoredKept, restoredDelete: restoredDelete)
    keptAssets.removeAll { identifiers.contains($0.localIdentifier) }
    deleteAssets.removeAll { identifiers.contains($0.localIdentifier) }
    for asset in restoredKept + restoredDelete {
      PhotoReviewHistory.unmarkSimilarReviewed(asset.localIdentifier, memoryOption: reviewMemoryOption)
    }
    selectionHaptic()
    advanceGroupAnimated()
  }

  private func advancePhoto() {
    photoCursor += 1
    if photoCursor >= groupAssets.count {
      advanceGroup()
    }
  }

  private func advanceGroup() {
    currentGroupIndex += 1
    photoCursor = 0
    if currentGroupIndex >= groups.count {
      showSummary = true
    }
  }

  // Advances to the next group with a brief animation lock so a rapid double-tap
  // on Skip group cannot advance two groups at once.
  private func advanceGroupAnimated() {
    isAnimatingCard = true
    withAnimation(.spring(duration: 0.34, bounce: 0.14)) {
      advanceGroup()
    }
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(340))
      isAnimatingCard = false
    }
  }

  private func pushUndo(addedKept: [PHAsset], addedDelete: [PHAsset], restoredKept: [PHAsset], restoredDelete: [PHAsset]) {
    undoStack.append(
      SimilarUndoStep(
        groupIndex: currentGroupIndex,
        photoCursor: photoCursor,
        addedKeptIDs: addedKept.map(\.localIdentifier),
        addedDeleteIDs: addedDelete.map(\.localIdentifier),
        restoredKept: restoredKept,
        restoredDelete: restoredDelete
      )
    )
  }

  private func undo() {
    guard !isAnimatingCard, !deleteInProgress, let step = undoStack.popLast() else { return }
    keptAssets.removeAll { step.addedKeptIDs.contains($0.localIdentifier) }
    deleteAssets.removeAll { step.addedDeleteIDs.contains($0.localIdentifier) }
    appendUnique(step.restoredKept, to: &keptAssets)
    appendUnique(step.restoredDelete, to: &deleteAssets)
    // Keep review memory in step with the decisions being reverted: drop the
    // ones this step added, and restore the ones a skip had cleared.
    for identifier in step.addedKeptIDs + step.addedDeleteIDs {
      PhotoReviewHistory.unmarkSimilarReviewed(identifier, memoryOption: reviewMemoryOption)
    }
    for asset in step.restoredKept + step.restoredDelete {
      PhotoReviewHistory.markSimilarReviewed(asset.localIdentifier, memoryOption: reviewMemoryOption)
    }
    showSummary = false
    withAnimation(.spring(duration: 0.34, bounce: 0.14)) {
      currentGroupIndex = step.groupIndex
      photoCursor = step.photoCursor
    }
    undoHaptic()
  }

  private func appendUnique(_ assets: [PHAsset], to target: inout [PHAsset]) {
    for asset in assets where !target.contains(where: { $0.localIdentifier == asset.localIdentifier }) {
      target.append(asset)
    }
  }

  private func deleteSelected() {
    guard !deleteAssets.isEmpty, !deleteInProgress else { return }
    deleteInProgress = true
    let targetAssets = deleteAssets
    let estimatedBytesValue = estimatedDeleteBytes
    Task {
      do {
        let success = try await PhotoLibrary.deleteAssets(targetAssets)
        await MainActor.run {
          deleteInProgress = false
          guard success else { return }
          deletedCount += targetAssets.count
          deleteAssets.removeAll { asset in
            targetAssets.contains(where: { $0.localIdentifier == asset.localIdentifier })
          }
          undoStack.removeAll()
          totalDeletedCount += targetAssets.count
          totalDeletedBytes += estimatedBytesValue
          deleteHaptic()
        }
      } catch {
        await MainActor.run {
          errorMessage = error.localizedDescription
          showError = true
          deleteInProgress = false
        }
      }
    }
  }

  // MARK: - Image caching

  private func updateCaching() {
    guard cardSize != .zero else { return }
    let nextRequests = upcomingInGroup.map { asset -> CachedAssetRequest in
      let fittedSize = PhotoLibrary.fittedSize(for: asset, in: cardSize)
      return CachedAssetRequest(
        asset: asset,
        targetSize: PhotoLibrary.imageRequestSize(for: asset, displaySize: fittedSize, scale: displayScale),
        contentMode: .aspectFit
      )
    }

    guard nextRequests != cachedRequests else { return }

    let previousRequests = Set(cachedRequests)
    let incomingRequests = Set(nextRequests)

    for request in previousRequests.subtracting(incomingRequests) {
      PhotoLibrary.stopCachingAssets([request.asset], targetSize: request.targetSize, contentMode: request.contentMode)
    }

    for request in incomingRequests.subtracting(previousRequests) {
      PhotoLibrary.startCachingAssets([request.asset], targetSize: request.targetSize, contentMode: request.contentMode)
    }

    for request in nextRequests.dropFirst() {
      PhotoLibrary.preloadImage(for: request.asset, targetSize: request.targetSize, contentMode: request.contentMode)
    }

    cachedRequests = nextRequests
  }

  private func interactiveOffset(for translation: CGSize) -> CGSize {
    CGSize(
      width: translation.width,
      height: (translation.height * 0.08) - min(abs(translation.width) * 0.03, 14)
    )
  }

  // MARK: - Haptics

  private func decisionHaptic(_ decision: PhotoDecision) {
    #if canImport(UIKit)
    let generator = UIImpactFeedbackGenerator(style: decision == .keep ? .light : .medium)
    generator.prepare()
    generator.impactOccurred()
    #endif
  }

  private func selectionHaptic() {
    #if canImport(UIKit)
    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.prepare()
    generator.impactOccurred()
    #endif
  }

  private func deleteHaptic() {
    #if canImport(UIKit)
    let generator = UINotificationFeedbackGenerator()
    generator.prepare()
    generator.notificationOccurred(.success)
    #endif
  }

  private func undoHaptic() {
    #if canImport(UIKit)
    let generator = UIImpactFeedbackGenerator(style: .soft)
    generator.prepare()
    generator.impactOccurred()
    #endif
  }
}

// Full-screen, pinch-to-zoom photo viewer used to compare similar shots closely.
// Pinch to zoom, drag to pan when zoomed, double-tap to toggle zoom.
private struct FullScreenPhotoView: View {
  let asset: PHAsset

  @Environment(\.dismiss) private var dismiss
  @State private var scale: CGFloat = 1
  @State private var lastScale: CGFloat = 1
  @State private var offset: CGSize = .zero
  @State private var lastOffset: CGSize = .zero

  private let maxScale: CGFloat = 4

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        Color.black.ignoresSafeArea()
        PhotoAssetImageView(asset: asset, targetSize: proxy.size, contentMode: .fit)
          .scaleEffect(scale)
          .offset(offset)
          .gesture(magnification(in: proxy.size).simultaneously(with: dragGesture(in: proxy.size)))
          .onTapGesture(count: 2) { toggleZoom() }
      }
      .contentShape(Rectangle())
    }
    .ignoresSafeArea()
    .overlay(alignment: .topTrailing) {
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark")
          .font(.body.weight(.semibold))
          .foregroundStyle(.white)
          .padding(12)
          .background(Color.black.opacity(0.45), in: Circle())
      }
      .padding(.top, 12)
      .padding(.trailing, 16)
      .accessibilityLabel("Close")
      #if os(macOS)
      .keyboardShortcut(.cancelAction)
      #endif
    }
    #if os(macOS)
    // Presented as a .sheet on macOS; the GeometryReader root has no intrinsic
    // size, so without an explicit frame the sheet collapses to a tiny window and
    // the "compare similar shots closely" viewer is unusable. Give it a generous,
    // resizable size that suits a large display.
    .frame(minWidth: 720, idealWidth: 1040, minHeight: 520, idealHeight: 760)
    #endif
    #if os(iOS)
    .statusBarHidden(true)
    #endif
  }

  private func magnification(in size: CGSize) -> some Gesture {
    MagnificationGesture()
      .onChanged { value in
        scale = min(max(lastScale * value, 1), maxScale)
        // Re-clamp as the scale shrinks so a pinch-down from a panned corner
        // tracks the fingers instead of snapping back on release.
        offset = clampedOffset(offset, in: size)
      }
      .onEnded { _ in
        lastScale = scale
        if scale <= 1 {
          withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            resetZoom()
          }
        } else {
          offset = clampedOffset(offset, in: size)
          lastOffset = offset
        }
      }
  }

  private func dragGesture(in size: CGSize) -> some Gesture {
    DragGesture()
      .onChanged { value in
        guard scale > 1 else { return }
        offset = CGSize(
          width: lastOffset.width + value.translation.width,
          height: lastOffset.height + value.translation.height
        )
      }
      .onEnded { _ in
        guard scale > 1 else { return }
        offset = clampedOffset(offset, in: size)
        lastOffset = offset
      }
  }

  private func toggleZoom() {
    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
      if scale > 1 {
        resetZoom()
      } else {
        scale = 2.5
        lastScale = 2.5
      }
    }
  }

  private func resetZoom() {
    scale = 1
    lastScale = 1
    offset = .zero
    lastOffset = .zero
  }

  private func clampedOffset(_ proposed: CGSize, in size: CGSize) -> CGSize {
    let maxX = max((size.width * (scale - 1)) / 2, 0)
    let maxY = max((size.height * (scale - 1)) / 2, 0)
    return CGSize(
      width: min(max(proposed.width, -maxX), maxX),
      height: min(max(proposed.height, -maxY), maxY)
    )
  }
}

private struct PhotoMetadataSheet: View {
  let asset: PHAsset
  let details: ReviewPhotoDetails

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section(asset.mediaType == .video ? "Video" : "Photo") {
          LabeledContent("Date") {
            Text(details.captureTimestampText)
              .multilineTextAlignment(.trailing)
          }
          LabeledContent("Age", value: details.captureAgeText)
          LabeledContent("File size", value: details.fileSizeText)
          if let durationText = details.durationText {
            LabeledContent("Duration", value: durationText)
          }
          LabeledContent("Resolution", value: details.resolutionText)
          LabeledContent("Aspect ratio", value: details.aspectRatioText)
          LabeledContent("Type", value: details.typeText)
          if let fileName = details.fileName {
            LabeledContent("Filename") {
              Text(fileName)
                .multilineTextAlignment(.trailing)
            }
          }
        }

        Section("Library") {
          LabeledContent("Favorite", value: asset.isFavorite ? "Yes" : "No")
          LabeledContent("Hidden", value: asset.isHidden ? "Yes" : "No")
        }

        #if canImport(MapKit)
        if let coordinate = asset.location?.coordinate {
          Section("Location") {
            AssetLocationMapView(coordinate: coordinate)
          }
        }
        #endif
      }
      .navigationTitle(asset.mediaType == .video ? "Video Details" : "Photo Details")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    #if os(iOS)
    .presentationDetents([.medium, .large])
    // On iPad this sheet is otherwise a small fixed-size form-sheet card that
    // clips its content (the location map ends up below the fold). A page-size
    // sheet is tall enough to show the whole list. No effect on iPhone (compact
    // width), where the detents above govern instead.
    .presentationSizing(.page)
    #else
    // The macOS sheet auto-sizes to the Form, which can open cramped (the location
    // map falls below the fold). Pin a comfortable, resizable size.
    .frame(minWidth: 420, idealWidth: 460, minHeight: 520, idealHeight: 620)
    #endif
  }
}

#if canImport(MapKit)
private struct AssetLocationMapView: View {
  let coordinate: CLLocationCoordinate2D

  private var position: MapCameraPosition {
    .region(
      MKCoordinateRegion(
        center: coordinate,
        span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
      )
    )
  }

  var body: some View {
    Map(position: .constant(position)) {
      Marker("Captured here", coordinate: coordinate)
    }
    .mapControlVisibility(.hidden)
    .frame(height: 172)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(AppColor.separator.opacity(0.35), lineWidth: 0.5)
    }
    .accessibilityLabel("Capture location map")
  }
}
#endif

private struct PhotoCardView: View {
  let asset: PHAsset
  let bounds: CGSize
  var enableLivePhotoPlayback = false
  var autoplaysVideo = true

  @State private var livePhotoPlaybackTrigger = 0

  var body: some View {
    let fittedSize = PhotoLibrary.fittedSize(for: asset, in: bounds)
    ZStack(alignment: .topLeading) {
      if asset.mediaType == .video {
        PhotoAssetImageView(asset: asset, targetSize: fittedSize)

        #if canImport(AVFoundation) && canImport(UIKit)
        VideoAssetPlayerView(asset: asset, isActive: autoplaysVideo)
          .frame(width: fittedSize.width, height: fittedSize.height)
        #endif
      } else {
        PhotoAssetImageView(
          asset: asset,
          targetSize: fittedSize,
          enableLivePhotoPlayback: enableLivePhotoPlayback,
          livePhotoPlaybackTrigger: livePhotoPlaybackTrigger
        )
      }

      if enableLivePhotoPlayback, asset.mediaSubtypes.contains(.photoLive) {
        Label("Live", systemImage: "livephoto")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          // Fixed dark scrim (not a material) so the white label stays legible
          // over bright photos in both Light and Dark.
          .background(.black.opacity(0.55), in: Capsule(style: .continuous))
          .padding(18)
      }

      if asset.mediaType == .video {
        Label(PhotoLibrary.durationText(for: asset), systemImage: "play.fill")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(.black.opacity(0.55), in: Capsule(style: .continuous))
          .padding(18)
      }
    }
    .frame(width: fittedSize.width, height: fittedSize.height)
    .background(AppColor.elevatedCard, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 28, style: .continuous)
        .strokeBorder(AppColor.cardEdge, lineWidth: 0.5)
    )
    .shadow(color: AppColor.shadow.opacity(1.35), radius: 22, x: 0, y: 12)
    .frame(width: bounds.width, height: bounds.height)
    .simultaneousGesture(
      LongPressGesture(minimumDuration: 0.18)
        .onEnded { _ in
          guard enableLivePhotoPlayback, asset.mediaSubtypes.contains(.photoLive) else { return }
          livePhotoPlaybackTrigger += 1
        }
    )
  }
}

#if canImport(AVFoundation) && canImport(UIKit)
private struct VideoAssetPlayerView: UIViewRepresentable {
  let asset: PHAsset
  let isActive: Bool

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeUIView(context: Context) -> VideoPlayerContainerView {
    let view = VideoPlayerContainerView()
    view.playerLayer.videoGravity = .resizeAspect
    view.backgroundColor = .clear
    context.coordinator.updatePlayerItem(for: asset, isActive: isActive, in: view)
    return view
  }

  func updateUIView(_ view: VideoPlayerContainerView, context: Context) {
    view.playerLayer.videoGravity = .resizeAspect
    context.coordinator.updatePlayerItem(for: asset, isActive: isActive, in: view)
  }

  static func dismantleUIView(_ uiView: VideoPlayerContainerView, coordinator: Coordinator) {
    coordinator.cancelRequest()
    uiView.playerLayer.player = nil
  }

  final class Coordinator {
    private var requestId: PHImageRequestID?
    private var assetIdentifier: String?
    private var endObserver: NSObjectProtocol?
    private weak var player: AVPlayer?

    @MainActor
    func updatePlayerItem(for asset: PHAsset, isActive: Bool, in view: VideoPlayerContainerView) {
      guard asset.mediaType == .video, isActive else {
        cancelRequest()
        view.playerLayer.player = nil
        return
      }

      if assetIdentifier == asset.localIdentifier {
        view.playerLayer.player?.play()
        return
      }

      cancelRequest()
      assetIdentifier = asset.localIdentifier
      view.accessibilityIdentifier = asset.localIdentifier
      view.playerLayer.player = nil

      let options = PHVideoRequestOptions()
      options.isNetworkAccessAllowed = true
      options.deliveryMode = .automatic
      let expectedAssetIdentifier = asset.localIdentifier

      requestId = PhotoLibrary.imageManager.requestPlayerItem(forVideo: asset, options: options) { [weak self, weak view] item, _ in
        guard let item else { return }
        DispatchQueue.main.async {
          guard let self,
                let view,
                self.assetIdentifier == expectedAssetIdentifier,
                view.accessibilityIdentifier == expectedAssetIdentifier else {
            return
          }

          let player = AVPlayer(playerItem: item)
          player.isMuted = true
          player.actionAtItemEnd = .none
          view.playerLayer.player = player
          self.player = player
          self.endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
          ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
          }
          player.play()
        }
      }
    }

    func cancelRequest() {
      if let requestId {
        PhotoLibrary.imageManager.cancelImageRequest(requestId)
      }
      if let endObserver {
        NotificationCenter.default.removeObserver(endObserver)
      }
      player?.pause()
      requestId = nil
      assetIdentifier = nil
      endObserver = nil
      player = nil
    }
  }
}

private final class VideoPlayerContainerView: UIView {
  override static var layerClass: AnyClass {
    AVPlayerLayer.self
  }

  var playerLayer: AVPlayerLayer {
    layer as! AVPlayerLayer
  }
}
#endif

private struct CardBackdropView: View {
  let bounds: CGSize

  var body: some View {
    RoundedRectangle(cornerRadius: 28, style: .continuous)
      .fill(AppColor.elevatedCard)
      .overlay(
        RoundedRectangle(cornerRadius: 28, style: .continuous)
          .strokeBorder(AppColor.cardEdge, lineWidth: 0.5)
      )
      .shadow(color: AppColor.shadow.opacity(1.2), radius: 18, x: 0, y: 10)
      .frame(width: bounds.width, height: bounds.height)
  }
}

private struct PhotoThumbnailView: View {
  let asset: PHAsset

  var body: some View {
    PhotoAssetImageView(asset: asset, targetSize: CGSize(width: 120, height: 120), contentMode: .fill)
      .aspectRatio(1, contentMode: .fill)
      .frame(minWidth: 0, maxWidth: .infinity)
      .overlay(alignment: .bottomTrailing) {
        if asset.mediaType == .video {
          Text(PhotoLibrary.durationText(for: asset))
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.55), in: Capsule(style: .continuous))
            .padding(6)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

private struct PhotoAssetImageView: View {
  let asset: PHAsset
  let targetSize: CGSize
  var contentMode: ContentMode = .fit
  var enableLivePhotoPlayback = false
  var livePhotoPlaybackTrigger = 0

  @Environment(\.displayScale) private var displayScale
  @State private var image: PlatformImage?
  @State private var requestId: PHImageRequestID?
  @State private var previewRequestId: PHImageRequestID?
  @State private var isLoaded = false
  @State private var activeRequestKey: String?

  private var requestSize: CGSize {
    PhotoLibrary.imageRequestSize(for: asset, displaySize: targetSize, scale: displayScale)
  }

  private var imageContentMode: PHImageContentMode {
    contentMode == .fill ? .aspectFill : .aspectFit
  }

  private var showsLivePhotoPlayback: Bool {
    enableLivePhotoPlayback && asset.mediaSubtypes.contains(.photoLive)
  }

  var body: some View {
    ZStack {
      if let image {
        platformImageView(image)
          .resizable()
          .aspectRatio(contentMode: contentMode)
          .opacity(isLoaded ? 1 : 0)
      } else {
        Rectangle()
          .fill(AppColor.fill)
      }

      #if canImport(PhotosUI) && canImport(UIKit)
      if showsLivePhotoPlayback {
        LivePhotoAssetView(
          asset: asset,
          targetSize: requestSize,
          contentMode: imageContentMode,
          playbackTrigger: livePhotoPlaybackTrigger
        )
      }
      #endif
    }
    .clipped()
    .onAppear { requestImage() }
    .onChange(of: asset.localIdentifier) { _, _ in requestImage() }
    .onChange(of: targetSize) { _, _ in requestImage() }
    .onDisappear { cancelRequest() }
  }

  @ViewBuilder
  private func platformImageView(_ image: PlatformImage) -> Image {
    #if canImport(UIKit)
    Image(uiImage: image)
    #elseif canImport(AppKit)
    Image(nsImage: image)
    #else
    Image(systemName: "photo")
    #endif
  }

  private func requestImage() {
    let cacheKey = PhotoLibrary.imageCacheKey(for: asset, targetSize: requestSize, contentMode: imageContentMode)
    let requestKey = String(cacheKey)
    let prefersHighQualityImage = contentMode == .fit

    if let cachedImage = PhotoLibrary.cachedImage(forKey: cacheKey) {
      cancelRequest()
      activeRequestKey = requestKey
      image = cachedImage
      isLoaded = true
      return
    }

    cancelRequest()
    activeRequestKey = requestKey
    image = nil
    isLoaded = false
    let options = PHImageRequestOptions()
    options.isNetworkAccessAllowed = true
    options.deliveryMode = prefersHighQualityImage ? .highQualityFormat : .opportunistic
    options.resizeMode = .exact

    if prefersHighQualityImage {
      let previewOptions = PHImageRequestOptions()
      previewOptions.isNetworkAccessAllowed = true
      previewOptions.deliveryMode = .opportunistic
      previewOptions.resizeMode = .exact

      previewRequestId = PhotoLibrary.imageManager.requestImage(
        for: asset,
        targetSize: requestSize,
        contentMode: imageContentMode,
        options: previewOptions
      ) { result, info in
        guard let result else { return }
        let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
        guard !isCancelled else { return }

        Task { @MainActor in
          guard activeRequestKey == requestKey, image == nil else { return }
          image = result
          isLoaded = true
        }
      }
    }

    requestId = PhotoLibrary.imageManager.requestImage(
      for: asset,
      targetSize: requestSize,
      contentMode: imageContentMode,
      options: options
    ) { result, info in
      guard let result else { return }
      let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
      guard !isCancelled else { return }
      let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
      Task { @MainActor in
        guard activeRequestKey == requestKey else { return }
        if prefersHighQualityImage && isDegraded {
          return
        }
        image = result
        if !isDegraded {
          PhotoLibrary.storeCachedImage(result, forKey: cacheKey)
        }
        if isDegraded {
          isLoaded = true
        } else {
          withAnimation(.easeOut(duration: 0.15)) { isLoaded = true }
        }
      }
    }
  }

  private func cancelRequest() {
    if let requestId {
      PhotoLibrary.imageManager.cancelImageRequest(requestId)
    }
    if let previewRequestId {
      PhotoLibrary.imageManager.cancelImageRequest(previewRequestId)
    }
    requestId = nil
    previewRequestId = nil
    activeRequestKey = nil
  }
}

#if canImport(PhotosUI) && canImport(UIKit)
private struct LivePhotoAssetView: UIViewRepresentable {
  let asset: PHAsset
  let targetSize: CGSize
  let contentMode: PHImageContentMode
  let playbackTrigger: Int

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeUIView(context: Context) -> PHLivePhotoView {
    let view = PHLivePhotoView()
    view.contentMode = contentMode == .aspectFill ? .scaleAspectFill : .scaleAspectFit
    view.clipsToBounds = true
    view.isMuted = true
    context.coordinator.requestLivePhoto(for: asset, targetSize: targetSize, contentMode: contentMode, in: view)
    return view
  }

  func updateUIView(_ view: PHLivePhotoView, context: Context) {
    view.contentMode = contentMode == .aspectFill ? .scaleAspectFill : .scaleAspectFit
    context.coordinator.requestLivePhoto(for: asset, targetSize: targetSize, contentMode: contentMode, in: view)

    if context.coordinator.playbackTrigger != playbackTrigger {
      context.coordinator.playbackTrigger = playbackTrigger
      view.startPlayback(with: .full)
    }
  }

  static func dismantleUIView(_ uiView: PHLivePhotoView, coordinator: Coordinator) {
    coordinator.cancelRequest()
    uiView.stopPlayback()
    uiView.livePhoto = nil
  }

  final class Coordinator {
    private var requestId: PHImageRequestID?
    private var assetIdentifier: String?
    private var requestedSize: CGSize = .zero
    private var requestedContentMode: PHImageContentMode = .aspectFit
    var playbackTrigger = 0

    @MainActor
    func requestLivePhoto(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode, in view: PHLivePhotoView) {
      guard assetIdentifier != asset.localIdentifier || requestedSize != targetSize || requestedContentMode != contentMode else { return }

      cancelRequest()
      assetIdentifier = asset.localIdentifier
      requestedSize = targetSize
      requestedContentMode = contentMode
      view.livePhoto = nil
      view.accessibilityIdentifier = asset.localIdentifier

      let options = PHLivePhotoRequestOptions()
      options.isNetworkAccessAllowed = true
      options.deliveryMode = .highQualityFormat
      let expectedAssetIdentifier = asset.localIdentifier

      requestId = PhotoLibrary.imageManager.requestLivePhoto(
        for: asset,
        targetSize: targetSize,
        contentMode: contentMode,
        options: options
      ) { livePhoto, _ in
        guard let livePhoto else { return }
        DispatchQueue.main.async {
          guard view.accessibilityIdentifier == expectedAssetIdentifier else { return }
          view.livePhoto = livePhoto
        }
      }
    }

    func cancelRequest() {
      if let requestId {
        PhotoLibrary.imageManager.cancelImageRequest(requestId)
      }
      requestId = nil
      assetIdentifier = nil
      requestedSize = .zero
    }
  }
}
#endif

private struct SwipeOverlayView: View {
  let offset: CGFloat

  private var revealProgress: CGFloat {
    min(max((abs(offset) - 12) / 104, 0), 1)
  }

  var body: some View {
    ZStack {
      if offset > 16 {
        badge(systemImage: "checkmark", tint: AppColor.success, backgroundTint: AppColor.keepBackground, alignment: .topTrailing)
          .opacity(revealProgress)
      } else if offset < -16 {
        badge(systemImage: "xmark", tint: AppColor.delete, backgroundTint: AppColor.deleteBackground, alignment: .topLeading)
          .opacity(revealProgress)
      }
    }
    .allowsHitTesting(false)
  }

  private func badge(systemImage: String, tint: Color, backgroundTint: Color, alignment: Alignment) -> some View {
    Image(systemName: systemImage)
      .font(.system(size: 28, weight: .bold))
      .symbolRenderingMode(.hierarchical)
      .foregroundStyle(tint)
      .frame(width: 64, height: 64)
      .background(backgroundTint, in: Circle())
      .overlay(
        Circle().strokeBorder(tint.opacity(0.12), lineWidth: 0.5)
      )
      .scaleEffect(0.84 + (revealProgress * 0.16))
      .rotationEffect(.degrees(Double((offset > 0 ? 1 : -1) * (1 - revealProgress) * 8)))
      .shadow(color: AppColor.shadow.opacity(1.4), radius: 14, x: 0, y: 8)
      .padding(24)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
  }
}

private struct ReviewActionButton: View {
  let systemImage: String
  let tint: Color
  let backgroundTint: Color
  let accessibilityLabel: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.title3.weight(.bold))
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(tint)
        .frame(width: 56, height: 56)
        .background(backgroundTint, in: Circle())
        .overlay(
          Circle().strokeBorder(tint.opacity(0.12), lineWidth: 0.5)
        )
    }
    .buttonStyle(.plain)
    .contentShape(Circle())
    .interactiveCardHover()
    .shadow(color: AppColor.shadow.opacity(1.1), radius: 10, x: 0, y: 6)
    .accessibilityLabel(accessibilityLabel)
  }
}
