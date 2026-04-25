import Foundation

#if canImport(SwiftUI)
import SwiftUI
#endif

#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// Brand tints paired with `AttentionLevel`. Defined in one place so the
/// shield extension, main app, widgets, watch app and watch complications
/// all paint the exact same shades — and so a tweak to the brand palette
/// only changes numbers here.
///
/// The four brand colours map to the four `AppIcon-*` variants:
///
/// | Hex       | Role                          | Surfaces                                    |
/// |-----------|-------------------------------|---------------------------------------------|
/// | `#34A853` | Green — "all clear"           | `AppIcon-Green`, shield / widget / complication background for `.clear` |
/// | `#F5A623` | Orange — "needs attention"    | `AppIcon-Orange`, same surfaces for `.attention` |
/// | `#D93025` | Red — "critical high"         | `AppIcon-Red`, same surfaces for `.critical` — paired with the no-disarm subtitle |
/// | `#4285F4` | Blue — "welcome / no source"  | `AppIcon-Blue`, HomeView welcome panel — not an `AttentionLevel` case |
///
/// These are flat hex values — they do **not** adapt between light and
/// dark mode the way SwiftUI's `.red` / `.green` / `.blue` do. That's
/// deliberate: the icon artwork is a single fixed shade, and the tint
/// needs to read as the same colour as the icon regardless of background.
/// If a surface needs a darker or lighter variant (e.g. a pressed state),
/// derive it from `BrandTint.*` rather than introducing a parallel palette.
///
/// **Don't** inline hex literals in UI code — add a constant here and
/// reference it. Grep for `Color\.(red|green|orange|blue)` and
/// `\.system(Red|Green|Orange|Blue)` to find drift.
public enum BrandTint {
    // MARK: Red #D93025 — critical glucose
    fileprivate static let redR: Double = 217 / 255
    fileprivate static let redG: Double = 48 / 255
    fileprivate static let redB: Double = 37 / 255

    // MARK: Orange #F5A623 — needs attention
    fileprivate static let orangeR: Double = 245 / 255
    fileprivate static let orangeG: Double = 166 / 255
    fileprivate static let orangeB: Double = 35 / 255

    // MARK: Green #34A853 — all clear
    fileprivate static let greenR: Double = 52 / 255
    fileprivate static let greenG: Double = 168 / 255
    fileprivate static let greenB: Double = 83 / 255

    // MARK: Blue #4285F4 — welcome / no data source yet
    fileprivate static let blueR: Double = 66 / 255
    fileprivate static let blueG: Double = 133 / 255
    fileprivate static let blueB: Double = 244 / 255

    #if canImport(SwiftUI)
    public static let red = Color(red: redR, green: redG, blue: redB)
    public static let orange = Color(red: orangeR, green: orangeG, blue: orangeB)
    public static let green = Color(red: greenR, green: greenG, blue: greenB)
    public static let blue = Color(red: blueR, green: blueG, blue: blueB)
    #endif

    #if canImport(UIKit) && !os(watchOS)
    public static let uiRed = UIColor(red: CGFloat(redR), green: CGFloat(redG), blue: CGFloat(redB), alpha: 1)
    public static let uiOrange = UIColor(red: CGFloat(orangeR), green: CGFloat(orangeG), blue: CGFloat(orangeB), alpha: 1)
    public static let uiGreen = UIColor(red: CGFloat(greenR), green: CGFloat(greenG), blue: CGFloat(greenB), alpha: 1)
    public static let uiBlue = UIColor(red: CGFloat(blueR), green: CGFloat(blueG), blue: CGFloat(blueB), alpha: 1)
    #endif
}

#if canImport(SwiftUI)
public extension AttentionLevel {
    /// SwiftUI tint matching the `AppIcon-*` variant for this level. Used
    /// by the home-screen icon background, widget container backgrounds,
    /// watch app, and watch complications. Prefer this over
    /// `switch level { ... }` ladders in call sites.
    var tint: Color {
        switch self {
        case .clear: return BrandTint.green
        case .attention: return BrandTint.orange
        case .critical: return BrandTint.red
        }
    }
}
#endif

#if canImport(UIKit) && !os(watchOS)
public extension AttentionLevel {
    /// UIKit tint — same mapping as `tint`, for call sites that need a
    /// `UIColor` (e.g. `ShieldConfiguration.backgroundColor`). iOS-only
    /// by convention, not by necessity: watchOS surfaces use SwiftUI
    /// `.tint` directly and never need the UIKit variant. If a watch
    /// use-case ever needs `UIColor`, drop the `!os(watchOS)` gate —
    /// `BrandTint.ui*` is pure RGB and has no system-colour dependency.
    var uiTint: UIColor {
        switch self {
        case .clear: return BrandTint.uiGreen
        case .attention: return BrandTint.uiOrange
        case .critical: return BrandTint.uiRed
        }
    }
}
#endif
