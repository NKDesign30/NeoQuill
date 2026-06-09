import Foundation

/// Eine Stelle, die zwei Entscheidungen aus **einem** Schwellen-Satz trifft:
/// "Ist das Transkript gut genug?" (`accepts`) und "Muss der gemischte Stem als
/// Rettungsversuch transkribiert werden?" (`needsFallback`).
///
/// Vorher lasen drei Module ihre eigenen, auseinanderdriftenden Schwellen:
/// `TranscriptQualityScorer` maß Wiederholung als `repeatRatio` über
/// normalisierte Bodies und "zu wenig Wörter" als `words < max(8, dur/30)`,
/// `MeetingTranscriber.needsMixedFallback` rechnete Wiederholung roh über
/// `Set(lowercased)` und "zu wenig Wörter" als `words < max(4, sec/3)`, und
/// `TranscriptNoiseFilter` hielt eine dritte Wiederholungs-Schwelle.
///
/// Hier ist die Trennung sauber: Der **Scorer misst** (Wörter, repeatRatio,
/// uniqueTextRatio, Status), diese **Policy entscheidet**. Damit gibt es genau
/// eine Messquelle und ein Zuhause für alle Transkript-Qualitäts-Schwellen.
enum TranscriptQualityPolicy {
    /// Das Fallback-Gate ist bewusst aggressiver als das Akzeptanz-Gate: ein
    /// dünner Einzel-Stem soll den gemischten Stem als Rettungsversuch auslösen,
    /// bevor wir das Ergebnis akzeptieren. Akzeptanz selbst bleibt nachsichtig
    /// (Scorer-Status), damit kurze, aber echte Meetings nicht verworfen werden.
    static let fallbackMinWordsFloor = 4
    static let fallbackSecondsPerWord = 3
    static let fallbackMinSecondsForWordCheck = 12

    /// Klein-Skalen-Wiederholung: Der Scorer flaggt Wiederholung erst ab 20
    /// Segmenten, ein Fallback soll aber auch ein "vielen dank"-Loop aus wenigen
    /// Zeilen abfangen. Darum prüft die Policy uniqueTextRatio schon ab 4 Zeilen.
    static let fallbackMinSegmentsForRepeatCheck = 4
    static let fallbackMaxUniqueTextRatio = 0.5

    /// Wie viele direkt aufeinanderfolgende identische Zeilen `TranscriptNoiseFilter`
    /// behält, bevor er trimmt. Lebt hier, damit alle Wiederholungs-Schwellen an
    /// einem Ort stehen — auch wenn das Trimmen eine andere Frage beantwortet als
    /// das Gating.
    static let maxConsecutiveRepeatedBodies = 2

    /// Wie viele direkt aufeinanderfolgende identische Zeilen die kollabierte
    /// Anzeige (`TranscriptPresentation`) zeigt, bevor sie den Rest zu einer
    /// "collapsedRun"-Zeile faltet. Bewusst eine eigene Konstante neben
    /// `maxConsecutiveRepeatedBodies`: Anzeigen-Falten und Summary-Verwerfen sind
    /// zwei getrennte Entscheidungen, die heute denselben Wert teilen, aber
    /// unabhängig bleiben sollen.
    static let visibleRepeatedBodiesPerRun = 2

    /// Akzeptanz-Gate: Übernimmt das Verdikt des Scorers. Eigener Name, damit
    /// Aufrufer eine Entscheidung treffen statt ein Status-Feld zu lesen.
    static func accepts(_ report: TranscriptQualityReport) -> Bool {
        report.status == .passed
    }

    /// Fallback-Gate: rein über die gemessenen Report-Felder ausgedrückt —
    /// keine parallele Roh-Messung mehr.
    static func needsFallback(_ report: TranscriptQualityReport, audioSeconds: Int) -> Bool {
        if report.segmentCount == 0 { return true }
        if audioSeconds >= fallbackMinSecondsForWordCheck,
           report.wordCount < max(fallbackMinWordsFloor, audioSeconds / fallbackSecondsPerWord) {
            return true
        }
        if report.status == .failed { return true }
        if report.segmentCount >= fallbackMinSegmentsForRepeatCheck,
           report.uniqueTextRatio <= fallbackMaxUniqueTextRatio {
            return true
        }
        return false
    }
}
