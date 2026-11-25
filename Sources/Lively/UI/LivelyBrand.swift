import SwiftUI
import AppKit

enum LivelyBrand {
    // Brand accents — use sparingly (active nav, primary actions, links, toggle on).
    static let primary = adaptive(light: "#007078", dark: "#55CAD0")
    static let primarySoft = adaptive(light: "#43B6BB", dark: "#9FE8EA")
    /// Label on primary fills. Light stays white on #007078.
    /// Dark primary-foreground is brand `oklch(0.100 0 0)`, not white on #55CAD0.
    static let onPrimary = adaptive(light: "#FFFFFF", dark: "#030303")
    static let destructive = Color(nsColor: .systemRed)
    static let onDestructive = Color.white
    static let clearButtonBackground = destructive.opacity(0.85)
    static let overlayBackground = Color(nsColor: .labelColor).opacity(0.55)

    // Semantic neutrals — prefer system colors so light/dark inherit correctly.
    static var background: Color { Color(nsColor: .windowBackgroundColor) }
    static var card: Color { Color(nsColor: .controlBackgroundColor) }
    /// Elevated/control surface fill (not brand accent). Prefer this over inventing greys.
    static var controlFill: Color { Color(nsColor: .controlBackgroundColor) }
    static var foreground: Color { Color(nsColor: .labelColor) }
    static var mutedForeground: Color { Color(nsColor: .secondaryLabelColor) }
    static var border: Color { Color(nsColor: .separatorColor) }

    /// Brand-tint fill for selected sidebar rows only (interactive selection language).
    static var selectionFill: Color { primary.opacity(0.13) }

    enum Spacing {
        static let tiny: CGFloat = 3
        static let xs: CGFloat = 4
        static let xxs: CGFloat = 6
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        /// Minimum interactive control height (Fitts).
        static let controlMin: CGFloat = 32
    }

    /// Shape system: controls/chips use `sm`, cards/tiles use `md`,
    /// panels/sheets use `lg`, nav pills use `navItem`, capsules use `full`.
    enum Radius {
        static let sm: CGFloat = 6
        static let navItem: CGFloat = 8
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let full: CGFloat = 9999
    }

    /// Type hierarchy (largest → smallest):
    /// `nav` (primary tabs) → `title` (display names) → `section` (pane headers)
    /// → `body` → `caption` → `footnote` / `mono`.
    enum Typography {
        /// Top chrome: Displays / Settings tab labels.
        static let nav = Font.headline
        /// Card / pane primary titles (display names).
        static let title = Font.title3.weight(.semibold)
        /// Settings pane section titles, card section labels.
        static let section = Font.body.weight(.semibold)
        static let body = Font.body
        static let caption = Font.callout.weight(.medium)
        static let footnote = Font.footnote
        static let mono = Font.system(.footnote, design: .monospaced, weight: .medium)
        static let badge = Font.caption.weight(.bold)
        static let iconSmall = Font.title3.weight(.medium)
        static let iconControl = Font.headline.weight(.medium)
        static let iconLarge = Font.largeTitle.weight(.light)
    }

    enum Shadow {
        /// Soft neutral ink — not pure black (visual-no-pure-black-shadow).
        static let color = Color(nsColor: .labelColor).opacity(0.12)
        static let radius: CGFloat = 4
        static let x: CGFloat = 0
        static let y: CGFloat = 2
    }

    enum Motion {
        /// Whether system Reduce Motion is active.
        public static var isReduceMotionEnabled: Bool {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }

        /// Motion helper returning nil animation if reduceMotion is active.
        public static func resolved(_ animation: Animation, reduceMotion: Bool? = nil) -> Animation? {
            let shouldReduce = reduceMotion ?? isReduceMotionEnabled
            return shouldReduce ? nil : animation
        }

        /// Press-down feedback: 120–180ms, critically damped.
        static let press      = Animation.spring(duration: 0.15, bounce: 0)
        static let fast       = Animation.spring(duration: 0.2, bounce: 0)
        static let normal     = Animation.spring(duration: 0.3, bounce: 0)
        static let dropTarget = Animation.spring(duration: 0.2, bounce: 0)
    }

    /// Symmetric opacity+offset enter/exit (exit mirrors insertion path).
    static var contentTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 6)),
            removal: .opacity.combined(with: .offset(y: 6))
        )
    }

    private static func adaptive(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&value)

        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255

        self.init(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}
