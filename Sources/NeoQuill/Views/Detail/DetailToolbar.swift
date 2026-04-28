import SwiftUI

// 44h Toolbar oben über dem Detail-Content. Links Title (klein, secondary,
// truncated), rechts Copy/Export/Share + More.

struct DetailToolbar: View {
    let title: String
    var onCopy:   () -> Void = {}
    var onExport: () -> Void = {}
    var onShare:  () -> Void = {}
    var onMore:   () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.neonBody(12, weight: .medium))
                .foregroundStyle(Neon.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 320, alignment: .leading)

            Spacer(minLength: 8)

            ToolbarButton(icon: .copy,   label: "Kopieren", action: onCopy)
            ToolbarButton(icon: .export, label: "Export",   action: onExport)
            ToolbarButton(icon: .share,  label: "Teilen",   action: onShare)

            Rectangle()
                .fill(Neon.strokeHairline)
                .frame(width: 1, height: 18)
                .padding(.horizontal, 4)

            ToolbarButton(icon: .more, action: onMore)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Neon.strokeHairline).frame(height: Neon.hairlineWidth)
        }
    }
}
