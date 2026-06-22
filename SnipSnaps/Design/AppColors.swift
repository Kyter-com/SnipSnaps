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

  #if canImport(UIKit)
  static let background = Color(.systemGroupedBackground)
  static let card = Color(.secondarySystemGroupedBackground)
  static let chip = Color(.tertiarySystemGroupedBackground)
  static let elevatedCard = Color(.secondarySystemBackground)
  static let fill = Color(.tertiarySystemFill)
  static let separator = Color(.separator)
  #elseif canImport(AppKit)
  static let background = Color(nsColor: .windowBackgroundColor)
  static let card = Color(nsColor: .controlBackgroundColor)
  static let chip = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
  static let elevatedCard = Color(nsColor: .controlBackgroundColor)
  static let fill = Color(nsColor: .quaternaryLabelColor)
  static let separator = Color(nsColor: .separatorColor)
  #endif
}
