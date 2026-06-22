#if os(macOS)
import Foundation
import SwiftUI

// Persists the folders the user has granted access to as app-scoped
// security-scoped bookmarks (com.apple.security.files.bookmarks.app-scope), and
// keeps that access open for the app session so the scan/trash engine can read
// and write inside them. Sandbox rule: the user must pick each folder via the
// system panel — there is no Desktop/Documents entitlement for silent scanning.
@MainActor
final class FileFolderStore: ObservableObject {
  struct Folder: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    var name: String { url.lastPathComponent }
  }

  @Published private(set) var folders: [Folder] = []

  private let defaultsKey = "filesGrantedFolderBookmarksV1"
  private var accessing: [URL] = []

  init() {
    restore()
  }

  // The URL comes from NSOpenPanel and is already accessible; capture a durable
  // app-scoped bookmark so the grant survives relaunch.
  func add(_ url: URL) {
    guard !folders.contains(where: { $0.url.path == url.path }) else { return }
    do {
      let data = try url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      var stored = storedBookmarks()
      stored.append(data)
      save(stored)
      restore()
    } catch {
      NSLog("SnipSnaps: failed to bookmark folder \(url.path): \(error)")
    }
  }

  func remove(_ folder: Folder) {
    let kept = storedBookmarks().filter { data in
      resolve(data)?.url.path != folder.url.path
    }
    save(kept)
    restore()
  }

  // MARK: - Private

  private func restore() {
    // Balance any previously-opened scopes before re-opening the fresh set.
    for url in accessing {
      url.stopAccessingSecurityScopedResource()
    }
    accessing = []

    var resolved: [Folder] = []
    var refreshed: [Data] = []
    for data in storedBookmarks() {
      guard let entry = resolve(data) else { continue }
      if resolved.contains(where: { $0.url.path == entry.url.path }) { continue }
      if entry.url.startAccessingSecurityScopedResource() {
        accessing.append(entry.url)
      }
      resolved.append(Folder(url: entry.url))
      refreshed.append(entry.refreshedData ?? data)
    }
    folders = resolved
    save(refreshed)
  }

  private func resolve(_ data: Data) -> (url: URL, refreshedData: Data?)? {
    var stale = false
    guard let url = try? URL(
      resolvingBookmarkData: data,
      options: .withSecurityScope,
      relativeTo: nil,
      bookmarkDataIsStale: &stale
    ) else {
      return nil
    }
    guard stale else { return (url, nil) }
    let fresh = try? url.bookmarkData(
      options: .withSecurityScope,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    return (url, fresh)
  }

  private func storedBookmarks() -> [Data] {
    UserDefaults.standard.array(forKey: defaultsKey) as? [Data] ?? []
  }

  private func save(_ bookmarks: [Data]) {
    if bookmarks.isEmpty {
      UserDefaults.standard.removeObject(forKey: defaultsKey)
    } else {
      UserDefaults.standard.set(bookmarks, forKey: defaultsKey)
    }
  }
}
#endif
