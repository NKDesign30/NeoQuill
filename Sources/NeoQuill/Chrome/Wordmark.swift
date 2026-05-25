import SwiftUI

// "Neo" (Space Grotesk Medium, weiß) + "quill" (DM Serif Italic, Forest Emerald).
// Pattern aus Bundle-chrome.jsx — passt zur Familie NeoBar / NeoWispr / NeoQuill.

struct AppIconView: View {
    var size: CGFloat = 28
    var radius: CGFloat? = nil

    var body: some View {
        Group {
            if let url = AppResourceBundle.url(forResource: "quill-app-icon", withExtension: "png"),
               let img = NSImage(contentsOf: url) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: (radius ?? size * 0.224), style: .continuous)
                    .fill(Neon.logoNight2)
                    .overlay(
                        Circle().fill(Neon.brandPrimary)
                            .frame(width: size * 0.36, height: size * 0.36)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius ?? size * 0.224, style: .continuous))
    }
}

struct Wordmark: View {
    var size: CGFloat = 22
    var accent: Color = Neon.brandPrimary

    var body: some View {
        HStack(spacing: 8) {
            AppIconView(size: size + 4)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("Neo")
                    .font(.neonBody(size * 0.8, weight: .medium))
                    .tracking(-0.2)
                    .foregroundStyle(Neon.textPrimary)
                Text("quill")
                    .font(.neonDisplay(size, italic: true))
                    .foregroundStyle(accent)
            }
        }
        .frame(maxHeight: size + 4, alignment: .leading)
    }
}
