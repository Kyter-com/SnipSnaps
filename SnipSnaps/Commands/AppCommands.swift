#if os(macOS)
import SwiftUI
import AppKit

// Native macOS menu-bar commands. The Help menu is retargeted at SnipSnaps' real
// support/legal URLs (the default SwiftUI Help menu is empty). The Review menu
// and Edit ▸ Undo are wired to the active review surface via focused values.
struct AppCommands: Commands {
  var body: some Commands {
    // Edit ▸ Undo routed to whichever review owns the focus, so ⌘Z works
    // regardless of which control is focused (and on the summary screen).
    CommandGroup(replacing: .undoRedo) {
      FocusedReviewUndoButton()
    }

    // File ▸ Add Folder… for the Files surface.
    CommandGroup(after: .newItem) {
      FocusedAddFolderButton()
    }

    CommandMenu("Review") {
      FocusedReviewActionButtons()
    }

    CommandGroup(replacing: .help) {
      Button("SnipSnaps Support") { Self.open("https://kyter.com/snipsnaps/support/") }
      Button("GitHub Repository") { Self.open("https://github.com/Kyter-com/SnipSnaps") }
      Button("Send Feedback…") { Self.open("mailto:dev@kyter.com?subject=SnipSnaps%20App%20Feedback") }
      Divider()
      Button("Privacy Policy") { Self.open("https://kyter.com/snipsnaps/privacy/") }
      Button("Terms & Conditions") { Self.open("https://kyter.com/snipsnaps/terms/") }
    }
  }

  static func open(_ string: String) {
    if let url = URL(string: string) {
      NSWorkspace.shared.open(url)
    }
  }
}

// MARK: - Focused review bridge

// A review screen publishes this so the menu bar can drive Keep / Delete / Undo /
// Skip on the currently-active review, with items auto-disabling elsewhere.
struct ReviewActions {
  var keep: (() -> Void)?
  var delete: (() -> Void)?
  var undo: (() -> Void)?
  var skipGroup: (() -> Void)?
  var canUndo: Bool = false
}

struct ReviewActionsFocusedValueKey: FocusedValueKey {
  typealias Value = ReviewActions
}

// Files surface publishes its "add folder" hook so File ▸ Add Folder… works.
struct AddFolderFocusedValueKey: FocusedValueKey {
  typealias Value = () -> Void
}

extension FocusedValues {
  var reviewActions: ReviewActions? {
    get { self[ReviewActionsFocusedValueKey.self] }
    set { self[ReviewActionsFocusedValueKey.self] = newValue }
  }

  var addFolderAction: (() -> Void)? {
    get { self[AddFolderFocusedValueKey.self] }
    set { self[AddFolderFocusedValueKey.self] = newValue }
  }
}

private struct FocusedReviewUndoButton: View {
  @FocusedValue(\.reviewActions) private var actions

  var body: some View {
    Button("Undo") { actions?.undo?() }
      .keyboardShortcut("z", modifiers: .command)
      .disabled(!(actions?.canUndo ?? false))
  }
}

private struct FocusedAddFolderButton: View {
  @FocusedValue(\.addFolderAction) private var addFolder

  var body: some View {
    Button("Add Folder…") { addFolder?() }
      .keyboardShortcut("o", modifiers: [.command, .shift])
      .disabled(addFolder == nil)
  }
}

// Click-only menu items (discoverability + VoiceOver). The matching ←/→/Delete/s
// keys are owned by in-view buttons on the active review, so these intentionally
// carry NO keyboardShortcut to avoid a double-owned key equivalent.
private struct FocusedReviewActionButtons: View {
  @FocusedValue(\.reviewActions) private var actions

  var body: some View {
    Button("Keep  →") { actions?.keep?() }
      .disabled(actions?.keep == nil)
    Button("Move to Trash  ←") { actions?.delete?() }
      .disabled(actions?.delete == nil)
    Button("Skip Group  S") { actions?.skipGroup?() }
      .disabled(actions?.skipGroup == nil)
  }
}
#endif
