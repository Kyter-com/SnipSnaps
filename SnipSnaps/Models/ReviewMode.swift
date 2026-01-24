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
    switch self {
    case .today:
      return Color(red: 0.36, green: 0.84, blue: 0.98)
    case .random:
      return Color(red: 0.42, green: 0.92, blue: 0.72)
    case .screenshots:
      return Color(red: 0.46, green: 0.95, blue: 0.62)
    }
  }

  var gradient: LinearGradient {
    switch self {
    case .today:
      return LinearGradient(
        colors: [
          Color(red: 0.34, green: 0.90, blue: 0.96),
          Color(red: 0.20, green: 0.52, blue: 0.98),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    case .random:
      return LinearGradient(
        colors: [
          Color(red: 0.28, green: 0.92, blue: 0.74),
          Color(red: 0.12, green: 0.64, blue: 0.84),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    case .screenshots:
      return LinearGradient(
        colors: [
          Color(red: 0.46, green: 0.96, blue: 0.62),
          Color(red: 0.14, green: 0.66, blue: 0.56),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    }
  }
}
