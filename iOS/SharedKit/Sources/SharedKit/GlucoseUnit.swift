import Foundation

/// Glucose display unit. Internal storage always uses mmol/L;
/// this controls presentation and settings input.
public enum GlucoseUnit: String, CaseIterable, Sendable {
    case mmolL
    case mgdL

    private static let factor: Double = 18.018

    public var label: String {
        switch self {
        case .mmolL: return "mmol/L"
        case .mgdL: return "mg/dL"
        }
    }

    /// Abbreviated unit for space-constrained surfaces (circular widgets).
    public var shortLabel: String {
        switch self {
        case .mmolL: return "mm"
        case .mgdL: return "mg"
        }
    }

    /// Convert an internal mmol/L value to the display unit.
    public func displayValue(_ mmol: Double) -> Double {
        switch self {
        case .mmolL: return mmol
        case .mgdL: return mmol * Self.factor
        }
    }

    /// Convert a display-unit value back to mmol/L for storage.
    public func toMmol(_ display: Double) -> Double {
        switch self {
        case .mmolL: return display
        case .mgdL: return display / Self.factor
        }
    }

    /// Format an mmol/L value as a short string in the display unit (no unit label).
    public func formatted(_ mmol: Double) -> String {
        let value = displayValue(mmol)
        switch self {
        case .mmolL: return String(format: "%.1f", value)
        case .mgdL: return String(format: "%.0f", value)
        }
    }

    /// Format an mmol/L value with the unit label appended.
    public func formattedWithUnit(_ mmol: Double) -> String {
        "\(formatted(mmol)) \(label)"
    }
}
