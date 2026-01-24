import Foundation
import Photos
import SwiftUI

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

struct ReviewSessionView: View {
  let mode: ReviewMode

  @Environment(\.dismiss) private var dismiss
  @State private var authStatus = PhotoLibrary.authorizationStatus()
  @State private var isLoading = true
  @State private var assets: [PHAsset] = []
  @State private var currentIndex = 0
  @State private var keptAssets: [PHAsset] = []
  @State private var deleteAssets: [PHAsset] = []
  @State private var dragOffset: CGSize = .zero
  @State private var isAnimatingCard = false
  @State private var showSummary = false
  @State private var showDeleteConfirm = false
  @State private var showError = false
  @State private var errorMessage = ""
  @State private var deleteInProgress = false
  @State private var deletedCount = 0
  @State private var cardOpacity = 1.0
  @State private var cardSize: CGSize = .zero
  @State private var cachedAssets: [PHAsset] = []
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
    .toolbar {
      if showSummary {
        Button("Done") {
          dismiss()
        }
      }
    }
    .onAppear {
      loadAssets()
    }
    .onChange(of: currentIndex) { _, _ in
      updateCaching()
    }
    .onChange(of: assets.count) { _, _ in
      updateCaching()
    }
    .alert("Delete selected photos?", isPresented: $showDeleteConfirm) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive) {
        deleteSelected()
      }
    } message: {
      Text("This will permanently remove \(deleteAssets.count) photos from your library.")
    }
    .alert("Something went wrong", isPresented: $showError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }

  private var reviewView: some View {
    VStack {
        reviewHeader.padding(.horizontal)
        
        Spacer()
        
        cardStack
            .padding(.horizontal)
        
        Spacer()
        
        decisionBar
            .padding()
    }
  }

  private var reviewHeader: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(mode.subtitle)
        .font(.subheadline)
        .foregroundColor(AppColor.subtext)
      HStack {
        Text("\(currentIndex + 1) of \(assets.count)")
          .font(.caption.weight(.medium))
          .foregroundColor(AppColor.subtext)
        Spacer()
        ProgressView(value: progressValue)
          .tint(mode.accentColor)
          .frame(width: 140)
      }
    }
  }

  private var cardStack: some View {
      GeometryReader { proxy in
          ZStack {
              if let asset = nextAsset {
                  PhotoCardView(asset: asset, targetSize: proxy.size)
                      .frame(width: proxy.size.width, height: proxy.size.height)
                      .scaleEffect(0.96)
                      .opacity(0.55)
                      .offset(y: 10)
              }
              if let asset = currentAsset {
                  PhotoCardView(asset: asset, targetSize: proxy.size)
                      .frame(width: proxy.size.width, height: proxy.size.height)
                      .id(asset.localIdentifier)
                      .overlay(SwipeOverlayView(offset: dragOffset.width))
                      .offset(dragOffset)
                      .rotationEffect(.degrees(Double(dragOffset.width / 20)))
                      .opacity(cardOpacity)
                      .gesture(
                          DragGesture()
                              .onChanged { value in
                                  guard !isAnimatingCard else { return }
                                  dragOffset = value.translation
                              }
                              .onEnded { value in
                                  guard !isAnimatingCard else { return }
                                  handleSwipe(value.translation.width)
                              }
                      )
              }
          }
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

  private var decisionBar: some View {
    HStack(spacing: 14) {
      Button {
        applyDecision(.delete)
      } label: {
        DecisionButton(
          title: "Delete",
          systemImage: "trash",
          color: AppColor.delete
        )
      }
      Button {
        applyDecision(.keep)
      } label: {
        DecisionButton(
          title: "Keep",
          systemImage: "heart.fill",
          color: AppColor.keep
        )
      }
    }
  }

  private var summaryView: some View {
    ScrollView {
      VStack(spacing: 16) {
        Text("Review complete")
            .font(.largeTitle.weight(.bold))
            .foregroundColor(AppColor.text)
        Text("\(keptAssets.count) kept - \(deleteAssets.count) to delete")
          .font(.subheadline)
          .foregroundColor(AppColor.subtext)

        if deletedCount > 0 {
          Text("Deleted \(deletedCount) photos.")
            .font(.headline)
            .foregroundColor(AppColor.keep)
        }

        if deleteAssets.isEmpty {
          Text("Nothing marked for deletion.")
            .font(.subheadline)
            .foregroundColor(AppColor.subtext)
            .padding(.vertical, 8)
        } else {
          Text("Estimated space to free: \(estimatedDeleteBytesText)")
            .font(.caption)
            .foregroundColor(AppColor.subtext)
          let columns = [GridItem(.adaptive(minimum: 80))]
          LazyVGrid(columns: columns, spacing: 8) {
            ForEach(deleteAssets, id: \.localIdentifier) { asset in
              PhotoThumbnailView(asset: asset)
            }
          }
        }

        if deleteInProgress {
          ProgressView("Deleting...")
            .padding(.top, 8)
        }

        VStack(spacing: 6) {
          Text("Lifetime deleted: \(totalDeletedCount) photos")
            .font(.caption)
            .foregroundColor(AppColor.subtext)
          Text("Lifetime space freed: \(totalDeletedBytesText)")
            .font(.caption)
            .foregroundColor(AppColor.subtext)
        }
        .padding(.top, 4)

        Button {
          showDeleteConfirm = true
        } label: {
          PrimaryActionButton(
            title: deleteAssets.isEmpty ? "Delete 0 Photos" : "Delete \(deleteAssets.count) Photos",
            systemImage: "trash.fill",
            color: AppColor.delete,
            isEnabled: !deleteAssets.isEmpty && !deleteInProgress
          )
        }
        .disabled(deleteAssets.isEmpty || deleteInProgress)

        Button {
          dismiss()
        } label: {
          PrimaryActionButton(
            title: "Done",
            systemImage: "checkmark",
            color: AppColor.primary,
            isEnabled: !deleteInProgress
          )
        }
        .disabled(deleteInProgress)
      }
      .padding(.horizontal, 20)
      .padding(.top, 12)
      .padding(.bottom, 32)
    }
  }

  private var accessView: some View {
    VStack(spacing: 16) {
        Text("Photo access required")
            .font(.title2.weight(.bold))
            .foregroundColor(AppColor.text)
        Text("Enable access to review and delete photos.")
            .font(.subheadline)
            .foregroundColor(AppColor.subtext)
        Button("Enable Photo Access") {
            Task {
                authStatus = await PhotoLibrary.requestAuthorization()
                loadAssets()
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(AppColor.primary)
    }
    .padding(24)
    .background(AppColor.card)
    .cornerRadius(18)
    .shadow(color: AppColor.shadow, radius: 12, x: 0, y: 6)
    .padding(.horizontal, 24)
  }

  private var loadingView: some View {
    ProgressView("Loading \(mode.title.lowercased()) photos...")
      .padding(24)
      .background(AppColor.card)
      .cornerRadius(18)
  }

  private var emptyView: some View {
      ContentUnavailableView {
          Label("No Photos Found", systemImage: "photo.on.rectangle.angled")
      } description: {
          Text("Try a different review mode, or check your photo library.")
      } actions: {
          Button("Back") {
              dismiss()
          }
      }
  }

  private func loadAssets() {
    isLoading = true
    Task {
      let status = await PhotoLibrary.ensureAuthorization()
      await MainActor.run {
        authStatus = status
      }
      guard PhotoLibrary.canAccessPhotos(status) else {
        await MainActor.run {
          isLoading = false
        }
        return
      }
      let fetched = PhotoLibrary.fetchAssets(for: mode, limit: sessionLimit)
      await MainActor.run {
        assets = fetched
        currentIndex = 0
        keptAssets = []
        deleteAssets = []
        deletedCount = 0
        showSummary = fetched.isEmpty
        isLoading = false
      }
    }
  }

  private func handleSwipe(_ width: CGFloat) {
    let threshold: CGFloat = 120
    if width > threshold {
      applyDecision(.keep)
    } else if width < -threshold {
      applyDecision(.delete)
    } else {
      withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
        dragOffset = .zero
      }
    }
  }

  private func applyDecision(_ decision: PhotoDecision) {
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
    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
      dragOffset = CGSize(width: direction * 600, height: 0)
      cardOpacity = 0.0
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
      advance()
      dragOffset = .zero
      cardOpacity = 1.0
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
    let targetSize = PhotoLibrary.scaledSize(for: cardSize)
    let nextAssets = [currentAsset, nextAsset].compactMap { $0 }
    PhotoLibrary.stopCachingAssets(cachedAssets, targetSize: targetSize)
    PhotoLibrary.startCachingAssets(nextAssets, targetSize: targetSize)
    cachedAssets = nextAssets
  }

  private func deleteSelected() {
    guard !deleteAssets.isEmpty, !deleteInProgress else { return }
    deleteInProgress = true
    let targetCount = deleteAssets.count
    let estimatedBytes = estimatedDeleteBytes
    Task {
      do {
        try await PhotoLibrary.deleteAssets(deleteAssets)
        await MainActor.run {
          deletedCount = targetCount
          deleteAssets = []
          deleteInProgress = false
          totalDeletedCount += targetCount
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
    let generator = UINotificationFeedbackGenerator()
    generator.prepare()
    let result: UINotificationFeedbackGenerator.FeedbackType = decision == .keep ? .success : .warning
    generator.notificationOccurred(result)
    #endif
  }

  private func triggerDeleteHaptic() {
    #if canImport(UIKit)
    let generator = UINotificationFeedbackGenerator()
    generator.prepare()
    generator.notificationOccurred(.success)
    #endif
  }
}

private struct PhotoCardView: View {
  let asset: PHAsset
  let targetSize: CGSize

  var body: some View {
    PhotoAssetImageView(asset: asset, targetSize: targetSize)
        .background(AppColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: AppColor.shadow, radius: 10, x: 0, y: 5)
  }
}

private struct PhotoThumbnailView: View {
  let asset: PHAsset

  var body: some View {
    PhotoAssetImageView(asset: asset, targetSize: CGSize(width: 120, height: 120))
      .cornerRadius(12)
  }
}

private struct PhotoAssetImageView: View {
  let asset: PHAsset
  let targetSize: CGSize

  @State private var image: PlatformImage?
  @State private var requestId: PHImageRequestID?
  @State private var isLoaded = false
  @State private var assetIdentifier = ""

  var body: some View {
    ZStack {
      if let image {
        platformImageView(image)
          .resizable()
          .scaledToFill()
          .opacity(isLoaded ? 1 : 0)
      } else {
        Rectangle()
          .fill(Color.gray.opacity(0.1))
      }
    }
    .clipped()
    .onAppear {
      requestImage()
    }
    .onChange(of: asset.localIdentifier) { _, _ in
      requestImage()
    }
    .onDisappear {
      cancelRequest()
    }
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
    cancelRequest()
    image = nil
    isLoaded = false
    assetIdentifier = asset.localIdentifier
    let options = PHImageRequestOptions()
    options.isNetworkAccessAllowed = true
    options.deliveryMode = .opportunistic
    options.resizeMode = .fast

    let scale = platformScale
    let size = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)
    requestId = PhotoLibrary.imageManager.requestImage(
      for: asset,
      targetSize: size,
      contentMode: .aspectFill,
      options: options
    ) { result, info in
      guard let result else { return }
      let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
      Task { @MainActor in
        guard assetIdentifier == asset.localIdentifier else { return }
        image = result
        if isDegraded {
          isLoaded = true
        } else {
          withAnimation(.easeOut(duration: 0.2)) {
            isLoaded = true
          }
        }
      }
    }
  }

  private func cancelRequest() {
    if let requestId {
      PhotoLibrary.imageManager.cancelImageRequest(requestId)
    }
    requestId = nil
  }

  private var platformScale: CGFloat {
    #if canImport(UIKit)
    return UIScreen.main.scale
    #elseif canImport(AppKit)
    return NSScreen.main?.backingScaleFactor ?? 2.0
    #else
    return 2.0
    #endif
  }
}

private struct SwipeOverlayView: View {
  let offset: CGFloat

  var body: some View {
    if offset > 20 {
      HStack {
        Label("KEEP", systemImage: "heart.fill")
          .font(.headline)
          .padding()
          .background(AppColor.keep.opacity(0.85))
          .foregroundColor(.white)
          .clipShape(Capsule())
        Spacer()
      }
      .padding(20)
    } else if offset < -20 {
      HStack {
        Spacer()
        Label("DELETE", systemImage: "trash.fill")
          .font(.headline)
          .padding()
          .background(AppColor.delete.opacity(0.85))
          .foregroundColor(.white)
          .clipShape(Capsule())
      }
      .padding(20)
    }
  }
}

private struct DecisionButton: View {
  let title: String
  let systemImage: String
  let color: Color

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: systemImage)
        .font(.headline)
      Text(title)
        .fontWeight(.semibold)
    }
    .foregroundColor(.white)
    .frame(maxWidth: .infinity, minHeight: 50)
    .background(color)
    .cornerRadius(16)
    .shadow(color: color.opacity(0.35), radius: 10, x: 0, y: 6)
  }
}

private struct PrimaryActionButton: View {
  let title: String
  let systemImage: String
  let color: Color
  let isEnabled: Bool

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: systemImage)
        .font(.headline)
      Text(title)
        .fontWeight(.semibold)
    }
    .foregroundColor(.white)
    .frame(maxWidth: .infinity, minHeight: 50)
    .background(color.opacity(isEnabled ? 1.0 : 0.45))
    .cornerRadius(16)
  }
}
