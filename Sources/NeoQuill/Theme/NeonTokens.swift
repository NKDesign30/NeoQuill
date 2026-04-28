import SwiftUI

// Forest Emerald · Warm Dark · Editorial Display
// 1:1-Port aus neon-design/ui_kits/quill/neon/colors_and_type.css.
// Dark-Mode ist NeoQuills Default — Light-Theme bleibt als Variante reserviert.

enum Neon {

    // MARK: - Brand (Forest Emerald — primär für NeoQuill)

    static let brandPrimary = Color(hex: 0x2EAB73)
    static let brandBright  = Color(hex: 0x34C788)
    static let brandFaint   = Color(hex: 0x2EAB73, alpha: 0.10)
    static let brandMuted   = Color(hex: 0x2EAB73, alpha: 0.22)

    // Logo-Tiefen (für Avatare auf Brand-Background)
    static let logoNight1 = Color(hex: 0x0B3A26)
    static let logoNight2 = Color(hex: 0x05201A)

    // MARK: - Neon-Skala

    enum Scale {
        static let n50  = Color(hex: 0xE8F5EE)
        static let n100 = Color(hex: 0xC7E6D5)
        static let n200 = Color(hex: 0x9FD4B6)
        static let n300 = Color(hex: 0x6FBC93)
        static let n400 = Color(hex: 0x3FA678)
        static let n500 = Color(hex: 0x2EAB73)
        static let n600 = Color(hex: 0x1F8E5C)
        static let n700 = Color(hex: 0x177248)
        static let n800 = Color(hex: 0x115638)
        static let n900 = Color(hex: 0x0B3A26)
    }

    // MARK: - Speaker-Akzente (Differenzierung in Avataren / Highlights — KEIN Brand)

    enum Speaker {
        static let blue       = Color(hex: 0x409CFF)
        static let amber      = Color(hex: 0xFFB340)
        static let indigo     = Color(hex: 0x7C8AFF)
        static let terracotta = Color(hex: 0xD4845A)
    }

    // MARK: - Surfaces (warm dark — never #000)

    static let surfaceBackground = Color(hex: 0x1A1A18)
    static let surfaceCard       = Color.white.opacity(0.04)
    static let surfaceSunken     = Color.white.opacity(0.02)
    static let surfaceElevated   = Color.white.opacity(0.06)
    static let surfaceInput      = Color.white.opacity(0.04)
    static let surfaceRowHover   = Color.white.opacity(0.04)

    // Window-Aussenrand (hinter dem App-Frame)
    static let windowBackdrop = Color(hex: 0x0E0E0D)

    // MARK: - Text-Hierarchie

    static let textPrimary    = Color.white.opacity(0.96)
    static let textSecondary  = Color.white.opacity(0.66)
    static let textTertiary   = Color.white.opacity(0.42)
    static let textQuaternary = Color.white.opacity(0.26)
    static let textOnBrand    = Color.white
    static let textLink       = Color(hex: 0x409CFF)

    // MARK: - Status

    static let statusSuccess = Color(hex: 0x2EAB73)
    static let statusWarning = Color(hex: 0xFFB340)
    static let statusError   = Color(hex: 0xFF6259)
    static let statusInfo    = Color(hex: 0x409CFF)

    // Live-Recording-Pulse (rot, nicht emerald — Akzent für aktiven Aufnahme-Zustand)
    static let recordingDot       = Color(hex: 0xFF6259)
    static let recordingDotBright = Color(hex: 0xFF8E87)

    // MARK: - Strokes

    static let strokeHairline = Color.white.opacity(0.08)
    static let strokeDefault  = Color.white.opacity(0.14)
    static let strokeStrong   = Color.white.opacity(0.22)
    static let strokeBrand    = Color(hex: 0x2EAB73, alpha: 0.60)
    static let hairlineWidth: CGFloat = 0.5

    // MARK: - Spacing

    enum Space {
        static let s0:  CGFloat = 0
        static let s1:  CGFloat = 4
        static let s2:  CGFloat = 8
        static let s3:  CGFloat = 12
        static let s4:  CGFloat = 16
        static let s5:  CGFloat = 20
        static let s6:  CGFloat = 24
        static let s8:  CGFloat = 32
        static let s10: CGFloat = 40
        static let s12: CGFloat = 48
        static let s16: CGFloat = 64
        static let s20: CGFloat = 80
    }

    // MARK: - Radius

    enum Radius {
        static let sm:  CGFloat = 4
        static let md:  CGFloat = 6
        static let lg:  CGFloat = 10
        static let xl:  CGFloat = 14
        static let xl2: CGFloat = 18
        static let xl3: CGFloat = 22       // macOS App-Icon Squircle
        static let full: CGFloat = 9999
    }

    // MARK: - Motion

    enum Duration {
        static let instant = 0.10
        static let fast    = 0.15
        static let normal  = 0.22
        static let slow    = 0.32
    }

    enum Easing {
        // var-Out: schnell anziehen, weich auslaufen
        static let out    = Animation.timingCurve(0.2, 0.8, 0.2, 1.0)
        static let inOut  = Animation.timingCurve(0.4, 0.0, 0.2, 1.0)
        static let spring = Animation.timingCurve(0.5, 1.5, 0.6, 1.0)
    }
}

// MARK: - Color Hex Initializer

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8)  & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
