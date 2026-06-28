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
  // Folders that resolved but whose security scope could not be opened this launch
  // (the user sees them but scans find nothing — surfaced as "couldn't access").
  @Published private(set) var inaccessiblePaths: Set<String> = []

  private let defaultsKey = "filesGrantedFolderBookmarksV1"
  private var accessing: [URL] = []
  // Maps a resolved folder path → the exact stored bookmark bytes, so remove() can
  // drop precisely that bookmark (even if it later stops resolving) without
  // disturbing other — possibly transiently-offline — grants.
  private var bookmarkByPath: [String: Data] = [:]

  init() {
    restore()
  }

  // Balance the security scopes opened in restore() if the store is ever torn down
  // mid-process (deinit is nonisolated; stopAccessingSecurityScopedResource is
  // thread-safe and `accessing` is a plain value array).
  deinit {
    for url in accessing {
      url.stopAccessingSecurityScopedResource()
    }
  }

  // The URL comes from NSOpenPanel (or a Finder drag) and is already accessible;
  // capture a durable app-scoped bookmark so the grant survives relaunch.
  func add(_ url: URL) {
    // Already granted AND working — nothing to do. But if the path is listed yet
    // inaccessible (stale bookmark), fall through to re-grant with the fresh one.
    if folders.contains(where: { $0.url.path == url.path }), !inaccessiblePaths.contains(url.path) {
      return
    }
    do {
      let data = try url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      var stored = storedBookmarks()
      // Re-granting a stale/inaccessible folder: drop its old bookmark first so
      // the fresh, working one replaces it instead of being deduped away.
      if let old = bookmarkByPath[url.path] {
        stored.removeAll { $0 == old }
      }
      stored.append(data)
      save(stored)
      restore()
    } catch {
      NSLog("SnipSnaps: failed to bookmark folder \(url.path): \(error)")
    }
  }

  func remove(_ folder: Folder) {
    if let targetData = bookmarkByPath[folder.url.path] {
      // Drop exactly the targeted bookmark; keep every other stored bookmark
      // (including any that are transiently offline) untouched.
      save(storedBookmarks().filter { $0 != targetData })
    } else {
      // Fallback: no stored mapping (shouldn't happen for a listed folder) — drop
      // any bookmark that currently resolves to this path.
      save(storedBookmarks().filter { resolve($0)?.url.path != folder.url.path })
    }
    restore()
  }

  // MARK: - Private

  private func restore() {
    // Diff against the scopes already open rather than blanket stop-all/start-all:
    // re-opening every folder on each add()/remove() would momentarily revoke access
    // to retained folders, which a background scan/trash task may still be using.
    let previouslyAccessing = accessing
    var stillAccessing: [URL] = []

    var resolved: [Folder] = []
    var refreshed: [Data] = []
    var byPath: [String: Data] = [:]
    var inaccessible: Set<String> = []
    for data in storedBookmarks() {
      guard let entry = resolve(data) else {
        // Transient failure (e.g. an external/network volume that's offline right
        // now). Keep the bookmark so the grant survives relaunch; just don't list
        // the folder this session. Only an explicit remove() drops it.
        refreshed.append(data)
        continue
      }
      if resolved.contains(where: { $0.url.path == entry.url.path }) { continue }
      let freshData = entry.refreshedData ?? data
      // Reuse the already-open scope (and its URL instance) for a retained folder so
      // its access is never interrupted; only newly-granted folders open a scope.
      let folderURL: URL
      if let open = previouslyAccessing.first(where: { $0.path == entry.url.path }) {
        stillAccessing.append(open)
        folderURL = open
      } else if entry.url.startAccessingSecurityScopedResource() {
        stillAccessing.append(entry.url)
        folderURL = entry.url
      } else {
        inaccessible.insert(entry.url.path)
        folderURL = entry.url
      }
      resolved.append(Folder(url: folderURL))
      refreshed.append(freshData)
      byPath[folderURL.path] = freshData
    }

    // Release only the scopes for folders that are no longer granted.
    let retainedPaths = Set(stillAccessing.map(\.path))
    for url in previouslyAccessing where !retainedPaths.contains(url.path) {
      url.stopAccessingSecurityScopedResource()
    }

    accessing = stillAccessing
    folders = resolved
    bookmarkByPath = byPath
    inaccessiblePaths = inaccessible
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
