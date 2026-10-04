import SwiftUI

// Liquid Glass styling helpers. On OS 26+ (iOS 26, macOS 26 Tahoe, and later,
// including the refined Glass of iOS/macOS 27) these use the real Liquid Glass
// APIs; on the app's older floors (iOS 18, macOS 15) they fall back to the
// bordered / material look. Every 26+ call is availability-gated.
extension View {
  // Primary call-to-action button.
  @ViewBuilder
  func prominentActionButton() -> some View {
    if #available(iOS 26, macOS 26, *) {
      buttonStyle(.glassProminent)
    } else {
      buttonStyle(.borderedProminent)
    }
  }

  // Secondary / neutral button.
  @ViewBuilder
  func secondaryActionButton() -> some View {
    if #available(iOS 26, macOS 26, *) {
      buttonStyle(.glass)
    } else {
      buttonStyle(.bordered)
    }
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
  // Interactive glass: every current use is a tappable chip (opens the details
  // sheet), so the glass should respond to touch like the other controls.
  @ViewBuilder
  func infoChipBackground(cornerRadius: CGFloat = 14) -> some View {
    if #available(iOS 26, macOS 26, *) {
      glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
    } else {
      materialChipBackground(cornerRadius: cornerRadius)
    }
  }

  // Circular Keep/Trash action button (and the matching swipe badge). On OS 26+
  // a tinted interactive glass disc; below that the flat tinted disc with a
  // hairline edge.
  @ViewBuilder
  func reviewActionCircleBackground(tint: Color, backgroundTint: Color) -> some View {
    if #available(iOS 26, macOS 26, *) {
      glassEffect(.regular.tint(backgroundTint).interactive(), in: .circle)
    } else {
      background(backgroundTint, in: Circle())
        .overlay(
          Circle().strokeBorder(tint.opacity(0.12), lineWidth: 0.5)
        )
    }
  }

  // Circular close button floating over full-bleed content (e.g. the full-screen
  // photo viewer). Glass on OS 26+; a legible dark scrim below that. The glyph
  // keeps a soft shadow on glass so it stays readable over bright photos —
  // matching the OS 27 readability guidance for glass over busy content.
  @ViewBuilder
  func floatingCloseButtonBackground() -> some View {
    if #available(iOS 26, macOS 26, *) {
      glassEffect(.regular.interactive(), in: .circle)
    } else {
      background(Color.black.opacity(0.45), in: Circle())
    }
  }

  // Collapses the iOS tab bar to its compact glass pill while scrolling down,
  // restoring it on scroll up. iOS 26+ only; a no-op everywhere else.
  @ViewBuilder
  func adaptiveTabBarMinimize() -> some View {
    #if os(iOS)
    if #available(iOS 26, *) {
      tabBarMinimizeBehavior(.onScrollDown)
    } else {
      self
    }
    #else
    self
    #endif
  }

  // Pre-Liquid-Glass chip background: a translucent material card.
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

  // iOS press feedback for tappable review cards and thumbnails (Home mode
  // cards, the similar-review filmstrip). The plain style gives zero visual
  // response on touch, so taps feel dead until navigation starts; a subtle
  // shrink (macOS gets the hover lift from interactiveCardHover instead)
  // confirms the touch immediately.
  @ViewBuilder
  func reviewCardButtonStyle() -> some View {
    #if os(iOS)
    buttonStyle(CardPressStyle())
    #else
    buttonStyle(.plain)
    #endif
  }
}

#if os(iOS)
// Pressed scale honors Reduce Motion the same way MacHoverHighlight does: the
// pressed state itself is direct-manipulation feedback and stays, but the
// springy release animation is dropped.
private struct CardPressStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
      .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: configuration.isPressed)
  }
}
#endif

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
