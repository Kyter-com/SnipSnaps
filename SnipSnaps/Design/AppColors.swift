import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// Cross-platform semantic colors. The label/fill/background families differ
// between UIKit and AppKit (e.g. there is no NSColor.systemGroupedBackground),
// so the platform-specific values are split below. The vivid system accents
// (systemRed/Pink/Green) and SwiftUI's hierarchical primary/secondary resolve
// on both platforms, so they stay shared.
enum AppColor {
  static let primary = Color.accentColor
  static let text = Color.primary
  static let subtext = Color.secondary
  static let shadow = Color.black.opacity(0.05)
  static let delete = Color(.systemRed)
  static let success = Color(.systemGreen)
  static let deleteBackground = Color(.systemRed).opacity(0.16)
  static let keepBackground = Color(.systemGreen).opacity(0.16)

  // Hairline edge for raised cards. iOS keeps the specular-white highlight; macOS
  // uses an adaptive separator so the edge is visible in both Light and Dark.
  #if canImport(UIKit)
  static let cardEdge = Color.white.opacity(0.28)
  #elseif canImport(AppKit)
  static let cardEdge = Color(nsColor: .separatorColor)
  #endif

  #if canImport(UIKit)
  static let background = Color(.systemGroupedBackground)
  static let card = Color(.secondarySystemGroupedBackground)
  static let chip = Color(.tertiarySystemGroupedBackground)
  static let elevatedCard = Color(.secondarySystemBackground)
  static let fill = Color(.tertiarySystemFill)
  static let separator = Color(.separator)
  #elseif canImport(AppKit)
  // Explicit macOS grouped palette mirroring iOS's systemGroupedBackground family,
  // so Light and Dark read the same on Mac as on iPhone/iPad. AppKit's stock
  // semantic colors don't fit an iOS-style grouped-card layout: underPageBackground
  // is a muddy mid-gray (~#969696) in Light, and control/textBackground fall BELOW
  // the page in Dark (30 on a 40 field), so cards look recessed instead of raised.
  // These explicit values keep the invariant elevatedCard >= card > background in
  // BOTH appearances — a recessed near-white/charcoal page with lighter, raised cards.
  static let background = Color(nsColor: .snapGroupedBackground)
  static let card = Color(nsColor: .snapCard)
  static let chip = Color(nsColor: .snapChip)
  static let elevatedCard = Color(nsColor: .snapElevatedCard)
  static let fill = Color(nsColor: .quaternaryLabelColor)
  static let separator = Color(nsColor: .separatorColor)
  #endif
}

#if canImport(AppKit)
private extension NSColor {
  // Resolves `light`/`dark` per-appearance, matching any Dark Aqua variant
  // (incl. vibrant / high-contrast). Values are iOS grouped-family sRGB triples.
  static func snapDynamic(light: (Int, Int, Int), dark: (Int, Int, Int)) -> NSColor {
    NSColor(name: nil) { appearance in
      let (r, g, b) = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
      return NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
  }

  static let snapGroupedBackground = snapDynamic(light: (242, 242, 247), dark: (28, 28, 30))  // iOS systemGroupedBackground
  static let snapCard = snapDynamic(light: (255, 255, 255), dark: (44, 44, 46))               // iOS secondarySystemGroupedBackground
  static let snapChip = snapDynamic(light: (229, 229, 234), dark: (58, 58, 60))               // iOS tertiary grouped
  static let snapElevatedCard = snapDynamic(light: (255, 255, 255), dark: (50, 50, 52))       // one step above card
}
#endif
