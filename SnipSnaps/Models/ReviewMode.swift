import SwiftUI

enum ReviewMode: String, CaseIterable, Identifiable {
  case today
  case onThisDay
  case random
  case screenshots
  case similar

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
    case .similar:
      return "Similar"
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
    case .similar:
      return "Review duplicate-looking groups"
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
    case .similar:
      return "square.stack.3d.up"
    }
  }

  private var monthDayText: String {
    Date.now.formatted(.dateTime.month(.abbreviated).day())
  }
}

enum ScreenshotSortOption: String, CaseIterable, Identifiable {
  case recent
  case oldest
  case largest
  case smallest
  case random

  var id: String { rawValue }

  var title: String {
    switch self {
    case .recent:
      return "Recent"
    case .oldest:
      return "Oldest"
    case .largest:
      return "Largest"
    case .smallest:
      return "Smallest"
    case .random:
      return "Random"
    }
  }

  var subtitle: String {
    switch self {
    case .recent:
      return "Newest first"
    case .oldest:
      return "Oldest first"
    case .largest:
      return "Biggest files first"
    case .smallest:
      return "Smallest files first"
    case .random:
      return "Shuffled each session"
    }
  }

  var systemImage: String {
    switch self {
    case .recent:
      return "clock.arrow.circlepath"
    case .oldest:
      return "calendar"
    case .largest:
      return "arrow.down.left.and.arrow.up.right"
    case .smallest:
      return "arrow.up.right.and.arrow.down.left"
    case .random:
      return "shuffle"
    }
  }
}
