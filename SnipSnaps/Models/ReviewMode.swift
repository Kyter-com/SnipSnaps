import SwiftUI

enum ReviewMode: String, CaseIterable, Identifiable {
  case today
  case onThisDay
  case random
  case screenshots

  var id: String { rawValue }

  var title: String {
    switch self {
    case .today:
      return "Today"
    case .onThisDay:
      return "On This Day"
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
    case .onThisDay:
      return "Photos from \(monthDayText) across the years"
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
    case .onThisDay:
      return "calendar"
    case .random:
      return "shuffle"
    case .screenshots:
      return "rectangle.on.rectangle"
    }
  }

  private var monthDayText: String {
    Date.now.formatted(.dateTime.month(.abbreviated).day())
  }
}
