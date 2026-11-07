import SwiftUI

extension View {
  /// Caps a column of text and buttons at a comfortable reading width and
  /// centers it, so it doesn't stretch across iPhone Duo's inner display or an
  /// iPad. No effect on iPhone, which is narrower, or on the Mac.
  func readableColumn(maxWidth: CGFloat = 560) -> some View {
    #if os(iOS)
    frame(maxWidth: maxWidth)
      .frame(maxWidth: .infinity)
    #else
    self
    #endif
  }
}

#if os(iOS)
/// Reads iPhone Duo's fold from layout geometry.
enum FoldGeometry {
  /// The width the system reserves around a fold that runs top to bottom
  /// through `proxy`'s view, including its margin for interactive content.
  ///
  /// Zero when there's no such fold: iPhone Duo held flat or closed, rotated
  /// so the fold runs across, and every device without a fold.
  static func verticalFoldWidth(in proxy: GeometryProxy) -> CGFloat {
    guard #available(iOS 27.1, *) else { return 0 }
    return proxy.reservedRegions(kind: .division)
      .filter { $0.isActive && $0.frame.height > $0.frame.width }
      .map(\.frame.width)
      .max() ?? 0
  }
}
#endif
