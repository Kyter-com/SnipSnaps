// Prints the CoreGraphics window number of the largest on-screen normal window
// owned by the given process, or exits 1 if none.
//
//   windowid <owner-name> [pid]
//
// If a pid is given it matches on kCGWindowOwnerPID (the exact instance we just
// launched) and falls back to the owner name only if the pid matches nothing —
// so a stray or pre-existing SnipSnaps window can't be picked by the
// largest-area heuristic.
//
// Used by capture-mac.sh to feed `screencapture -l <id>`. Matches on the window
// *owner* (process name / pid), which is available without Screen Recording
// permission — only window *titles* are gated — so discovery works even before
// the user grants screen recording (the screencapture itself still needs it).
//
// Build: swiftc -O windowid.swift -o windowid

import CoreGraphics
import Foundation

let target = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "SnipSnaps"
let wantPID: Int? = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) : nil
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]

guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
  exit(1)
}

func largestWindow(matching matches: ([String: Any]) -> Bool) -> Int? {
  var best: (id: Int, area: CGFloat)?
  for window in list {
    guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
          let number = window[kCGWindowNumber as String] as? Int,
          matches(window)
    else { continue }
    var area: CGFloat = 0
    if let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] {
      area = (bounds["Width"] ?? 0) * (bounds["Height"] ?? 0)
    }
    if best == nil || area > best!.area { best = (number, area) }
  }
  return best?.id
}

// Prefer an exact pid match; fall back to the owner name.
if let wantPID, let id = largestWindow(matching: { ($0[kCGWindowOwnerPID as String] as? Int) == wantPID }) {
  print(id)
  exit(0)
}
if let id = largestWindow(matching: { ($0[kCGWindowOwnerName as String] as? String) == target }) {
  print(id)
  exit(0)
}
exit(1)
