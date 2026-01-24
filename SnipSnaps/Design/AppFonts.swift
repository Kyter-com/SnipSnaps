import SwiftUI

enum AppFont {
  static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
    Font.custom("SF Pro Rounded", size: size).weight(weight)
  }

  static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
    Font.custom("SF Pro Rounded", size: size).weight(weight)
  }

  static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
    Font.custom("SF Mono", size: size).weight(weight)
  }
}
