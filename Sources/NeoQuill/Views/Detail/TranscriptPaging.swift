import Foundation
import SwiftUI

enum TranscriptPaging {
    static let pageSize = 50

    static func visibleCount(total: Int, requested: Int) -> Int {
        guard total > 0 else { return 0 }
        return min(max(requested, pageSize), total)
    }

    static func nextCount(current: Int, total: Int) -> Int {
        min(max(current, pageSize) + pageSize, total)
    }

    static func hasMore(visibleCount: Int, total: Int) -> Bool {
        visibleCount < total
    }

    static func filteredLines(_ lines: [TranscriptLine], query: String) -> [TranscriptLine] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return lines }

        return lines.filter { line in
            line.body.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

struct TranscriptLoadMoreFooter: View {
    let visibleCount: Int
    let totalCount: Int
    let accent: Color
    let loadMore: () -> Void

    var body: some View {
        if TranscriptPaging.hasMore(visibleCount: visibleCount, total: totalCount) {
            Button(action: loadMore) {
                HStack(spacing: 8) {
                    GlyphView(name: .chevDown, size: 11, weight: .semibold, color: accent)
                    Text("\(visibleCount) / \(totalCount)")
                        .font(.neonMono(10, weight: .semibold))
                        .foregroundStyle(Neon.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.035))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
                )
            }
            .buttonStyle(.plain)
            .onAppear(perform: loadMore)
        }
    }
}
