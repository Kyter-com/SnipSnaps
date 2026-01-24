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
      sessionBackground
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
    GeometryReader { proxy in
      let horizontalPadding: CGFloat = 20
      let headerHeight: CGFloat = 72
      let buttonHeight: CGFloat = 70
      let spacing: CGFloat = 16
      let availableHeight = proxy.size.height - headerHeight - buttonHeight - spacing * 3 - proxy.safeAreaInsets.bottom
      let cardHeight = max(280, min(520, availableHeight))
      let cardSize = CGSize(width: proxy.size.width - horizontalPadding * 2, height: cardHeight)

      VStack(spacing: spacing) {
        reviewHeader
          .frame(height: headerHeight)

        cardStack(cardSize: cardSize)
          .frame(height: cardHeight)

        Spacer(minLength: 0)
      }
      .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
      .padding(.top, 12)
      .padding(.horizontal, horizontalPadding)
      .safeAreaInset(edge: .bottom) {
        decisionBar
          .padding(.horizontal, horizontalPadding)
          .padding(.bottom, 10)
      }
    }
  }

  private var reviewHeader: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(mode.subtitle)
        .font(AppFont.body(16))
        .foregroundColor(Color(red: 0.40, green: 0.46, blue: 0.56))
      HStack {
        Text("\(currentIndex + 1) of \(assets.count)")
          .font(AppFont.mono(12, weight: .semibold))
          .foregroundColor(Color(red: 0.40, green: 0.48, blue: 0.58))
        Spacer()
        ProgressView(value: progressValue)
          .tint(mode.accentColor)
          .frame(width: 140)
      }
    }
  }

  private func cardStack(cardSize: CGSize) -> some View {
    ZStack {
      if let asset = nextAsset {
        PhotoCardView(asset: asset, targetSize: cardSize)
          .scaleEffect(0.96)
          .opacity(0.55)
          .offset(y: 10)
      }
      if let asset = currentAsset {
        PhotoCardView(asset: asset, targetSize: cardSize)
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
  }

  private var decisionBar: some View {
    HStack(spacing: 14) {
      Button {
        applyDecision(.delete)
      } label: {
        DecisionButton(
          title: "Delete",
          systemImage: "trash",
          color: Color(red: 0.92, green: 0.24, blue: 0.30)
        )
      }
      Button {
        applyDecision(.keep)
      } label: {
        DecisionButton(
          title: "Keep",
          systemImage: "heart.fill",
          color: Color(red: 0.18, green: 0.64, blue: 0.36)
        )
      }
    }
    .padding(.top, 6)
  }

  private var summaryView: some View {
    ScrollView {
      VStack(spacing: 16) {
        Text("Review complete")
          .font(AppFont.display(24, weight: .semibold))
          .foregroundColor(Color(red: 0.12, green: 0.16, blue: 0.22))
        Text("\(keptAssets.count) kept - \(deleteAssets.count) to delete")
          .font(AppFont.body(15))
          .foregroundColor(Color(red: 0.40, green: 0.46, blue: 0.56))

        if deletedCount > 0 {
          Text("Deleted \(deletedCount) photos.")
            .font(AppFont.body(14, weight: .semibold))
            .foregroundColor(Color(red: 0.26, green: 0.62, blue: 0.50))
        }

        if deleteAssets.isEmpty {
          Text("Nothing marked for deletion.")
            .font(AppFont.body(15))
            .foregroundColor(Color(red: 0.40, green: 0.46, blue: 0.56))
            .padding(.vertical, 8)
        } else {
          Text("Estimated space to free: \(estimatedDeleteBytesText)")
            .font(AppFont.body(14))
            .foregroundColor(Color(red: 0.38, green: 0.46, blue: 0.54))
          let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
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
            .font(AppFont.body(14))
            .foregroundColor(Color(red: 0.38, green: 0.46, blue: 0.54))
          Text("Lifetime space freed: \(totalDeletedBytesText)")
            .font(AppFont.body(14))
            .foregroundColor(Color(red: 0.38, green: 0.46, blue: 0.54))
        }
        .padding(.top, 4)

        Button {
          showDeleteConfirm = true
        } label: {
          PrimaryActionButton(
            title: deleteAssets.isEmpty ? "Delete 0 Photos" : "Delete \(deleteAssets.count) Photos",
            systemImage: "trash.fill",
            color: Color(red: 0.90, green: 0.20, blue: 0.24),
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
            color: mode.accentColor,
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
        .font(AppFont.display(20, weight: .semibold))
        .foregroundColor(Color(red: 0.12, green: 0.16, blue: 0.22))
      Text("Enable access to review and delete photos.")
        .font(AppFont.body(15))
        .foregroundColor(Color(red: 0.40, green: 0.46, blue: 0.56))
      Button("Enable Photo Access") {
        Task {
          authStatus = await PhotoLibrary.requestAuthorization()
          loadAssets()
        }
      }
      .buttonStyle(.borderedProminent)
      .tint(mode.accentColor)
    }
    .padding(24)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(Color.white.opacity(0.9))
        .shadow(color: Color.black.opacity(0.10), radius: 12, x: 0, y: 6)
    )
    .padding(.horizontal, 24)
  }

  private var loadingView: some View {
    ProgressView("Loading \(mode.title.lowercased()) photos...")
      .padding(24)
      .background(
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .fill(Color.white.opacity(0.9))
      )
  }

  private var emptyView: some View {
    VStack(spacing: 12) {
      Text("No photos found")
        .font(AppFont.display(20, weight: .semibold))
        .foregroundColor(Color(red: 0.12, green: 0.16, blue: 0.22))
      Text("Try a different review mode.")
        .font(AppFont.body(15))
        .foregroundColor(Color(red: 0.40, green: 0.46, blue: 0.56))
      Button("Back") {
        dismiss()
      }
      .buttonStyle(.bordered)
    }
    .padding(24)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(Color.white.opacity(0.9))
        .shadow(color: Color.black.opacity(0.10), radius: 12, x: 0, y: 6)
    )
    .padding(.horizontal, 24)
  }

  private var sessionBackground: some View {
    LinearGradient(
      colors: [
        Color(red: 0.98, green: 0.98, blue: 0.99),
        Color(red: 0.94, green: 0.96, blue: 0.98),
      ],
      startPoint: .top,
      endPoint: .bottom
    )
    .ignoresSafeArea()
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
    ZStack {
      RoundedRectangle(cornerRadius: 26, style: .continuous)
        .fill(Color.white)
      PhotoAssetImageView(asset: asset, targetSize: targetSize)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
    .overlay(
      RoundedRectangle(cornerRadius: 26, style: .continuous)
        .stroke(Color.white.opacity(0.4), lineWidth: 1)
    )
    .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 10)
  }
}

private struct PhotoThumbnailView: View {
  let asset: PHAsset

  var body: some View {
    PhotoAssetImageView(asset: asset, targetSize: CGSize(width: 120, height: 120))
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}

private struct PhotoAssetImageView: View {
  let asset: PHAsset
  let targetSize: CGSize

  @State private var image: PlatformImage?
  @State private var requestId: PHImageRequestID?
  @State private var isLoaded = false

  var body: some View {
    ZStack {
      if let image {
        platformImageView(image)
          .resizable()
          .scaledToFill()
          .opacity(isLoaded ? 1 : 0)
      } else {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .fill(
            LinearGradient(
              colors: [
                Color.white.opacity(0.6),
                Color(red: 0.88, green: 0.93, blue: 0.98),
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
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
    let options = PHImageRequestOptions()
    options.isNetworkAccessAllowed = true
    options.deliveryMode = .highQualityFormat
    options.resizeMode = .fast

    let scale = platformScale
    let size = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)
    requestId = PHImageManager.default().requestImage(
      for: asset,
      targetSize: size,
      contentMode: .aspectFill,
      options: options
    ) { result, _ in
      if let result {
        image = result
        withAnimation(.easeOut(duration: 0.2)) {
          isLoaded = true
        }
      }
    }
  }

  private func cancelRequest() {
    if let requestId {
      PHImageManager.default().cancelImageRequest(requestId)
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
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .background(Color.green.opacity(0.85))
          .foregroundColor(.white)
          .clipShape(Capsule())
        Spacer()
      }
      .padding(20)
    } else if offset < -20 {
      HStack {
        Spacer()
        Label("DELETE", systemImage: "trash.fill")
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .background(Color.red.opacity(0.85))
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
        .font(.system(size: 16, weight: .semibold))
      Text(title)
        .font(AppFont.body(16, weight: .semibold))
    }
    .foregroundColor(.white)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 14)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(color)
    )
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
        .font(.system(size: 15, weight: .semibold))
      Text(title)
        .font(AppFont.body(16, weight: .semibold))
    }
    .foregroundColor(.white)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 14)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(color.opacity(isEnabled ? 1.0 : 0.45))
    )
  }
}
