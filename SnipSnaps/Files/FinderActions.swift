#if os(macOS)
import AppKit

// Thin wrappers over NSWorkspace for the desktop-native file affordances on the
// Files surface. The granted folders' security scopes are already held open by
// FileFolderStore, so these operate on URLs the app can see.
enum FinderActions {
  // Reveal & select the file in a Finder window.
  static func revealInFinder(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  // Open the file in its default application (or the folder in Finder).
  static func open(_ url: URL) {
    NSWorkspace.shared.open(url)
  }

  // Open the user's Trash in Finder so they can confirm / restore what was moved.
  static func openTrash() {
    if let trash = try? FileManager.default.url(
      for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false
    ) {
      NSWorkspace.shared.open(trash)
    }
  }
}
#endif
