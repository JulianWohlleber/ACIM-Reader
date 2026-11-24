import SwiftUI
import UIKit

// MARK: - Dieter Rams design language
//
// "Weniger, aber besser."
//
// Braun housings were warm off-white; the ET66 calculator was matte near-black.
// Both carry exactly one signal colour — orange — reserved for the thing that is
// happening right now. Everything else is Helvetica on a strict 8pt grid,
// separated by hairlines rather than boxes, shadows or gradients.
//
// In this app the orange marks one thing only: the word being spoken.

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red:   CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >>  8) & 0xFF) / 255,
                  blue:  CGFloat( rgb        & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Color {
    init(rgb: UInt32) { self.init(UIColor(rgb: rgb)) }
}

/// The palette. Two housings, one signal colour.
struct RamsTheme {
    var isDark: Bool

    /// The housing itself.
    var paper:     UIColor { isDark ? UIColor(rgb: 0x1B1B1B) : UIColor(rgb: 0xF4F3F0) }
    /// Recessed areas: the control strip, settings rows.
    var surface:   UIColor { isDark ? UIColor(rgb: 0x242424) : UIColor(rgb: 0xEAE7E1) }
    /// Printed text.
    var ink:       UIColor { isDark ? UIColor(rgb: 0xE9E6E0) : UIColor(rgb: 0x1A1A1A) }
    /// Text that is not being read right now.
    var inkMuted:  UIColor { isDark ? UIColor(rgb: 0x737069) : UIColor(rgb: 0x97938B) }
    /// The sentence that comes next: already leaning in, but not yet speaking.
    /// Sits halfway between `inkMuted` and `ink`, so the eye can find where it
    /// is about to go without being pulled off the line being read.
    var inkNext:   UIColor { isDark ? UIColor(rgb: 0x9A958C) : UIColor(rgb: 0x7A766E) }
    /// Engraved labels on a Braun front panel.
    var label:     UIColor { isDark ? UIColor(rgb: 0x8A8780) : UIColor(rgb: 0x7C7971) }
    /// 0.5pt rules. Never a border, never a shadow.
    var hairline:  UIColor { isDark ? UIColor(rgb: 0x343230) : UIColor(rgb: 0xD6D3CC) }
    /// The one signal colour.
    var accent:    UIColor { isDark ? UIColor(rgb: 0xF2652A) : UIColor(rgb: 0xDE4E0A) }
    /// The marker laid over the words being spoken: the accent at low
    /// strength, a wash you read the black text straight through. At full
    /// strength it stops being a marker and becomes a block of colour — the
    /// text has to be knocked out white to survive it, and the page reads as
    /// if something were selected rather than being read aloud.
    var marker:    UIColor { accent.withAlphaComponent(isDark ? 0.34 : 0.25) }
    /// The faint tint behind the sentence currently being spoken.
    var mark:      UIColor { isDark ? UIColor(rgb: 0x2B2825) : UIColor(rgb: 0xE8E4DA) }

    static func current(_ scheme: ColorScheme) -> RamsTheme {
        RamsTheme(isDark: scheme == .dark)
    }

    // SwiftUI mirrors
    var paperC:    Color { Color(paper) }
    var surfaceC:  Color { Color(surface) }
    var inkC:      Color { Color(ink) }
    var inkMutedC: Color { Color(inkMuted) }
    var inkNextC:  Color { Color(inkNext) }
    var labelC:    Color { Color(label) }
    var hairlineC: Color { Color(hairline) }
    var accentC:   Color { Color(accent) }
    var markC:     Color { Color(mark) }
    var markerC:   Color { Color(marker) }
}

/// Helvetica, as on every Braun front panel.
enum RamsFont {
    static func regular(_ size: CGFloat) -> UIFont {
        UIFont(name: "HelveticaNeue", size: size) ?? .systemFont(ofSize: size)
    }
    static func medium(_ size: CGFloat) -> UIFont {
        UIFont(name: "HelveticaNeue-Medium", size: size) ?? .systemFont(ofSize: size, weight: .medium)
    }
    static func bold(_ size: CGFloat) -> UIFont {
        UIFont(name: "HelveticaNeue-Bold", size: size) ?? .systemFont(ofSize: size, weight: .bold)
    }
}

extension Font {
    static func rams(_ size: CGFloat) -> Font { .custom("HelveticaNeue", size: size) }
    static func ramsMedium(_ size: CGFloat) -> Font { .custom("HelveticaNeue-Medium", size: size) }
    static func ramsBold(_ size: CGFloat) -> Font { .custom("HelveticaNeue-Bold", size: size) }
}

/// The 8pt grid.
enum Grid {
    static let unit: CGFloat = 8
    static func x(_ n: CGFloat) -> CGFloat { unit * n }
    /// Reading measure: generous side margins, as in Vitsœ's printed matter.
    static let margin: CGFloat = 24
}

/// An engraved panel label: small, uppercase, widely tracked.
struct PanelLabel: ViewModifier {
    let theme: RamsTheme
    func body(content: Content) -> some View {
        content
            .font(.ramsMedium(10))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(theme.labelC)
    }
}

extension View {
    func panelLabel(_ theme: RamsTheme) -> some View { modifier(PanelLabel(theme: theme)) }

    /// A 0.5pt rule. Rams separates with a line, not a box.
    func hairline(_ theme: RamsTheme, edge: Edge = .bottom) -> some View {
        overlay(alignment: edge == .bottom ? .bottom : .top) {
            Rectangle()
                .fill(theme.hairlineC)
                .frame(height: 0.5)
        }
    }
}
