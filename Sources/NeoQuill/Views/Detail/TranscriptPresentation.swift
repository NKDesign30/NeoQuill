import Foundation

enum TranscriptPresentationMode {
    case collapsedRepeatedRuns
    case raw
}

struct TranscriptDisplayRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case line(TranscriptLine)
        case collapsedRun(firstLine: TranscriptLine, hiddenCount: Int)
    }

    let id: String
    let kind: Kind

    var representedLineCount: Int {
        switch kind {
        case .line:
            return 1
        case .collapsedRun(_, let hiddenCount):
            return hiddenCount
        }
    }

    var searchableText: String {
        switch kind {
        case .line(let line), .collapsedRun(let line, _):
            return line.body
        }
    }
}

enum TranscriptPresentation {
    static let visibleRepeatedBodiesPerRun = 2

    static func rows(
        from lines: [TranscriptLine],
        mode: TranscriptPresentationMode
    ) -> [TranscriptDisplayRow] {
        switch mode {
        case .raw:
            return lines.map { line in
                TranscriptDisplayRow(id: line.id.uuidString, kind: .line(line))
            }
        case .collapsedRepeatedRuns:
            return collapsedRows(from: lines)
        }
    }

    static func filteredRows(
        _ rows: [TranscriptDisplayRow],
        query: String
    ) -> [TranscriptDisplayRow] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return rows }

        return rows.filter { row in
            row.searchableText.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private static func collapsedRows(from lines: [TranscriptLine]) -> [TranscriptDisplayRow] {
        var rows: [TranscriptDisplayRow] = []
        var run: [TranscriptLine] = []
        var previousKey = ""

        func flushRun() {
            guard !run.isEmpty else { return }

            if run.count <= visibleRepeatedBodiesPerRun {
                rows.append(contentsOf: run.map { line in
                    TranscriptDisplayRow(id: line.id.uuidString, kind: .line(line))
                })
            } else {
                rows.append(contentsOf: run.prefix(visibleRepeatedBodiesPerRun).map { line in
                    TranscriptDisplayRow(id: line.id.uuidString, kind: .line(line))
                })

                let firstHidden = run[visibleRepeatedBodiesPerRun]
                let lastHidden = run[run.count - 1]
                rows.append(
                    TranscriptDisplayRow(
                        id: "collapsed-\(firstHidden.id.uuidString)-\(lastHidden.id.uuidString)-\(run.count)",
                        kind: .collapsedRun(
                            firstLine: firstHidden,
                            hiddenCount: run.count - visibleRepeatedBodiesPerRun
                        )
                    )
                )
            }

            run.removeAll(keepingCapacity: true)
        }

        for line in lines {
            let key = normalizedBody(line.body)
            guard !key.isEmpty else { continue }

            if key != previousKey {
                flushRun()
                previousKey = key
            }
            run.append(line)
        }

        flushRun()
        return rows
    }

    private static func normalizedBody(_ body: String) -> String {
        body
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
