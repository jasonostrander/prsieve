import SwiftUI

/// Calm, priority-aware color system.
///
/// Uses warmth to encode urgency:
///   - Priority = warmer hue (amber)
///   - Low = cooler hue (slate)
///
/// All backgrounds are low-saturation pastels that work in both
/// light and dark mode without competing for attention.
enum PRTheme {

    // MARK: - Card backgrounds

    static func cardBackground(for category: PRCategory) -> Color {
        switch category {
        case .priority: .priorityBg
        case .low:      .lowBg
        case .noise:    .noiseBg
        }
    }

    // MARK: - Accent color (icons, badges, counts)

    static func accent(for category: PRCategory) -> Color {
        switch category {
        case .priority: .priorityAccent
        case .low:      .lowAccent
        case .noise:    .noiseAccent
        }
    }

    // MARK: - Section header icon

    static func icon(for category: PRCategory) -> String {
        switch category {
        case .priority: "arrow.up.circle.fill"
        case .low:      "minus.circle.fill"
        case .noise:    "speaker.slash.circle.fill"
        }
    }
}

// MARK: - Color definitions

extension Color {
    // Priority — warm amber / soft coral
    static let priorityBg     = Color(light: .init(h: 24,  s: 0.50, b: 0.98),
                                      dark:  .init(h: 24,  s: 0.30, b: 0.22))
    static let priorityAccent = Color(light: .init(h: 24,  s: 0.65, b: 0.75),
                                      dark:  .init(h: 24,  s: 0.55, b: 0.70))

    // Low — cool slate / quiet blue-gray
    static let lowBg     = Color(light: .init(h: 215, s: 0.12, b: 0.96),
                                 dark:  .init(h: 215, s: 0.12, b: 0.19))
    static let lowAccent = Color(light: .init(h: 215, s: 0.25, b: 0.65),
                                 dark:  .init(h: 215, s: 0.20, b: 0.55))

    // Noise — very muted gray, recedes into background
    static let noiseBg     = Color(light: .init(h: 0, s: 0.00, b: 0.94),
                                   dark:  .init(h: 0, s: 0.00, b: 0.16))
    static let noiseAccent = Color(light: .init(h: 0, s: 0.00, b: 0.60),
                                   dark:  .init(h: 0, s: 0.00, b: 0.45))

    // Status pills — high contrast against any card background
    static let pillApprovedText  = Color(light: .init(h: 145, s: 0.70, b: 0.35),
                                         dark:  .init(h: 145, s: 0.55, b: 0.75))
    static let pillApprovedBg    = Color(light: .init(h: 145, s: 0.20, b: 0.92),
                                         dark:  .init(h: 145, s: 0.30, b: 0.25))

    static let pillChangesText   = Color(light: .init(h: 0,   s: 0.65, b: 0.55),
                                         dark:  .init(h: 0,   s: 0.50, b: 0.80))
    static let pillChangesBg     = Color(light: .init(h: 0,   s: 0.18, b: 0.94),
                                         dark:  .init(h: 0,   s: 0.30, b: 0.25))

    static let pillCommentedText = Color(light: .init(h: 35,  s: 0.70, b: 0.50),
                                         dark:  .init(h: 35,  s: 0.50, b: 0.75))
    static let pillCommentedBg   = Color(light: .init(h: 35,  s: 0.18, b: 0.93),
                                         dark:  .init(h: 35,  s: 0.25, b: 0.25))
}

// MARK: - Adaptive color helper

extension Color {
    /// Create a color that adapts between light and dark appearance.
    init(light: HSB, dark: HSB) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(hue: c.h / 360.0, saturation: c.s, brightness: c.b, alpha: 1.0)
        })
    }

    struct HSB {
        let h: CGFloat  // 0–360
        let s: CGFloat  // 0–1
        let b: CGFloat  // 0–1
    }
}
