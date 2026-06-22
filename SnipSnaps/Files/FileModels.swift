#if os(macOS)
import Foundation
import UniformTypeIdentifiers

enum FileDecision {
  case keep
  case delete
}

// One loose on-disk file surfaced for review. Value type built from URL resource
// values so it is Sendable and can be scanned off the main actor.
struct FileItem: Identifiable, Hashable, Sendable {
  let url: URL
  let size: Int64
  let modified: Date
  let created: Date
  let contentType: UTType?

  var id: URL { url }
  var name: String { url.lastPathComponent }
  var parentPath: String { url.deletingLastPathComponent().path }

  var sizeText: String {
    ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
  }

  var isImage: Bool {
    contentType?.conforms(to: .image) ?? false
  }

  // macOS screenshots land on disk as images named "Screenshot …" / "Screen Shot …".
  // Filenames can be localized or renamed, so this is a heuristic the user confirms.
  var isScreenshot: Bool {
    guard isImage else { return false }
    let lower = name.lowercased()
    return lower.contains("screenshot") || lower.contains("screen shot")
  }
}

enum FileReviewCategory: String, CaseIterable, Identifiable, Sendable {
  case everything
  case large
  case old
  case screenshots

  var id: String { rawValue }

  var title: String {
    switch self {
    case .everything: return "Everything"
    case .large: return "Large Files"
    case .old: return "Old Files"
    case .screenshots: return "Screenshots"
    }
  }

  var subtitle: String {
    switch self {
    case .everything: return "Every file in your folders"
    case .large: return "Files 50 MB and up"
    case .old: return "Untouched for 6+ months"
    case .screenshots: return "Screenshots saved to disk"
    }
  }

  var systemImage: String {
    switch self {
    case .everything: return "folder"
    case .large: return "internaldrive"
    case .old: return "clock.badge.xmark"
    case .screenshots: return "rectangle.on.rectangle"
    }
  }
}
#endif
