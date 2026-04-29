import SwiftUI

// SF-Symbol-Mapping. Statt das Bundle-SVG-Set 1:1 zu portieren nutzen wir native
// SF Symbols — sieht auf macOS authentischer aus, skaliert sauber, kostenlos.
// Bundle-Namen → SF-Symbol-Namen.

enum Glyph {

    enum Name: String {
        case mic              = "mic"
        case micFill          = "mic.fill"
        case micSlash         = "mic.slash"
        case waveform         = "waveform"
        case search           = "magnifyingglass"
        case plus             = "plus"
        case sparkles         = "sparkles"
        case flame            = "flame.fill"
        case check            = "checkmark"
        case checkCircle      = "checkmark.circle.fill"
        case circle           = "circle"
        case play             = "play.fill"
        case pause            = "pause.fill"
        case stop             = "stop.fill"
        case rewind           = "backward.fill"
        case forward          = "forward.fill"
        case refresh          = "arrow.triangle.2.circlepath"
        case share            = "square.and.arrow.up"
        case more             = "ellipsis"
        case copy             = "doc.on.doc"
        case export           = "arrow.up.forward.square"
        case link             = "link"
        case tag              = "tag"
        case people           = "person.2.fill"
        case clock            = "clock"
        case tasks            = "checklist"
        case settings         = "gearshape"
        case calendar         = "calendar"
        case archive          = "archivebox"
        case star             = "star.fill"
        case chevDown         = "chevron.down"
        case chevRight        = "chevron.right"
        case chevUp           = "chevron.up"
        case arrowUpRight     = "arrow.up.right"
        case kbdCommand       = "command"
    }
}

struct GlyphView: View {
    let name: Glyph.Name
    var size: CGFloat = 14
    var weight: Font.Weight = .regular
    var color: Color = Neon.textSecondary

    var body: some View {
        Image(systemName: name.rawValue)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
    }
}
