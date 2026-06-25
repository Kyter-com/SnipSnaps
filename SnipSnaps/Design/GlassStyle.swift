import SwiftUI

// Liquid Glass styling helpers. On macOS (deployment target 26 / Tahoe) these use
// the real Liquid Glass APIs; on iOS they fall back to the app's existing
// bordered / material look so the shared iOS build is unchanged.
extension View {
  // Primary call-to-action button.
  @ViewBuilder
  func prominentActionButton() -> some View {
    #if os(macOS)
    buttonStyle(.glassProminent)
    #else
    buttonStyle(.borderedProminent)
    #endif
  }

  // Secondary / neutral button.
  @ViewBuilder
  func secondaryActionButton() -> some View {
    #if os(macOS)
    buttonStyle(.glass)
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
    glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    #else
    background {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(.ultraThinMaterial)
        .overlay {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(AppColor.card.opacity(0.72))
        }
    }
    #endif
  }
}

#if os(macOS)
private struct MacHoverHighlight: ViewModifier {
  @State private var hovering = false

  func body(content: Content) -> some View {
    content
      .scaleEffect(hovering ? 1.012 : 1.0)
      .animation(.easeOut(duration: 0.12), value: hovering)
      .onHover { hovering = $0 }
      .pointerStyle(.link)
  }
}
#endif
