import SwiftUI

enum ReviewMode: String, CaseIterable, Identifiable {
  case today
  case onThisDay
  case random
  case screenshots
  case oldScreenshots
  case videos
  case screenRecordings
  case largePhotos
  case livePhotos
  case bursts
  case recentlyEdited
  case oldFavorites
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
    case .oldScreenshots:
      return "Old Screenshots"
    case .videos:
      return "Videos"
    case .screenRecordings:
      return "Screen Recordings"
    case .largePhotos:
      return "Large Photos"
    case .livePhotos:
      return "Live Photos"
    case .bursts:
      return "Bursts"
    case .recentlyEdited:
      return "Recently Edited"
    case .oldFavorites:
      return "Old Favorites"
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
    case .oldScreenshots:
      return "Screenshots older than a month"
    case .videos:
      return "Review space-hungry clips"
    case .screenRecordings:
      return "Find recorded clips"
    case .largePhotos:
      return "Review high-resolution space savers"
    case .livePhotos:
      return "Review animated photos"
    case .bursts:
      return "Choose the best from bursts"
    case .recentlyEdited:
      return "Check touched-up shots"
    case .oldFavorites:
      return "Revisit favorites from past years"
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
    case .oldScreenshots:
      return "clock.badge.xmark"
    case .videos:
      return "video.fill"
    case .screenRecordings:
      return "record.circle"
    case .largePhotos:
      return "internaldrive"
    case .livePhotos:
      return "livephoto"
    case .bursts:
      return "bolt.fill"
    case .recentlyEdited:
      return "slider.horizontal.3"
    case .oldFavorites:
      return "heart.fill"
    case .similar:
      return "square.stack.3d.up"
    }
  }

  var reviewsVideos: Bool {
    self == .videos || self == .screenRecordings
  }

  private var monthDayText: String {
    Date.now.formatted(.dateTime.month(.abbreviated).day())
  }
}

enum VideoSortOption: String, CaseIterable, Identifiable {
  case recent
  case oldest
  case largest
  case shortest
  case longest
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
    case .shortest:
      return "Shortest"
    case .longest:
      return "Longest"
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
    case .shortest:
      return "Shortest clips first"
    case .longest:
      return "Longest clips first"
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
      return "internaldrive"
    case .shortest:
      return "timer"
    case .longest:
      return "timer.circle.fill"
    case .random:
      return "shuffle"
    }
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

enum SimilarSortOption: String, CaseIterable, Identifiable {
  case recent
  case oldest
  case largest
  case mostMatches
  case random

  var id: String { rawValue }

  var title: String {
    switch self {
    case .recent:
      return "Recent"
    case .oldest:
      return "Oldest"
    case .largest:
      return "Biggest"
    case .mostMatches:
      return "Matches"
    case .random:
      return "Random"
    }
  }

  var subtitle: String {
    switch self {
    case .recent:
      return "Newest groups first"
    case .oldest:
      return "Oldest groups first"
    case .largest:
      return "Most space first"
    case .mostMatches:
      return "Largest groups first"
    case .random:
      return "Shuffled each scan"
    }
  }

  var systemImage: String {
    switch self {
    case .recent:
      return "clock.arrow.circlepath"
    case .oldest:
      return "calendar"
    case .largest:
      return "internaldrive"
    case .mostMatches:
      return "square.stack.3d.up"
    case .random:
      return "shuffle"
    }
  }
}
