import SwiftUI

enum ReviewMode: String, CaseIterable, Identifiable {
  case today
  case random
  case screenshots

  var id: String { rawValue }

  var title: String {
    switch self {
    case .today:
      return "Today"
    case .random:
      return "Random"
    case .screenshots:
      return "Screenshots"
    }
  }

  var subtitle: String {
    switch self {
    case .today:
      return "Review your newest shots"
    case .random:
      return "A surprise mix from your library"
    case .screenshots:
      return "Clear the clutter fast"
    }
  }

  var systemImage: String {
    switch self {
    case .today:
      return "sun.max.fill"
    case .random:
      return "shuffle"
    case .screenshots:
      return "rectangle.on.rectangle"
    }
  }

  var accentColor: Color {
    AppColor.primary
  }

  var gradient: LinearGradient {
    switch self {
    case .today:
        return AppColor.gradient1
    case .random:
        return AppColor.gradient2
    case .screenshots:
        return AppColor.gradient3
    }
  }
}
