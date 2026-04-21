import Foundation
import Photos
import SwiftUI

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

enum PhotoDecision {
  case keep
  case delete
}

private struct CachedAssetRequest: Equatable {
  let asset: PHAsset
  let targetSize: CGSize
  let contentMode: PHImageContentMode

  static func == (lhs: CachedAssetRequest, rhs: CachedAssetRequest) -> Bool {
    lhs.asset.localIdentifier == rhs.asset.localIdentifier && lhs.targetSize == rhs.targetSize && lhs.contentMode == rhs.contentMode
  }
}

private struct ReviewPhotoDetails {
  let captureDateText: String
  let captureTimestampText: String
  let fileSizeText: String
  let resolutionText: String
  let aspectRatioText: String
  let fileName: String?
  let isLivePhoto: Bool
  let typeText: String

  init(asset: PHAsset) {
    let creationDate = asset.creationDate
    captureDateText = creationDate.map(Self.dateFormatter.string(from:)) ?? "Unknown date"
    captureTimestampText = creationDate.map(Self.timestampFormatter.string(from:)) ?? "Unknown"

    let bytes = PhotoLibrary.estimatedBytes(for: asset)
    if bytes > 0 {
      fileSizeText = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    } else {
      fileSizeText = "Unavailable"
    }

    resolutionText = "\(asset.pixelWidth) × \(asset.pixelHeight)"
    aspectRatioText = Self.aspectRatioText(width: asset.pixelWidth, height: asset.pixelHeight)
    fileName = PHAssetResource.assetResources(for: asset).first?.originalFilename
    isLivePhoto = asset.mediaSubtypes.contains(.photoLive)
    typeText = Self.typeText(for: asset)
  }

  private static func aspectRatioText(width: Int, height: Int) -> String {
    guard width > 0, height > 0 else { return "Unknown" }
    let gcdValue = gcd(width, height)
    return "\(width / gcdValue):\(height / gcdValue)"
  }

  private static func typeText(for asset: PHAsset) -> String {
    var labels: [String] = []
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

struct ReviewSessionView: View {
  let mode: ReviewMode

  @Environment(\.dismiss) private var dismiss
  @Environment(\.displayScale) private var displayScale
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
  @AppStorage("reviewLimit") private var reviewLimit: Int = 20
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

  private var progressValue: Double {
    guard !assets.isEmpty else { return 0 }
    return Double(currentIndex + 1) / Double(assets.count)
  }

  private var sessionLimit: Int {
    max(5, min(reviewLimit, 200))
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

  private var infoPanelOverlayOpacity: Double {
    0.34 + (1 - Double(swipeProgress)) * 0.48
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
    }
    .navigationTitle(mode.title)
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $showMetadataSheet) {
      if let asset = currentAsset,
         let currentPhotoDetails {
        PhotoMetadataSheet(asset: asset, details: currentPhotoDetails)
      }
    }
    .toolbar {
      if showSummary {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
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
  }

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
            if currentPhotoDetails.isLivePhoto {
              Label("Live", systemImage: "livephoto")
                .lineLimit(1)
                .foregroundStyle(AppColor.primary)
            }
            Label(currentPhotoDetails.captureDateText, systemImage: "calendar")
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
          .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .fill(.ultraThinMaterial)
              .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                  .fill(AppColor.card.opacity(infoPanelOverlayOpacity))
              }
          }
        }
        .id(currentAsset?.localIdentifier)
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
        .buttonStyle(.plain)
      }
    }
    .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.86), value: currentAsset?.localIdentifier)
    .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.9), value: swipeProgress)
  }

  private var cardStack: some View {
    GeometryReader { proxy in
      ZStack {
        if upcomingAssets.count > 2 {
          CardBackdropView(bounds: proxy.size)
            .allowsHitTesting(false)
            .scaleEffect(0.92 + (swipeProgress * 0.015))
            .offset(y: 20 - (swipeProgress * 6))
            .opacity(0.2 + (swipeProgress * 0.08))
        }

        if nextAsset != nil {
          CardBackdropView(bounds: proxy.size)
            .allowsHitTesting(false)
            .scaleEffect(0.965 + (swipeProgress * 0.018))
            .offset(y: 12 - (swipeProgress * 6))
            .opacity(0.18 + (swipeProgress * 0.12))
            .overlay {
              RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.34 + (1 - Double(swipeProgress)) * 0.24)
            }
        }

        if let asset = currentAsset {
          reviewCard(asset, bounds: proxy.size)
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
    PhotoCardView(asset: asset, bounds: bounds, enableLivePhotoPlayback: true)
      .offset(activeCardOffset)
      .rotationEffect(.degrees(swipeRotation))
      .overlay {
        SwipeOverlayView(offset: activeCardOffset.width)
      }
      .onTapGesture {
        showMetadataSheet = true
      }
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
        accessibilityLabel: "Delete photo"
      ) {
        applyDecision(.delete)
      }

      Spacer(minLength: 0)

      Text("Swipe or tap")
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)

      Spacer(minLength: 0)

      ReviewActionButton(
        systemImage: "checkmark",
        tint: AppColor.success,
        backgroundTint: AppColor.keepBackground,
        accessibilityLabel: "Keep photo"
      ) {
        applyDecision(.keep)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity)
    .background(.ultraThinMaterial, in: Capsule(style: .continuous))
    .overlay(
      Capsule(style: .continuous)
        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
    )
    .shadow(color: AppColor.shadow.opacity(1.4), radius: 14, x: 0, y: 6)
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
            title: "Deleted \(deletedCount) photos",
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
              Text("Delete \(deleteAssets.count) Photos")
                .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .tint(AppColor.delete)
          .controlSize(.large)
          .disabled(deleteInProgress)
        }

        Button {
          dismiss()
        } label: {
          Text("Done")
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(deleteInProgress)
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 32)
    }
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
      Text("Enable access to review and delete photos.")
    } actions: {
      Button("Enable Photo Access") {
        Task {
          authStatus = await PhotoLibrary.requestAuthorization()
          loadAssets()
        }
      }
      .buttonStyle(.borderedProminent)
    }
  }

  private var loadingView: some View {
    ProgressView()
      .controlSize(.large)
  }

  private var emptyView: some View {
    ContentUnavailableView {
      Label("No Photos Found", systemImage: "photo.on.rectangle.angled")
    } description: {
      Text("Try a different review mode, or check your photo library.")
    } actions: {
      Button("Back") { dismiss() }
    }
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
      let fetched = PhotoLibrary.fetchAssets(for: mode, limit: sessionLimit)
      await MainActor.run {
        assets = fetched
        currentIndex = 0
        keptAssets = []
        deleteAssets = []
        deletedCount = 0
        currentPhotoDetails = fetched.first.map(ReviewPhotoDetails.init)
        showSummary = fetched.isEmpty
        isLoading = false
      }
    }
  }

  private func handleSwipe(_ value: DragGesture.Value) {
    let threshold: CGFloat = 120
    let width = value.translation.width
    let projectedWidth = value.predictedEndTranslation.width

    if max(width, projectedWidth) > threshold {
      applyDecision(.keep, startingOffset: interactiveOffset(for: value.translation))
    } else if min(width, projectedWidth) < -threshold {
      applyDecision(.delete, startingOffset: interactiveOffset(for: value.translation))
    } else {
      withAnimation(.snappy(duration: 0.22, extraBounce: 0.03)) {
        cardDepartureOffset = .zero
      }
    }
  }

  private func applyDecision(_ decision: PhotoDecision, startingOffset: CGSize = .zero) {
    guard let asset = currentAsset, !isAnimatingCard else { return }
    isAnimatingCard = true
    triggerDecisionHaptic(decision)
    switch decision {
    case .keep:
      keptAssets.append(asset)
    case .delete:
      deleteAssets.append(asset)
    }
    let direction: CGFloat = decision == .keep ? 1 : -1
    let exitDistance = max(cardSize.width, 500) * 1.35
    cardDepartureOffset = startingOffset
    withAnimation(.snappy(duration: 0.22, extraBounce: 0.02)) {
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
      withAnimation(.snappy(duration: 0.3, extraBounce: 0.03)) {
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

    for request in cachedRequests {
      PhotoLibrary.stopCachingAssets([request.asset], targetSize: request.targetSize, contentMode: request.contentMode)
    }

    for request in nextRequests {
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

  private func interactiveOffset(for translation: CGSize) -> CGSize {
    CGSize(width: translation.width, height: translation.height * 0.08)
  }
}

private struct PhotoMetadataSheet: View {
  let asset: PHAsset
  let details: ReviewPhotoDetails

  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL

  var body: some View {
    NavigationStack {
      Form {
        Section("Photo") {
          LabeledContent("Date") {
            Text(details.captureTimestampText)
              .multilineTextAlignment(.trailing)
          }
          LabeledContent("File size", value: details.fileSizeText)
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

        Section {
          Button {
            openPhotosApp()
          } label: {
            Label("Open in Photos", systemImage: "photo.on.rectangle")
          }
        } footer: {
          Text("This opens Apple Photos. iOS does not provide a public API to deep-link directly to the exact photo.")
        }
      }
      .navigationTitle("Photo Details")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  private func openPhotosApp() {
    guard let url = URL(string: "photos-redirect://") else { return }
    openURL(url)
  }
}

private struct PhotoCardView: View {
  let asset: PHAsset
  let bounds: CGSize
  var enableLivePhotoPlayback = false

  @State private var livePhotoPlaybackTrigger = 0

  var body: some View {
    let fittedSize = PhotoLibrary.fittedSize(for: asset, in: bounds)
    ZStack(alignment: .topLeading) {
      PhotoAssetImageView(
        asset: asset,
        targetSize: fittedSize,
        enableLivePhotoPlayback: enableLivePhotoPlayback,
        livePhotoPlaybackTrigger: livePhotoPlaybackTrigger
      )

      if enableLivePhotoPlayback, asset.mediaSubtypes.contains(.photoLive) {
        Label("Live", systemImage: "livephoto")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(.ultraThinMaterial, in: Capsule(style: .continuous))
          .padding(18)
      }
    }
    .frame(width: fittedSize.width, height: fittedSize.height)
    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 28, style: .continuous)
        .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.5)
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

private struct CardBackdropView: View {
  let bounds: CGSize

  var body: some View {
    RoundedRectangle(cornerRadius: 28, style: .continuous)
      .fill(Color(.secondarySystemBackground))
      .overlay(
        RoundedRectangle(cornerRadius: 28, style: .continuous)
          .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.5)
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
          .fill(Color(.tertiarySystemFill))
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
    let prefersHighQualityImage = contentMode == .fit

    if let cachedImage = PhotoLibrary.cachedImage(forKey: cacheKey) {
      image = cachedImage
      isLoaded = true
      cancelRequest()
      return
    }

    cancelRequest()
    image = nil
    isLoaded = false
    let options = PHImageRequestOptions()
    options.isNetworkAccessAllowed = true
    options.deliveryMode = prefersHighQualityImage ? .highQualityFormat : .opportunistic
    options.resizeMode = .exact

    let identifier = asset.localIdentifier
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
          guard identifier == asset.localIdentifier, image == nil else { return }
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
      let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
      Task { @MainActor in
        guard identifier == asset.localIdentifier else { return }
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

  var body: some View {
    ZStack {
      if offset > 16 {
        badge(systemImage: "checkmark", tint: AppColor.success, backgroundTint: AppColor.keepBackground, alignment: .topTrailing)
          .opacity(min(1, Double(abs(offset) - 16) / 96))
      } else if offset < -16 {
        badge(systemImage: "xmark", tint: AppColor.delete, backgroundTint: AppColor.deleteBackground, alignment: .topLeading)
          .opacity(min(1, Double(abs(offset) - 16) / 96))
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
    .shadow(color: AppColor.shadow.opacity(1.1), radius: 10, x: 0, y: 6)
    .accessibilityLabel(accessibilityLabel)
  }
}
