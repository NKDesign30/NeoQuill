import SwiftUI

// Editorial-Hierarchie: Mono Eyebrow → Display Headline → Body.
// Familien-Mapping aus Bundle-CSS: display = DM Serif Display, body = Space Grotesk,
// alt = Inter (Reading-Längen), mono = Geist Mono (Meta/Code).

extension Font {

    enum NeonFamily: String {
        case displayRegular = "DMSerifDisplay-Regular"
        case displayItalic  = "DMSerifDisplay-Italic"
        case body           = "SpaceGrotesk"
        case alt            = "Inter"
        case mono           = "GeistMono"
    }

    // MARK: - Display (DM Serif)

    static func neonDisplay(_ size: CGFloat, italic: Bool = false) -> Font {
        let family: NeonFamily = italic ? .displayItalic : .displayRegular
        return .custom(family.rawValue, size: size)
    }

    static var neonDisplayHeroXL:   Font { neonDisplay(96) }
    static var neonDisplayHero:     Font { neonDisplay(72) }
    static var neonDisplayStat:     Font { neonDisplay(44) }
    static var neonDisplayWindow:   Font { neonDisplay(32) }
    static var neonDisplaySection:  Font { neonDisplay(24) }
    static var neonDisplayHeader40: Font { neonDisplay(40) }   // Detail-Hero
    static var neonDisplayCard22:   Font { neonDisplay(22) }   // Stat-Werte
    static var neonDisplayTab:      Font { neonDisplay(28) }

    // MARK: - Body (Space Grotesk)

    static func neonBody(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(NeonFamily.body.rawValue, size: size).weight(weight)
    }

    static var neonBodyXL:     Font { neonBody(18) }
    static var neonBody15:     Font { neonBody(15) }
    static var neonBody:       Font { neonBody(14) }
    static var neonBodySm:     Font { neonBody(12) }
    static var neonBodyButton: Font { neonBody(13, weight: .medium) }
    static var neonBodyLabel:  Font { neonBody(12, weight: .medium) }

    // MARK: - Alt (Inter — TLDR-Lesblock)

    static func neonAlt(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(NeonFamily.alt.rawValue, size: size).weight(weight)
    }

    static var neonAltLead: Font { neonAlt(18) }   // TLDR-Body

    // MARK: - Mono (Geist Mono — Eyebrows/Time/Meta)

    static func neonMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(NeonFamily.mono.rawValue, size: size).weight(weight)
    }

    static var neonEyebrow:   Font { neonMono(11, weight: .medium) }
    static var neonEyebrowSm: Font { neonMono(10, weight: .medium) }
    static var neonMonoMeta:  Font { neonMono(11) }
    static var neonMonoTime:  Font { neonMono(11) }
    static var neonMonoCode:  Font { neonMono(13) }
    static var neonMonoStat:  Font { neonMono(17, weight: .medium) }
    static var neonMonoTimer: Font { neonMono(44) }    // Live-Recording Timer
    static var neonMonoRec:   Font { neonMono(12, weight: .medium) }
}

// MARK: - Eyebrow Modifier (Mono · Uppercase · Tracked)

struct NeonEyebrowStyle: ViewModifier {
    var color: Color
    func body(content: Content) -> some View {
        content
            .font(.neonEyebrow)
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

extension View {
    func neonEyebrow(_ color: Color = Neon.textTertiary) -> some View {
        modifier(NeonEyebrowStyle(color: color))
    }
}

// MARK: - Hairline Border

struct NeonHairlineBorderStyle: ViewModifier {
    var radius: CGFloat
    var color: Color
    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(color, lineWidth: Neon.hairlineWidth)
        )
    }
}

extension View {
    func neonHairline(radius: CGFloat = Neon.Radius.xl, color: Color = Neon.strokeHairline) -> some View {
        modifier(NeonHairlineBorderStyle(radius: radius, color: color))
    }
}
