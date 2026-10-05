import Foundation

/// User-adjustable Similar matching strictness.
///
/// The value is a Vision feature-print distance: lower means stricter (photos
/// must look more alike to group). It mirrors the scale in PhotoLibrary's
/// Similar scan: ~0 identical, ~0.35 genuinely similar, ~0.5 unrelated photos
/// of the same general scene.
enum SimilarThreshold {
  /// Ships as the Balanced detent — the fixed threshold older builds used.
  static let defaultValue: Double = 0.35

  /// Slider bounds. Wide enough to feel different at the ends, narrow enough
  /// that Loose still groups lookalikes rather than same-scene strangers.
  static let range: ClosedRange<Double> = 0.28...0.42

  static let step: Double = 0.01

  /// Strict / Balanced / Loose stops. Crossing one fires a haptic tick.
  static let detents: [Double] = [0.30, 0.35, 0.40]

  static let presetNames = ["Strict", "Balanced", "Loose"]

  /// Nearest-detent preset name. Midpoint ties resolve toward Balanced.
  static func presetName(for value: Double) -> String {
    presetNames[detentIndex(for: value)]
  }

  /// Corrals any stored or passed-in value to the slider range so a corrupt
  /// default can only shift strictness, never disable matching or match
  /// everything. In-range values pass through untouched.
  static func clamped(_ value: Double) -> Double {
    min(max(value, range.lowerBound), range.upperBound)
  }

  /// Nearest-detent index (0/1/2). Used as the haptic trigger so the slider
  /// ticks only when settling onto a different stop.
  static func detentIndex(for value: Double) -> Int {
    let lowerMidpoint = (detents[0] + detents[1]) / 2
    let upperMidpoint = (detents[1] + detents[2]) / 2
    if value < lowerMidpoint {
      return 0
    }
    if value <= upperMidpoint {
      return 1
    }
    return 2
  }
}
