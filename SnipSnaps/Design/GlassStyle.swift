import SwiftUI

// Liquid Glass styling helpers. On macOS 26 (Tahoe) these use the real Liquid Glass
// APIs; on macOS 15/16 and on iOS they fall back to the app's existing bordered /
// material look. The macOS floor is 15.0, so the glass calls are availability-gated.
extension View {
  // Primary call-to-action button.
  @ViewBuilder
  func prominentActionButton() -> some View {
    #if os(macOS)
    if #available(macOS 26, *) {
      buttonStyle(.glassProminent)
    } else {
      buttonStyle(.borderedProminent)
    }
    #else
    buttonStyle(.borderedProminent)
    #endif
  }

  // Secondary / neutral button.
  @ViewBuilder
  func secondaryActionButton() -> some View {
    #if os(macOS)
    if #available(macOS 26, *) {
      buttonStyle(.glass)
    } else {
      buttonStyle(.bordered)
    }
    #else
    buttonStyle(.bordered)
    #endif
  }

  // Subtle hover lift + pointer cursor for clickable cards on macOS (no-op on iOS).
  @ViewBuilder
  func interactiveCardHover() -> some View {
    #if os(macOS)
    modifier(MacHoverHighlight())
    #else
    self
    #endif
  }

  // Background for a small floating info chip (e.g. the review date/size pill).
  @ViewBuilder
  func infoChipBackground(cornerRadius: CGFloat = 14) -> some View {
    #if os(macOS)
    if #available(macOS 26, *) {
      glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    } else {
      materialChipBackground(cornerRadius: cornerRadius)
    }
    #else
    materialChipBackground(cornerRadius: cornerRadius)
    #endif
  }

  // Pre-Liquid-Glass (macOS 15/16) and iOS chip background: a translucent material card.
  @ViewBuilder
  fileprivate func materialChipBackground(cornerRadius: CGFloat) -> some View {
    background {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(.ultraThinMaterial)
        .overlay {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(AppColor.card.opacity(0.72))
        }
    }
  }
}

#if os(macOS)
private struct MacHoverHighlight: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovering = false

  func body(content: Content) -> some View {
    content
      // Honor Reduce Motion: keep the pointer/link affordance but drop the lift.
      .scaleEffect(reduceMotion ? 1.0 : (hovering ? 1.012 : 1.0))
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
      .onHover { hovering = $0 }
      .pointerStyle(.link)
  }
}
#endif
