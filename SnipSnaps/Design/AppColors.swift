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
  static let keep = Color(.systemPink)
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
  // macOS card hierarchy: the window/scroll surface must read as RECESSED and the
  // cards as RAISED, or both collapse to the same light gray and every card
  // becomes invisible in Light mode. underPageBackgroundColor is the recessed
  // backdrop; controlBackgroundColor / textBackgroundColor are the raised (near
  // white) card surfaces.
  static let background = Color(nsColor: .underPageBackgroundColor)
  static let card = Color(nsColor: .controlBackgroundColor)
  static let chip = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
  static let elevatedCard = Color(nsColor: .textBackgroundColor)
  static let fill = Color(nsColor: .quaternaryLabelColor)
  static let separator = Color(nsColor: .separatorColor)
  #endif
}
