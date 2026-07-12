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

  // Reveal the just-trashed files in Finder. Under the App Sandbox we can't
  // resolve the real ~/.Trash via .trashDirectory/.userDomainMask — that points
  // at the app container's own trash, which doesn't hold these files — but the
  // URLs FileManager.trashItem hands back point at the files' real in-Trash
  // locations, so selecting those opens the actual Trash with them highlighted
  // (and lets the user restore them).
  static func revealInTrash(_ urls: [URL]) {
    let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    guard !existing.isEmpty else { return }
    NSWorkspace.shared.activateFileViewerSelecting(existing)
  }
}
#endif
