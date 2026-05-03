import Foundation

// 1:1-Übernahme aus Bundle-data.js für die UI-Phase. Sobald MeetingStore (SQLite)
// und RecordingManager das Frontend speisen, fliegt die Datei wieder raus.

enum MockData {

    static let meetings: [MeetingSummary] = [
        // Diesen Monat
        .init(id: "m1", title: "Systempiloten X Schindler — Kickoff",
              date: "10. Apr.", time: "11:00", duration: "47m", platform: .teams,
              wordCount: 5240, group: "Diesen Monat", participantIds: ["ME","SE","MR","JB"]),
        .init(id: "m2", title: "Meeting",
              date: "10. Apr.", time: "10:51", duration: "8m", platform: .call,
              wordCount: 612, group: "Diesen Monat", participantIds: ["ME"]),
        .init(id: "m3", title: "Abstimmung AM Solutions — Q2 Roadmap",
              date: "10. Apr.", time: "10:50", duration: "32m", platform: .zoom,
              wordCount: 3142, group: "Diesen Monat", participantIds: ["ME","SE","TM"], unread: true),
        .init(id: "m4", title: "DEV Sprint StartEnde",
              date: "10. Apr.", time: "10:46", duration: "21m", platform: .meet,
              wordCount: 1980, group: "Diesen Monat", participantIds: ["ME","JB","SE"]),
        .init(id: "m5", title: "Microsoft Teams 10:21",
              date: "10. Apr.", time: "10:46", duration: "14m", platform: .teams,
              wordCount: 1102, group: "Diesen Monat", participantIds: ["ME","MR"]),
        .init(id: "m6", title: "Updates",
              date: "01. Apr.", time: "15:07", duration: "12m", platform: .call,
              wordCount: 920, group: "Diesen Monat", participantIds: ["ME"]),
        .init(id: "m7", title: "Abstimmung AM Solutions — Pricing",
              date: "01. Apr.", time: "13:14", duration: "28m", platform: .zoom,
              wordCount: 2654, group: "Diesen Monat", participantIds: ["ME","SE"]),
        .init(id: "m8", title: "Meeting",
              date: "01. Apr.", time: "12:53", duration: "6m", platform: .call,
              wordCount: 410, group: "Diesen Monat", participantIds: ["ME"]),
        // Früher
        .init(id: "m9", title: "Abstimmung AM Solutions — Discovery",
              date: "26. März", time: "10:06", duration: "41m", platform: .teams,
              wordCount: 4108, group: "Früher", participantIds: ["ME","SE","TM"]),
        .init(id: "m10", title: "Meeting",
              date: "26. März", time: "10:04", duration: "9m", platform: .call,
              wordCount: 728, group: "Früher", participantIds: ["ME"]),
        .init(id: "m11", title: "Abstimmung AM Solutions — Architektur",
              date: "25. März", time: "11:09", duration: "38m", platform: .zoom,
              wordCount: 3580, group: "Früher", participantIds: ["ME","SE","MR"]),
        .init(id: "m12", title: "Meeting",
              date: "25. März", time: "11:08", duration: "7m", platform: .call,
              wordCount: 540, group: "Früher", participantIds: ["ME"]),
        .init(id: "m13", title: "Abstimmung AM Solutions — Followup",
              date: "25. März", time: "09:56", duration: "24m", platform: .teams,
              wordCount: 2210, group: "Früher", participantIds: ["ME","SE"]),
    ]

    static let activeMeeting = MeetingDetail(
        id: "m3",
        title: "Abstimmung AM Solutions — Q2 Roadmap",
        dateLong: "Donnerstag, 10. April",
        timeRange: "10:50 – 11:22",
        duration: "32m 14s",
        platform: .zoom,
        wordCount: 3142,
        participants: [
            .init(id: "ME", name: "Alex Kramer",   role: "Eigene Stimme", colorHex: 0x2EAB73, spoke: "14m 02s"),
            .init(id: "SE", name: "Sarah Ebner",   role: "AM Solutions", colorHex: 0x7C8AFF, spoke: "11m 47s"),
            .init(id: "TM", name: "Thomas Müller", role: "AM Solutions", colorHex: 0xFFB340, spoke: "6m 25s"),
        ],
        tldr: "Die Q2-Roadmap steht: WhisperKit bleibt lokal, der Pricing-Test läuft bis 15. Mai weiter, das NeoBar-Beta-Rollout verschiebt sich auf KW 19. Sarah übernimmt die Architektur-Doku, Thomas klärt das Lizenzmodell mit dem Partner.",
        highlights: [
            .init(label: "Entscheidung", text: "WhisperKit bleibt on-device — kein Cloud-Fallback in Q2.", tone: .brand),
            .init(label: "Risiko",       text: "Lizenzmodell mit AM Solutions noch offen — bis KW 17 klären.", tone: .warning),
            .init(label: "Termin",       text: "NeoBar-Beta-Rollout verschoben auf KW 19.", tone: .info),
        ],
        tasks: [
            .init(id: "t1", who: "SE", task: "Pricing-Test bis 15. Mai weiterlaufen lassen, Auswertung am 16.",  due: "15. Mai", status: .open),
            .init(id: "t2", who: "ME", task: "NeoBar-Beta-Rollout auf KW 19 verschieben, Stakeholder informieren", due: "02. Mai", status: .open),
            .init(id: "t3", who: "SE", task: "WhisperKit-Architektur dokumentieren (Notion + ADR)",                due: "08. Mai", status: .open),
            .init(id: "t4", who: "TM", task: "Lizenzmodell mit AM-Solutions-Partner klären",                       due: "24. Apr.", status: .open),
            .init(id: "t5", who: "ME", task: "Q2-Roadmap im All-Hands vorstellen",                                  due: "30. Apr.", status: .done),
        ],
        chapters: [
            .init(id: "c1", timestamp: "00:00", label: "Begrüßung & Ziel des Termins",         duration: "2m"),
            .init(id: "c2", timestamp: "02:14", label: "Pricing-Test — Status & Verlängerung", duration: "6m"),
            .init(id: "c3", timestamp: "08:42", label: "WhisperKit — On-device-Entscheidung",  duration: "9m"),
            .init(id: "c4", timestamp: "17:30", label: "NeoBar-Beta — Rollout-Plan",           duration: "7m"),
            .init(id: "c5", timestamp: "24:55", label: "Lizenzmodell & Open Items",            duration: "5m"),
            .init(id: "c6", timestamp: "30:10", label: "Nächste Schritte",                     duration: "2m"),
        ],
        transcript: [
            .init(who: "ME", timestamp: "00:14", body: "Gut, dann lass uns starten. Heute geht es um die Q2-Roadmap — ich würde mit dem Pricing-Test anfangen, wenn das passt."),
            .init(who: "SE", timestamp: "00:23", body: "Passt. Der Test läuft seit dem 8. April, Conversion ist 11,2 % über der Kontrollgruppe. Ich würde bis zum 15. Mai weiterlaufen lassen, dann haben wir saubere vier Wochen."),
            .init(who: "ME", timestamp: "00:48", body: "Klingt gut. Auswertung dann am 16.?", highlight: true),
            .init(who: "SE", timestamp: "00:54", body: "Genau. Ich übernehme das."),
            .init(who: "TM", timestamp: "01:02", body: "Eine Sache zum Lizenzmodell — der Partner hat sich noch nicht zurückgemeldet. Ich gehe davon aus, dass wir bis KW 17 Klarheit haben."),
            .init(who: "ME", timestamp: "01:19", body: "Lass uns das als Risiko tracken. Wenn bis KW 17 nichts da ist, eskalieren wir."),
            .init(who: "ME", timestamp: "01:34", body: "Nächster Punkt — WhisperKit. Bleiben wir bei on-device?"),
            .init(who: "SE", timestamp: "01:41", body: "Ja. Cloud-Fallback bringt uns in Q2 zu wenig, der Aufwand frisst zwei Sprints. Lass uns lokal bleiben und im Q3 neu bewerten."),
            .init(who: "ME", timestamp: "02:08", body: "Einverstanden. Damit ist die Architektur klar — Sarah, magst du das in einem ADR festhalten?", highlight: true),
            .init(who: "SE", timestamp: "02:21", body: "Mache ich. Bis 8. Mai im Notion."),
            .init(who: "TM", timestamp: "02:33", body: "Und NeoBar-Beta?"),
            .init(who: "ME", timestamp: "02:38", body: "Schaffen wir nicht in dieser KW — verschieben wir auf KW 19. Ich informiere die Stakeholder."),
        ]
    )

    static let liveSession = LiveSession(
        startedAt: Date(),
        device: "Built-in Mic",
        model: "WhisperKit ANE",
        lines: [
            .init(who: "ME", timestamp: "00:04", body: "Gut, dann starten wir. Zwei Punkte heute — Pricing-Status und das Beta-Rollout."),
            .init(who: "SE", timestamp: "00:12", body: "Pricing läuft sauber, 11 % über Plan. Ich würde verlängern."),
            .init(who: "ME", timestamp: "00:21", body: "Bis Mitte Mai?"),
            .init(who: "SE", timestamp: "00:24", body: "Genau. Vier Wochen Daten, dann saubere Auswertung."),
            .init(who: "TM", timestamp: "00:33", body: "Beim Lizenzmodell warten wir noch auf Rückmeldung vom Partner."),
            .init(who: "ME", timestamp: "00:41", body: "Wir tracken das als Risiko. Sarah, kannst du WhisperKit dokumentieren?"),
            .init(who: "SE", timestamp: "00:49", body: "Ja, ADR im Notion bis Mitte Mai."),
        ]
    )
}
