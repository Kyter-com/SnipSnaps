import SwiftUI

/// Where the review panel sits relative to the media it controls.
enum ReviewPanelPlacement: Equatable {
  /// Beside the media on a wide display: iPhone Duo's inner display, iPad.
  case beside
  /// Below the media when a wide display is taller than wide, including
  /// iPhone Duo's tabletop pose.
  case below
  /// A narrow column beside the media when a phone is in landscape, including
  /// iPhone Duo's outer display, so the photo keeps the full height.
  case column
}

/// Places review media beside (or above) its review panel when there's room.
///
/// Regular width and height (iPhone Duo's inner display, iPad) split the space
/// into the media and a panel: side by side when the space is wider than tall,
/// stacked otherwise. On iOS 27.1 and later an `ArrangementView` makes the
/// split. When iPhone Duo is partly folded it divides the two at the fold, so
/// neither a photo nor a button runs across it. The panel width (side by side)
/// and the panel's own height (stacked) apply while the device is flat.
///
/// Compact height (a phone in landscape, including iPhone Duo's outer display)
/// puts a narrow column of controls beside the media. Everything else keeps the
/// phone layout: compact width, Split View, and accessibility text sizes.
///
/// This view only changes presentation. Session state lives in the parent, so a
/// fold, unfold, or rotation keeps the review exactly where it was.
struct AdaptiveReviewLayout<Media: View, Panel: View, Compact: View>: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.verticalSizeClass) private var verticalSizeClass

  /// The panel's width when it sits beside the media on a wide display. `nil`
  /// splits the space evenly, which suits two photos compared side by side.
  var panelWidth: ClosedRange<CGFloat>?
  /// The column's width beside the media in landscape on a phone.
  var columnWidth: CGFloat = 300
  @ViewBuilder let media: (ReviewPanelPlacement) -> Media
  @ViewBuilder let panel: (ReviewPanelPlacement) -> Panel
  @ViewBuilder let compact: () -> Compact

  static func usesExpandedLayout(
    horizontalSizeClass: UserInterfaceSizeClass?,
    verticalSizeClass: UserInterfaceSizeClass?,
    dynamicTypeSize: DynamicTypeSize
  ) -> Bool {
    horizontalSizeClass == .regular && verticalSizeClass == .regular
      && !dynamicTypeSize.isAccessibilitySize
  }

  static func usesColumnLayout(
    verticalSizeClass: UserInterfaceSizeClass?,
    dynamicTypeSize: DynamicTypeSize
  ) -> Bool {
    verticalSizeClass == .compact && !dynamicTypeSize.isAccessibilitySize
  }

  var body: some View {
    if Self.usesExpandedLayout(
      horizontalSizeClass: horizontalSizeClass,
      verticalSizeClass: verticalSizeClass,
      dynamicTypeSize: dynamicTypeSize
    ) {
      expanded
        .accessibilityIdentifier("expandedReviewLayout")
    } else if Self.usesColumnLayout(verticalSizeClass: verticalSizeClass, dynamicTypeSize: dynamicTypeSize) {
      HStack(spacing: 0) {
        media(.column)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        panel(.column)
          .frame(width: columnWidth)
          .frame(maxHeight: .infinity)
      }
      .accessibilityIdentifier("columnReviewLayout")
    } else {
      compact()
        .accessibilityIdentifier("compactReviewLayout")
    }
  }

  @ViewBuilder
  private var expanded: some View {
    #if os(iOS)
    if #available(iOS 27.1, *) {
      // The split runs side by side when the space is wider than tall and
      // stacks otherwise, which is also how iPhone Duo's fold divides it (top
      // to bottom in landscape, across in portrait). Reading the shape here
      // rather than `splitArrangementAxis` keeps both panes in step: on iOS
      // 27.2 the secondary pane never receives the axis.
      GeometryReader { proxy in
        let placement: ReviewPanelPlacement = proxy.size.width >= proxy.size.height ? .beside : .below
        ArrangementView {
          media(placement)
        } secondary: {
          panel(placement)
            .modifier(SplitPanelSizing(width: panelWidth))
        }
        .arrangementViewStyle(.split)
      }
    } else {
      LegacyReviewSplit(panelWidth: panelWidth, media: media, panel: panel)
    }
    #else
    LegacyReviewSplit(panelWidth: panelWidth, media: media, panel: panel)
    #endif
  }
}

#if os(iOS)
@available(iOS 27.1, *)
private struct SplitPanelSizing: ViewModifier {
  let width: ClosedRange<CGFloat>?

  func body(content: Content) -> some View {
    // Stacked, the panel takes its own height and the media gets the rest.
    let stacked = content.splitArrangementFixedLayoutSize(horizontal: false, vertical: true)
    if let width {
      stacked.splitArrangementLayoutSize(
        minWidth: width.lowerBound,
        idealWidth: (width.lowerBound + width.upperBound) / 2,
        maxWidth: width.upperBound
      )
    } else {
      stacked
    }
  }
}
#endif

/// The same split for systems without `ArrangementView` (iPad before iOS 27.1).
private struct LegacyReviewSplit<Media: View, Panel: View>: View {
  let panelWidth: ClosedRange<CGFloat>?
  let media: (ReviewPanelPlacement) -> Media
  let panel: (ReviewPanelPlacement) -> Panel

  var body: some View {
    GeometryReader { proxy in
      if proxy.size.width >= proxy.size.height {
        HStack(spacing: 0) {
          media(.beside)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          panel(.beside)
            .frame(width: sideWidth(in: proxy.size.width))
            .frame(maxHeight: .infinity)
        }
      } else {
        VStack(spacing: 0) {
          media(.below)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          panel(.below)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private func sideWidth(in totalWidth: CGFloat) -> CGFloat {
    guard let panelWidth else { return totalWidth / 2 }
    return (panelWidth.lowerBound + panelWidth.upperBound) / 2
  }
}
