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

  struct ExcludedFolder: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    var name: String { url.lastPathComponent }
  }

  @Published private(set) var folders: [Folder] = []
  @Published private(set) var excludedFolders: [ExcludedFolder] = []
  // Folders that resolved but whose security scope could not be opened this launch
  // (the user sees them but scans find nothing — surfaced as "couldn't access").
  @Published private(set) var inaccessiblePaths: Set<String> = []

  private let defaultsKey = "filesGrantedFolderBookmarksV1"
  private let excludedPathsDefaultsKey = "filesExcludedFolderPathsV1"
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
      // An explicit review grant wins over an older broader exclusion. Since an
      // exclusion cannot represent a "hole", remove any exclusion that contains
      // the newly granted root rather than silently skipping a folder the user
      // just asked SnipSnaps to review.
      let granted = url.standardizedFileURL
      saveExcludedPaths(storedExcludedPaths().filter { path in
        let excluded = URL(fileURLWithPath: path, isDirectory: true)
        return !Self.isDescendant(granted, of: excluded)
      })
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

  var excludedPaths: Set<String> {
    Set(excludedFolders.map { $0.url.standardizedFileURL.path })
  }

  // Exclusions are path-based because they are always descendants of an already
  // security-scoped review folder. Adding a parent exclusion automatically folds
  // any narrower child exclusions into it.
  @discardableResult
  func exclude(_ url: URL) -> Bool {
    let candidate = url.standardizedFileURL
    let isDirectory = (try? candidate.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    guard isDirectory,
          !folders.contains(where: {
            candidate.path == $0.url.standardizedFileURL.path
          }),
          !folders.contains(where: {
            Self.isDescendant($0.url, of: candidate)
          }),
          folders.contains(where: {
            Self.isDescendant(candidate, of: $0.url) && candidate.path != $0.url.standardizedFileURL.path
          }) else {
      return false
    }

    var paths = storedExcludedPaths()
      .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL.path }
    if paths.contains(where: {
      Self.isDescendant(candidate, of: URL(fileURLWithPath: $0, isDirectory: true))
    }) {
      return true
    }

    paths.removeAll {
      Self.isDescendant(URL(fileURLWithPath: $0, isDirectory: true), of: candidate)
    }
    paths.append(candidate.path)
    saveExcludedPaths(paths)
    restoreExcludedFolders()
    return true
  }

  func include(_ folder: ExcludedFolder) {
    let target = folder.url.standardizedFileURL.path
    saveExcludedPaths(storedExcludedPaths().filter {
      URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL.path != target
    })
    restoreExcludedFolders()
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
    restoreExcludedFolders()
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

  private func restoreExcludedFolders() {
    let reviewedRoots = folders.map(\.url)
    var seen = Set<String>()
    excludedFolders = storedExcludedPaths().compactMap { path in
      let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
      guard seen.insert(url.path).inserted,
            reviewedRoots.contains(where: {
              Self.isDescendant(url, of: $0) && url.path != $0.standardizedFileURL.path
            }),
            !reviewedRoots.contains(where: { $0.standardizedFileURL.path == url.path }) else {
        return nil
      }
      return ExcludedFolder(url: url)
    }
    .sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
  }

  private func storedExcludedPaths() -> [String] {
    UserDefaults.standard.stringArray(forKey: excludedPathsDefaultsKey) ?? []
  }

  private func saveExcludedPaths(_ paths: [String]) {
    if paths.isEmpty {
      UserDefaults.standard.removeObject(forKey: excludedPathsDefaultsKey)
    } else {
      UserDefaults.standard.set(Array(Set(paths)).sorted(), forKey: excludedPathsDefaultsKey)
    }
  }

  private static func isDescendant(_ candidate: URL, of parent: URL) -> Bool {
    let candidatePath = candidate.standardizedFileURL.path
    let parentPath = parent.standardizedFileURL.path
    guard candidatePath != parentPath else { return true }
    let prefix = parentPath == "/" ? "/" : parentPath + "/"
    return candidatePath.hasPrefix(prefix)
  }
}
#endif
