import Foundation
import Combine
import AVFoundation

// Orchestrator für eine Live-Aufnahme:
// - PermissionGate prüft Mic/Audio.
// - AudioCapture puffert dual-stream Audio (Mic + System-Audio via ProcessTap).
// - Post-Recording-Architektur: Whisper läuft beim Stop einmal pro Stem über
//   das volle Float-Array statt live chunk-weise — keine RMS-Drops bei leisem
//   Mic-Pegel, mehr Kontext für Whisper.
// - SpeakerDiarizer (FluidAudio) labelt Speaker auf dem System-Audio-Stream.
// - Auf Stop: finales Transcript wird in MeetingStore persistiert.

@MainActor
final class RecordingController: ObservableObject {

    // MARK: - Published state für UI

    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var statusText: String = "Bereit"
    @Published private(set) var hasMicPermission: Bool = false
    /// Live-Audio-Level (RMS, 0..~1) — UI-Header/Pille zeigt Live-Bars.
    @Published private(set) var audioLevel: Float = 0

    // MARK: - Dependencies

    private let audioCapture = AudioCapture()
    private let captionCapture = CaptionCaptureService()
    /// Single Whisper-Instance fuer Post-Recording. Mic- und Sys-Stem laufen
    /// sequenziell durch. Ein Modell = halbe RAM-Last + kein ANE-Konflikt.
    private let transcriber = WhisperKitTranscriber()
    /// Multi-Stem-STT-Orchestrierung (Stems rein, Zeilen raus) — ausgelagert
    /// aus diesem Controller in ein eigenes Modul mit klarem Interface.
    private lazy var meetingTranscriber = MeetingTranscriber(whisperKitFallback: transcriber)
    private let permissions = PermissionGate()
    let diarizer = SpeakerDiarizer()
    let detector = MeetingDetector()
    weak var store: MeetingStore?
    weak var speakerStore: SpeakerStore?

    /// Lizenz-Gate für AI-Summaries. Wird vom AppState gesetzt. Default `true`
    /// damit Tests + Builds ohne LicenseService weiterhin funktionieren.
    var licenseAllowsSummary: () -> Bool = { true }
    /// Lizenz-Gate für Cross-Meeting-Speaker-Backfill. Lokales Labeln bleibt frei.
    var licenseAllowsCrossMeetingSpeakerID: () -> Bool = { true }

    private var detectorCancellable: AnyCancellable?
    private var levelCancellable: AnyCancellable?
    private var autoDetectActive = false

    private var elapsedTimer: AnyCancellable?
    private var startedAt: Date?
    /// Plattform der laufenden Aufnahme — beim `start()` eingefroren, damit die
    /// Persist-Pipeline nie den Detector zur Persist-Zeit liest (der beim
    /// Call-Ende bereits auf `.unknown` resettet ist).
    private var sessionPlatform: Platform = .call

    // MARK: - Lifecycle

    init() {
        wireAudioCapture()
        refreshPermissions()
        applyAutoDetectSetting()
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyAutoDetectSetting() }
        }
    }

    /// Schaltet MeetingDetector live ein/aus, wenn Settings-Toggle wechselt.
    /// Detector bleibt waehrend Recording AKTIV — Auto-Stop bei Aufgelegt
    /// soll funktionieren. Self-Trigger wird durch State-Check verhindert.
    func applyAutoDetectSetting() {
        let wantOn = UserDefaults.standard.boolOr(AppSettings.autoDetectMeetings, default: false)
        if wantOn && !autoDetectActive {
            detector.startMonitoring()
            autoDetectActive = true
            detectorCancellable = detector.$isInMeeting
                .removeDuplicates()
                .sink { [weak self] inMeeting in
                    Task { @MainActor in
                        guard let self else { return }
                        self.handleDetectorChange(inMeeting: inMeeting)
                    }
                }
        } else if !wantOn && autoDetectActive {
            detector.stopMonitoring()
            detectorCancellable?.cancel()
            detectorCancellable = nil
            autoDetectActive = false
        }
    }

    /// Reagiert auf Detector-State-Aenderungen.
    /// - inMeeting=true + idle → Pille zeigen, User entscheidet
    /// - inMeeting=true + bereits recording → ignorieren
    /// - inMeeting=false + recording → automatisch stoppen
    /// - inMeeting=false + detected (User hat noch nicht entschieden) → Pille weg
    private func handleDetectorChange(inMeeting: Bool) {
        if inMeeting {
            if case .idle = state {
                let app = detector.detectedApp
                state = .detected(app: app)
                statusText = "Meeting erkannt: \(app.rawValue)"
            }
        } else {
            if state.isRecording {
                Task { await self.stop() }
            } else if case .detected = state {
                state = .idle
                statusText = "Bereit"
            }
        }
    }

    /// User hat in der Pille auf "Aufnehmen" geklickt — Recording starten.
    func acceptDetection() async {
        guard case .detected = state else { return }
        await start()
    }

    /// Laedt Whisper- und Diarizer-Modelle im Hintergrund nach App-Start —
    /// dadurch ist die erste Aufnahme nahezu sofort startbereit, statt erst
    /// bei `start()` Sekunden auf den Modell-Download/Decode zu warten.
    func prewarmModels() async {
        if !FinalSTTTranscriber.isAvailable {
            let model = UserDefaults.standard.stringOr(AppSettings.whisperModel, default: "openai_whisper-small")
            let lang  = UserDefaults.standard.stringOr(AppSettings.language, default: "auto")
            _ = await transcriber.loadModel(model: model, language: lang)
        }

        if UserDefaults.standard.boolOr(AppSettings.speakerDiarization, default: false) {
            await diarizer.warmUp()
        }
    }

    /// User hat in der Pille auf "Ablehnen" geklickt — Detection fuer
    /// diesen Call ignorieren bis er endet und ein neuer beginnt.
    func dismissDetection() {
        guard case .detected = state else { return }
        state = .idle
        statusText = "Ignoriert — wartet auf neues Meeting"
    }

    func refreshPermissions() {
        permissions.refreshAll()
        hasMicPermission = permissions.canRecord
    }

    private func requestMicrophone() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        permissions.refreshMicrophone()
        hasMicPermission = granted
    }

    // MARK: - Public API

    func toggle() async {
        switch state {
        case .idle, .error:
            await start()
        case .recording:
            await stop()
        default:
            break
        }
    }

    func start() async {
        guard !state.isActive else { return }
        state = .preparing
        statusText = "Vorbereiten"

        refreshPermissions()
        if !hasMicPermission {
            await requestMicrophone()
            guard hasMicPermission else {
                state = .error(message: "Mikrofon-Zugriff fehlt — bitte in Systemeinstellungen erlauben.")
                statusText = "Permission fehlt"
                return
            }
        }

        // Modell + Sprache aus Settings, sonst Defaults.
        let model = UserDefaults.standard.stringOr(AppSettings.whisperModel, default: "openai_whisper-small")
        let lang  = UserDefaults.standard.stringOr(AppSettings.language,     default: "auto")
        if !FinalSTTTranscriber.isAvailable {
            let loaded = await transcriber.loadModel(model: model, language: lang)
            guard loaded else {
                state = .error(message: "WhisperKit-Modell konnte nicht geladen werden.")
                statusText = "Fehler"
                return
            }
        }

        // Diarization warm-up nur wenn aktiviert (lädt ~140 MB beim ersten Mal).
        // Bekannte Sprecher werden gleich als Bias mitgegeben — Re-Identification.
        if UserDefaults.standard.boolOr(AppSettings.speakerDiarization, default: false) {
            await diarizer.warmUp()
            if let known = speakerStore?.fluidAudioSpeakers(), !known.isEmpty {
                await diarizer.loadKnownSpeakers(known)
            }
        }

        do {
            audioCapture.clearRecording()
            // Embedding-Cache der VORHERIGEN Aufnahme leeren — er ist nur ein
            // Fallback fürs Labeling-Sheet. Eine noch laufende Pipeline von
            // Aufnahme #1 darf ihn danach wieder füllen: zu dem Zeitpunkt sind
            // ihre Embeddings bereits meeting-bezogen im SpeakerStore
            // persistiert, und der Coordinator löst meeting-bezogen ZUERST auf
            // — der Cache kann ein älteres Meeting nie mehr übersteuern.
            lastEmbeddings.removeAll()
            // Bei Auto-Detect liefert der Detector bereits die App, sonst
            // probieren wir einmal `detectOnce`. Die App wird HIER eingefroren
            // (BundleIds für den Tap + Plattform für die Persistierung) — der
            // Detector resettet sie beim Call-Ende, bevor der Auto-Stop läuft.
            if detector.detectedApp == .unknown {
                detector.detectOnce()
            }
            sessionPlatform = Self.mappedPlatform(from: detector.detectedApp)
            try await audioCapture.start(bundleIds: detector.detectedApp.bundleIdentifiers)
            startedAt = Date()
            state = .recording(startedAt: startedAt!)
            statusText = "Aufnahme läuft"
            startElapsedTimer()
            startCaptionCapture(startedAt: startedAt!, app: detector.detectedApp)
            // Detector laeuft WEITER waehrend Recording — Auto-Stop bei
            // aufgelegtem Call braucht den. Self-Trigger wird durch
            // `handleDetectorChange` via State-Check verhindert.
        } catch {
            state = .error(message: "Audio-Capture fehlgeschlagen: \(error.localizedDescription)")
            statusText = "Fehler"
        }
    }

    func stop() async {
        guard state.isRecording else { return }
        state = .processing
        statusText = "Verarbeiten"
        stopElapsedTimer()
        await audioCapture.stop()

        // Die Aufnahme als WERT einsammeln — die Pipeline greift danach nie
        // wieder in audioCapture/captionCapture/detector zurück. Ein nächstes
        // `start()` kann die Buffer gefahrlos leeren.
        let audio = audioCapture.collectFinalAudio()
        let audioHQ = audioCapture.collectFinalAudioHQ()
        let session = CapturedSession(
            mic: audio.mic,
            sys: audio.sys,
            mixed: audio.mixed,
            micHQ: audioHQ.micHQ,
            sysHQ: audioHQ.sysHQ,
            captionEvents: captionCapture.stop(),
            startedAt: startedAt ?? Date(),
            runtime: elapsed,
            platform: sessionPlatform
        )

        // UI sofort entlasten: Provisional-Detail einsetzen + State auf idle,
        // sodass die Detail-View mit "Wird transkribiert…" angezeigt wird.
        // Whisper + Claude laufen im Hintergrund und updaten das Detail wenn fertig.
        let meetingId = MeetingID.recording(at: session.startedAt)
        insertProvisionalMeeting(
            id: meetingId,
            runtime: session.runtime,
            started: session.startedAt,
            platform: session.platform
        )

        state = .idle
        statusText = "Bereit"
        // Detector wurde nicht pausiert — kein Resume nötig. Self-Trigger
        // verhindert via State-Check in `handleDetectorChange`.

        // Heavy Lifting im Hintergrund — Whisper auf Stems, FluidAudio-Diarize,
        // Claude-Summary. Updated das Provisional-Detail Schritt für Schritt.
        Task { [weak self] in
            await self?.persistMeeting(meetingId: meetingId, session: session)
        }
    }

    func reprocessMeeting(_ meetingId: String) {
        Task { [weak self] in
            await self?.reprocessMeetingAsync(meetingId)
        }
    }

    /// Re-runs final STT for meetings left stuck in `processing` with no
    /// transcript — i.e. the app was quit or crashed mid-transcription, so the
    /// whisper subprocess died and the meeting would otherwise show
    /// "Wird transkribiert…" forever. Runs at app start. Sequential on purpose so
    /// we never spawn several whisper-cli processes at once. The reprocess path
    /// always clears `processing`, so even a meeting whose audio is gone gets
    /// unstuck rather than hanging again.
    func recoverOrphanedTranscripts() {
        guard let store else { return }
        let orphans = store.meetingsNeedingRecovery()
        guard !orphans.isEmpty else { return }
        Task { [weak self] in
            guard let self, let store = self.store else { return }
            for id in orphans {
                let attempts = store.bumpTranscribeAttempts(for: id)
                switch TranscriptionRecoveryPolicy.decision(forAttempt: attempts) {
                case .markFailed(let lifecycle):
                    if var detail = store.detail(for: id) {
                        detail.lifecycle = lifecycle
                        store.updateDetail(detail)
                    }
                    continue
                case .retry:
                    break
                }
                // Clear the stuck busy state first — reprocessMeetingAsync bails out
                // on `!detail.processing`, which is exactly the state an orphaned
                // meeting is in. Without this the re-run is a no-op.
                if var detail = store.detail(for: id) {
                    detail.lifecycle = .done
                    store.updateDetail(detail)
                }
                await self.reprocessMeetingAsync(id)
                // Erfolg (Transkript vorhanden) → Versuchszähler zurücksetzen.
                if let finished = store.detail(for: id), !finished.transcript.isEmpty {
                    store.resetTranscribeAttempts(for: id)
                }
            }
        }
    }

    /// Importiert eine externe Audiodatei (iPhone-Sprachmemo, Diktiergerät,
    /// beliebige .m4a/.mp3/.wav/.caf) als eigenständige Aufnahme: dekodieren,
    /// als Mic-Stem persistieren und durch die normale Final-STT- plus
    /// Summary-Pipeline schicken. Mono-Solo-Audio → keine Diarization,
    /// keine Captions. Gibt bei Fehlern eine deutsche Meldung zurück (nil = ok).
    @discardableResult
    func importAudioFile(url: URL) async -> String? {
        guard store != nil else { return "Kein Meeting-Speicher verfügbar." }

        let fileName = url.deletingPathExtension().lastPathComponent
        statusText = "Audio wird gelesen"

        let samples: [Float]
        do {
            samples = try await AudioIngestService.decode(url: url)
        } catch {
            statusText = "Bereit"
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            NSLog("[RecordingController] Audio-Import fehlgeschlagen: \(message)")
            return message
        }

        let started = Date()
        let runtime = TimeInterval(samples.count) / AudioImporter.targetSampleRate
        let meetingId = MeetingID.imported(at: started)

        // Mic- + Mix-Stem schreiben: Mic füttert die Transkription, Mix dient
        // dem späteren Playback im Detail-View.
        do {
            _ = try AudioWriter.persist(id: meetingId, stem: .mic, samples: samples)
            _ = try AudioWriter.persist(id: meetingId, stem: .mix, samples: samples)
        } catch {
            statusText = "Bereit"
            NSLog("[RecordingController] Import-Stem persist failed: \(error)")
            return "Audio konnte nicht gespeichert werden: \(error.localizedDescription)"
        }

        insertProvisionalMeeting(id: meetingId, runtime: runtime, started: started, title: fileName, platform: .call)
        await persistImportedMeeting(
            meetingId: meetingId,
            samples: samples,
            started: started,
            runtime: runtime,
            fileName: fileName
        )
        return nil
    }

    /// Setzt direkt nach Stop ein Provisional-Meeting in den Store, damit
    /// AppState in Detail-View wechselt waehrend die echte Transkription laeuft.
    private func insertProvisionalMeeting(
        id: String,
        runtime: TimeInterval,
        started: Date,
        title: String? = nil,
        platform: Platform
    ) {
        guard let store else { return }
        let timeline = MeetingTimeline(started: started, runtime: runtime)
        let durationShort = timeline.durationShort
        let timeShort = timeline.timeShort
        let dateShort = timeline.dateShort
        let dateLong = timeline.dateLong
        let timeRange = timeline.timeRange
        let provisionalTitle = title ?? "Aufnahme \(timeShort)"
        let participants: [Participant] = [LocalSpeakerProfile.participant(spoke: durationShort)]

        let summary = MeetingSummary(
            id: id, title: provisionalTitle, date: dateShort, time: timeShort,
            duration: durationShort, platform: platform, wordCount: 0,
            group: "Diesen Monat", participantIds: [LocalSpeakerProfile.id], unread: true
        )
        let provisional = MeetingDetail(
            id: id, title: provisionalTitle, dateLong: dateLong, timeRange: timeRange,
            duration: durationShort, platform: platform, wordCount: 0,
            participants: participants,
            tldr: "Wird transkribiert…",
            highlights: [], tasks: [], chapters: [],
            transcript: [], audioURL: nil, lifecycle: .transcribing
        )
        store.insert(summary: summary, detail: provisional)
    }

    private func persistMeeting(meetingId: String, session: CapturedSession) async {
        guard let store else { return }
        let id = meetingId
        let timeline = MeetingTimeline(started: session.startedAt, runtime: session.runtime)
        let durationShort = timeline.durationShort
        let dateLong = timeline.dateLong
        let timeRange = timeline.timeRange
        let captionEvents = session.captionEvents

        let audioURL = persistCapturedAudio(meetingId: id, session: session)

        let lang = UserDefaults.standard.stringOr(AppSettings.language, default: "auto")
        statusText = FinalSTTTranscriber.isAvailable ? "Final-STT läuft" : "Transkribiere"

        var allLines = await meetingTranscriber.transcribe(
            meetingId: id,
            mic: session.mic,
            system: session.sys,
            mixed: session.mixed,
            language: lang
        )
        var participants: [Participant] = [LocalSpeakerProfile.participant(spoke: durationShort)]

        var pendingEmbeddings: [String: [Float]] = [:]
        var diarizationSegments: [DiarizedSpeakerSegment] = []
        // FluidAudio-Diarize auf System-Audio (>= 5s) — labelt S1 ggf. um in S2/S3
        // bzw. matcht gegen bekannte Speaker (Re-ID via SpeakerStore).
        if UserDefaults.standard.boolOr(AppSettings.speakerDiarization, default: false), diarizer.isReady {
            if session.sys.count > 16_000 * 5 {
                statusText = "Erkenne Sprecher"
                diarizationSegments = await runDiarization(samples: session.sys)
                for entry in diarizationSegments {
                    if pendingEmbeddings[entry.speakerId] == nil {
                        pendingEmbeddings[entry.speakerId] = entry.embedding
                    }
                }
                persistMeetingEmbeddings(meetingId: id, embeddings: pendingEmbeddings)
            }
        }
        if !captionEvents.isEmpty || !diarizationSegments.isEmpty {
            allLines = mergeSpeakers(lines: allLines, captionEvents: captionEvents, diarization: diarizationSegments)
            persistCaptionIdentities(from: allLines, platform: session.platform)
            participants = collectParticipants(
                lines: allLines,
                baseDuration: durationShort,
                diarizationSegments: diarizationSegments
            )
        }

        let summaryLines = TranscriptNoiseFilter.filtered(allLines)
        let wordCount = TranscriptNoiseFilter.wordCount(allLines)
        let provisionalTitle = generateTitle(from: summaryLines.isEmpty ? allLines : summaryLines, started: session.startedAt)

        // Detail mit echten Lines updaten (Provisional ist schon eingefuegt).
        let transcribed = MeetingDetail(
            id: id,
            title: provisionalTitle,
            dateLong: dateLong,
            timeRange: timeRange,
            duration: durationShort,
            platform: session.platform,
            wordCount: wordCount,
            participants: participants,
            tldr: "KI-Zusammenfassung läuft…",
            highlights: [],
            tasks: [],
            chapters: [],
            transcript: allLines,
            audioURL: nil,
            lifecycle: .summarizing
        )
        store.updateDetail(transcribed)
        statusText = "KI verarbeitet"

        // Embeddings frisch entdeckter Speaker für später vorhalten — UI-Labeling-Sheet
        // greift darauf zu, wenn der User "S1 = Thorsten" tippt.
        for (speakerId, embedding) in pendingEmbeddings where !embedding.isEmpty {
            self.lastEmbeddings[speakerId] = embedding
        }

        // 2. Async: WAV speichern + Claude-Summary holen, dann Detail updaten.
        let summary = await MeetingSummarizer.summarize(
            meetingId: id,
            transcriptLines: summaryLines.isEmpty ? allLines : summaryLines,
            locale: lang,
            licenseAllowsSummary: { [weak self] in self?.licenseAllowsSummary() ?? true }
        )

        let finalAudioPath = audioURL?.path
        let shouldDeleteAudio = UserDefaults.standard.boolOr(AppSettings.deleteAudioAfterTranscription, default: false)
        let finalDetail = MeetingDetail(
            id: id,
            title: summary.title.isEmpty ? provisionalTitle : summary.title,
            dateLong: dateLong,
            timeRange: timeRange,
            duration: durationShort,
            platform: session.platform,
            wordCount: wordCount,
            participants: participants,
            tldr: summary.tldr,
            highlights: summary.highlights,
            tasks: summary.tasks,
            chapters: summary.chapters,
            transcript: allLines,
            audioURL: shouldDeleteAudio ? nil : finalAudioPath,
            lifecycle: .done
        )

        store.updateDetail(finalDetail)
        if shouldDeleteAudio {
            _ = try? PrivacyDataService.deleteAudioFiles(for: id)
        }
    }

    /// Pipeline für eine importierte Audiodatei: Final-STT auf dem Mic-Stem,
    /// dann Claude-Summary. Bewusst ohne Diarization/Captions — eine externe
    /// Datei hat keinen separaten System-Audio-Stream und keine Plattform-
    /// Captions. Updated das bereits eingefügte Provisional-Detail in Stufen.
    private func persistImportedMeeting(
        meetingId: String,
        samples: [Float],
        started: Date,
        runtime: TimeInterval,
        fileName: String
    ) async {
        guard let store else { return }
        let timeline = MeetingTimeline(started: started, runtime: runtime)
        let durationShort = timeline.durationShort
        let dateLong = timeline.dateLong
        let timeRange = timeline.timeRange
        let lang = UserDefaults.standard.stringOr(AppSettings.language, default: "auto")
        let audioPath = AudioWriter.url(id: meetingId, stem: .mix).path
        let shouldDeleteAudio = UserDefaults.standard.boolOr(AppSettings.deleteAudioAfterTranscription, default: false)

        statusText = FinalSTTTranscriber.isAvailable ? "Final-STT läuft" : "Transkribiere"
        let lines = await meetingTranscriber.transcribe(
            meetingId: meetingId,
            mic: samples,
            system: [],
            mixed: samples,
            language: lang
        )

        guard !lines.isEmpty else {
            let empty = MeetingDetail(
                id: meetingId, title: "\(fileName) (keine Sprache)", dateLong: dateLong,
                timeRange: timeRange, duration: durationShort, platform: .call, wordCount: 0,
                participants: [LocalSpeakerProfile.participant(spoke: durationShort)],
                tldr: "Keine Sprach-Inhalte erkannt.",
                highlights: [], tasks: [], chapters: [], transcript: [],
                audioURL: shouldDeleteAudio ? nil : audioPath, lifecycle: .done
            )
            store.updateDetail(empty)
            if shouldDeleteAudio { _ = try? PrivacyDataService.deleteAudioFiles(for: meetingId) }
            statusText = "Bereit"
            return
        }

        let summaryLines = TranscriptNoiseFilter.filtered(lines)
        let participants = collectParticipants(lines: lines, baseDuration: durationShort)
        let wordCount = TranscriptNoiseFilter.wordCount(lines)

        let transcribed = MeetingDetail(
            id: meetingId, title: fileName, dateLong: dateLong, timeRange: timeRange,
            duration: durationShort, platform: .call, wordCount: wordCount,
            participants: participants, tldr: "KI-Zusammenfassung läuft…",
            highlights: [], tasks: [], chapters: [], transcript: lines,
            audioURL: audioPath, lifecycle: .summarizing
        )
        store.updateDetail(transcribed)
        statusText = "KI verarbeitet"

        let summary = await MeetingSummarizer.summarize(
            meetingId: meetingId,
            transcriptLines: summaryLines.isEmpty ? lines : summaryLines,
            locale: lang,
            licenseAllowsSummary: { [weak self] in self?.licenseAllowsSummary() ?? true }
        )
        let finalTitle = summary.title.isEmpty ? fileName : summary.title
        let finalDetail = MeetingDetail(
            id: meetingId, title: finalTitle, dateLong: dateLong, timeRange: timeRange,
            duration: durationShort, platform: .call, wordCount: wordCount,
            participants: participants, tldr: summary.tldr,
            highlights: summary.highlights, tasks: summary.tasks, chapters: summary.chapters, transcript: lines,
            audioURL: shouldDeleteAudio ? nil : audioPath, lifecycle: .done
        )
        store.updateDetail(finalDetail)
        if shouldDeleteAudio { _ = try? PrivacyDataService.deleteAudioFiles(for: meetingId) }
        statusText = "Bereit"
    }

    /// Speaker-ID für Zeilen aus einer nachträglich gemergten Zweitaufnahme.
    static let mergedExternalSpeakerId = "EXT"

    /// Ergänzt ein bestehendes Meeting um eine zweite Audioquelle: dekodieren,
    /// transkribieren, die neuen Zeilen zeit-sortiert ins Transkript mergen
    /// (mit Text+Zeit-Dedup gegen Dubletten) und neu zusammenfassen. Use-Case:
    /// eine Backup-Aufnahme füllt Lücken, die das Original nicht erfasst hat.
    /// Gibt bei Fehlern eine deutsche Meldung zurück (nil = ok).
    @discardableResult
    func mergeAudioIntoMeeting(meetingId: String, url: URL) async -> String? {
        guard let store, let detail = store.detail(for: meetingId), !detail.processing else {
            return "Meeting nicht verfügbar oder wird gerade verarbeitet."
        }

        statusText = "Zusatz-Audio wird gelesen"
        let samples: [Float]
        do {
            samples = try await AudioIngestService.decode(url: url)
        } catch {
            statusText = "Bereit"
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            NSLog("[RecordingController] Merge-Decode fehlgeschlagen: \(message)")
            return message
        }

        // Zweitquelle als eigenen Stem ablegen (für spätere Reprozesse/Playback).
        let mergeStemId = "\(meetingId).merge-\(Int(Date().timeIntervalSince1970))"
        _ = try? AudioWriter.persist(id: mergeStemId, stem: .mic, samples: samples)

        // UI in den Processing-Zustand setzen, Original-Inhalte bleiben sichtbar.
        store.updateDetail(detail.with(tldr: "Zusatz-Audio wird eingearbeitet…", lifecycle: .transcribing))
        statusText = FinalSTTTranscriber.isAvailable ? "Final-STT läuft" : "Transkribiere"

        let lang = UserDefaults.standard.stringOr(AppSettings.language, default: "auto")
        let incoming = await meetingTranscriber.transcribe(
            meetingId: meetingId,
            mic: samples,
            system: [],
            mixed: samples,
            language: lang
        ).map { line -> TranscriptLine in
            TranscriptLine(
                who: Self.mergedExternalSpeakerId,
                displayName: "Zusatzaufnahme",
                timestamp: line.timestamp,
                startSeconds: line.startSeconds,
                endSeconds: line.endSeconds,
                body: line.body,
                source: .merged,
                speakerSource: .unknown,
                confidence: line.confidence,
                highlight: false
            )
        }

        guard !incoming.isEmpty else {
            store.updateDetail(detail.with(tldr: detail.tldr, lifecycle: .done))
            statusText = "Bereit"
            return "In der Zusatzaufnahme wurde keine Sprache erkannt."
        }

        let mergedLines = Self.fuseTranscripts(original: detail.transcript, incoming: incoming)
        let summaryLines = TranscriptNoiseFilter.filtered(mergedLines)
        let addedCount = mergedLines.count - detail.transcript.count
        let wordCount = TranscriptNoiseFilter.wordCount(mergedLines)

        var participants = detail.participants
        if addedCount > 0, !participants.contains(where: { $0.id == Self.mergedExternalSpeakerId }) {
            participants.append(Participant(
                id: Self.mergedExternalSpeakerId,
                name: "Zusatzaufnahme",
                role: "Ergänzt",
                colorHex: SpeakerPalette.color(for: Self.mergedExternalSpeakerId),
                spoke: ""
            ))
        }

        store.updateDetail(detail.with(
            wordCount: wordCount,
            participants: participants,
            tldr: "KI-Zusammenfassung läuft…",
            transcript: mergedLines,
            lifecycle: .summarizing
        ))
        statusText = "KI verarbeitet"

        let summary = await MeetingSummarizer.summarize(
            meetingId: meetingId,
            idPrefix: "merge-",
            transcriptLines: summaryLines.isEmpty ? mergedLines : summaryLines,
            locale: lang,
            licenseAllowsSummary: { [weak self] in self?.licenseAllowsSummary() ?? true }
        )
        store.updateDetail(detail.with(
            title: summary.title.isEmpty ? detail.title : summary.title,
            wordCount: wordCount,
            participants: participants,
            tldr: summary.tldr.isEmpty ? detail.tldr : summary.tldr,
            highlights: summary.highlights,
            tasks: summary.tasks,
            chapters: summary.chapters,
            transcript: mergedLines,
            lifecycle: .done
        ))
        statusText = "Bereit"
        return nil
    }

    /// Fusioniert zwei Transkripte EINES doppelt aufgenommenen Meetings —
    /// zeitUNabhängig per Text-Alignment. Nötig, weil parallele Aufnahmen
    /// (NeoQuill + Sprachmemo) nie synchron starten und ein zeitbasiertes
    /// Matching deshalb scheitert.
    ///
    /// Verfahren: Inverted Index über die Original-Zeilen-Tokens, dann pro
    /// incoming-Zeile die inhaltlich ähnlichste Original-Zeile suchen
    /// (Jaccard ≥ mergeMatchThreshold = Dublette). Substanzielle Zeilen ohne
    /// Treffer sind echte Lücken und werden via monotonem Anchor-Merge an der
    /// passenden Gesprächsposition eingefügt. So füllt die bessere/vollständigere
    /// Quelle die Lücken der anderen, ohne Dubletten zu erzeugen.
    nonisolated static func fuseTranscripts(
        original: [TranscriptLine],
        incoming: [TranscriptLine]
    ) -> [TranscriptLine] {
        let mergeMatchThreshold = 0.5
        let mergeMinTokens = 4
        guard !original.isEmpty else { return incoming }
        guard !incoming.isEmpty else { return original }

        let origTokens = original.map { lineTokens($0.body) }
        var inverted: [String: Set<Int>] = [:]
        for (i, tokens) in origTokens.enumerated() where tokens.count >= mergeMinTokens {
            for word in tokens { inverted[word, default: []].insert(i) }
        }

        var result: [TranscriptLine] = []
        result.reserveCapacity(original.count + incoming.count)
        var consumed = 0

        for line in incoming {
            let tokens = lineTokens(line.body)
            var matchIdx = -1
            if tokens.count >= mergeMinTokens {
                var candidates: Set<Int> = []
                for word in tokens { if let hits = inverted[word] { candidates.formUnion(hits) } }
                var best = 0.0
                for ci in candidates {
                    let score = jaccard(tokens, origTokens[ci])
                    if score > best { best = score; matchIdx = ci }
                }
                if best < mergeMatchThreshold { matchIdx = -1 }
            }

            if matchIdx >= consumed {
                while consumed <= matchIdx {
                    result.append(original[consumed]); consumed += 1
                }
            } else if matchIdx == -1 && tokens.count >= mergeMinTokens {
                // Substanzielle Lücke → einfügen (incoming ist bereits als
                // Zusatzquelle markiert). Floskeln/Out-of-order-Dubletten: skip.
                result.append(line)
            }
        }
        while consumed < original.count {
            result.append(original[consumed]); consumed += 1
        }
        return result
    }

    /// Lowercase Wort-Tokens eines Transkript-Bodys (Satzzeichen entfernt).
    nonisolated static func lineTokens(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }

    /// Jaccard-Ähnlichkeit zweier Token-Mengen (0…1).
    nonisolated static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        if a.isEmpty && b.isEmpty { return 1 }
        let union = a.union(b).count
        return union == 0 ? 0 : Double(a.intersection(b).count) / Double(union)
    }

    private func reprocessMeetingAsync(_ meetingId: String) async {
        await reprocessMeetingAsync(meetingId, platformEvents: [])
    }

    private func reprocessMeetingAsync(_ meetingId: String, platformEvents: [PlatformTranscriptEvent]) async {
        guard let store, let detail = store.detail(for: meetingId), !detail.processing else { return }
        let busy = detail.with(
            tldr: "Final-STT läuft…",
            highlights: [],
            tasks: [],
            chapters: [],
            lifecycle: .transcribing
        )
        store.updateDetail(busy)
        statusText = "Final-STT läuft"

        let storedAudio = readStoredAudio(meetingId: meetingId, detail: detail)
        let lang = UserDefaults.standard.stringOr(AppSettings.language, default: "auto")
        var allLines = await meetingTranscriber.transcribe(
            meetingId: meetingId,
            mic: storedAudio.mic,
            system: storedAudio.system,
            mixed: storedAudio.mixed,
            language: lang
        )

        var participants = allLines.isEmpty
            ? detail.participants
            : collectParticipants(lines: allLines, baseDuration: detail.duration)

        let diarizationEnabled = UserDefaults.standard.boolOr(AppSettings.speakerDiarization, default: false)
        let diarSamplesAvailable = diarizationEnabled && diarizer.isReady && storedAudio.system.count > 16_000 * 5
        var diarSegments: [DiarizedSpeakerSegment] = []
        if diarSamplesAvailable {
            statusText = "Erkenne Sprecher"
            diarSegments = await runDiarization(samples: storedAudio.system)
            var freshEmbeddings: [String: [Float]] = [:]
            for segment in diarSegments where freshEmbeddings[segment.speakerId] == nil {
                freshEmbeddings[segment.speakerId] = segment.embedding
            }
            persistMeetingEmbeddings(meetingId: meetingId, embeddings: freshEmbeddings)
        }
        if diarSamplesAvailable || !platformEvents.isEmpty {
            allLines = mergeSpeakers(
                lines: allLines,
                captionEvents: [],
                platformEvents: platformEvents,
                diarization: diarSegments
            )
            participants = collectParticipants(
                lines: allLines,
                baseDuration: detail.duration,
                diarizationSegments: diarSegments
            )
        }
        if !platformEvents.isEmpty {
            persistPlatformIdentities(from: allLines, platform: detail.platform)
        }

        let summaryLines = TranscriptNoiseFilter.filtered(allLines)
        let wordCount = TranscriptNoiseFilter.wordCount(allLines)
        let shouldDeleteAudio = UserDefaults.standard.boolOr(AppSettings.deleteAudioAfterTranscription, default: false)
        guard !allLines.isEmpty else {
            let empty = detail.with(
                title: "Aufnahme ohne Sprache",
                wordCount: 0,
                participants: participants,
                tldr: "Keine Sprach-Inhalte erkannt.",
                highlights: [],
                tasks: [],
                chapters: [],
                transcript: [],
                audioURL: shouldDeleteAudio ? nil : (storedAudio.audioURL?.path ?? detail.audioURL),
                lifecycle: .done
            )
            store.updateDetail(empty)
            if shouldDeleteAudio {
                _ = try? PrivacyDataService.deleteAudioFiles(for: meetingId)
            }
            statusText = "Bereit"
            return
        }

        let transcribed = detail.with(
            title: generateTitle(from: summaryLines.isEmpty ? allLines : summaryLines, started: Date()),
            wordCount: wordCount,
            participants: participants,
            tldr: "KI-Zusammenfassung läuft…",
            highlights: [],
            tasks: [],
            transcript: allLines,
            audioURL: storedAudio.audioURL?.path ?? detail.audioURL,
            lifecycle: .summarizing
        )
        store.updateDetail(transcribed)

        statusText = "KI verarbeitet"
        let summary = await MeetingSummarizer.summarize(
            meetingId: detail.id,
            idPrefix: "reprocess-",
            transcriptLines: summaryLines.isEmpty ? allLines : summaryLines,
            locale: lang,
            licenseAllowsSummary: { [weak self] in self?.licenseAllowsSummary() ?? true }
        )
        let final = transcribed.with(
            title: summary.title.isEmpty ? transcribed.title : summary.title,
            wordCount: wordCount,
            participants: participants,
            tldr: summary.tldr,
            highlights: summary.highlights,
            tasks: summary.tasks,
            chapters: summary.chapters,
            transcript: allLines,
            audioURL: shouldDeleteAudio ? nil : (storedAudio.audioURL?.path ?? detail.audioURL),
            lifecycle: .done
        )
        store.updateDetail(final)
        if shouldDeleteAudio {
            _ = try? PrivacyDataService.deleteAudioFiles(for: meetingId)
        }
        statusText = "Bereit"
    }

    private func persistCapturedAudio(meetingId: String, session: CapturedSession) -> URL? {
        do {
            let mixURL = try AudioWriter.persist(id: meetingId, stem: .mix, samples: session.mixed)
            _ = try AudioWriter.persist(id: meetingId, stem: .mic, samples: session.mic)
            _ = try AudioWriter.persist(id: meetingId, stem: .system, samples: session.sys)

            // High-resolution stereo archive (mic = left, system = right) is the
            // user-facing playback/export file — but only when BOTH sources carry
            // audio. A hard-panned stereo file with one empty channel would play
            // in one ear only, so mic-only / system-only captures keep the 16 kHz
            // mono mix as the playback file.
            let bothStems = !session.micHQ.isEmpty && !session.sysHQ.isEmpty
            let hqURL = bothStems ? try AudioWriter.persistStereo(
                id: meetingId,
                stem: .hq,
                left: session.micHQ,
                right: session.sysHQ
            ) : nil
            return hqURL ?? mixURL
        } catch {
            NSLog("[RecordingController] Stem persist failed: \(error)")
            return nil
        }
    }

    /// Embeddings der letzten Aufnahme — verfügbar für das Speaker-Labeling-Sheet.
    private(set) var lastEmbeddings: [String: [Float]] = [:]

    /// Importiertes Plattform-Transkript auf Meeting anwenden — re-running Final-STT
    /// mit den neuen platformEvents im Merger. Synchroner Trigger, asynchrone Arbeit.
    func applyPlatformImport(meetingId: String, events: [PlatformTranscriptEvent]) {
        Task { [weak self] in
            await self?.reprocessMeetingAsync(meetingId, platformEvents: events)
        }
    }

    /// User labelt "S1 → Thorsten". Der komplette Flow (Embedding-Auflösung,
    /// kanonische ID, Relabel, Cross-Meeting-Backfill) lebt im
    /// `SpeakerIdentityCoordinator` — der Controller liefert nur seinen
    /// Embedding-Cache der letzten Aufnahme als Fallback plus das Lizenz-Gate.
    /// Gibt zurück, wie viele weitere Meetings migriert wurden (UI-Feedback).
    @discardableResult
    func labelSpeaker(
        internalId: String,
        name: String,
        colorHex: UInt32,
        meetingId: String?,
        knownSpeakerId: String? = nil
    ) -> Int {
        guard let speakerStore else { return 0 }
        return SpeakerIdentityCoordinator(speakerStore: speakerStore, store: store).label(
            meetingId: meetingId,
            internalId: internalId,
            name: name,
            colorHex: colorHex,
            knownSpeakerId: knownSpeakerId,
            cachedEmbedding: lastEmbeddings[internalId],
            allowCrossMeetingBackfill: licenseAllowsCrossMeetingSpeakerID()
        )
    }

    private func persistMeetingEmbeddings(meetingId: String, embeddings: [String: [Float]]) {
        guard let speakerStore else { return }
        SpeakerIdentityCoordinator(speakerStore: speakerStore)
            .recordMeetingEmbeddings(meetingId: meetingId, embeddings: embeddings)
    }

    private func readStoredAudio(
        meetingId: String,
        detail: MeetingDetail
    ) -> (mic: [Float], system: [Float], mixed: [Float], audioURL: URL?) {
        let fileManager = FileManager.default
        let micURL = AudioWriter.url(id: meetingId, stem: .mic)
        let systemURL = AudioWriter.url(id: meetingId, stem: .system)
        let derivedMixURL = AudioWriter.url(id: meetingId, stem: .mix)
        let storedMixURL = detail.audioURL.map { URL(fileURLWithPath: $0) }
        let mixURL = [storedMixURL, derivedMixURL]
            .compactMap { $0 }
            .first { fileManager.fileExists(atPath: $0.path) }

        let mic = fileManager.fileExists(atPath: micURL.path)
            ? ((try? AudioWriter.readSamples(from: micURL)) ?? [])
            : []
        let system = fileManager.fileExists(atPath: systemURL.path)
            ? ((try? AudioWriter.readSamples(from: systemURL)) ?? [])
            : []
        let mixed = mixURL.flatMap { try? AudioWriter.readSamples(from: $0) } ?? []
        // Playback prefers the 48 kHz stereo archive, but only when BOTH stems
        // carry audio — a hard-panned stereo file with one empty channel plays in
        // one ear only, so mic-only / system-only meetings keep the mono mix.
        // Re-processing/recovery must otherwise never downgrade a meeting that
        // already has a good .hq archive back to the mono mix.
        let bothStems = !mic.isEmpty && !system.isEmpty
        let playbackURL = bothStems
            ? RecordingArtifacts(meetingId: meetingId).preferredPlaybackURL(mixFallback: mixURL)
            : mixURL
        return (mic: mic, system: system, mixed: mixed, audioURL: playbackURL)
    }



    /// Mappt die erkannte Call-App auf die persistierte Plattform. Pure und
    /// nonisolated — wird beim `start()` in `sessionPlatform` eingefroren und
    /// reist danach als Teil der `CapturedSession`; zur Persist-Zeit wird der
    /// Detector nie mehr gelesen.
    nonisolated static func mappedPlatform(from app: CallApp) -> Platform {
        switch app {
        case .teams:    return .teams
        case .zoom:     return .zoom
        case .browser:  return .meet
        case .facetime, .slack, .discord, .webex, .unknown:
            return .call
        }
    }

    /// Diarisiert den System-Audio-Stream und gibt die aufgelöste
    /// Speaker-Timeline zurück. Die Resolution-Regeln (Kurz-Segment-Filter,
    /// Known-Voice-Match, ID-Normalisierung) leben im `SpeakerDiarizer` —
    /// hier wird nur der SpeakerStore als Matcher eingehängt.
    private func runDiarization(samples: [Float]) async -> [DiarizedSpeakerSegment] {
        await diarizer.resolveSegments(samples) { [weak speakerStore] embedding in
            speakerStore?.bestMatch(for: embedding)
        }
    }

    /// Match TranscriptLines (mit Mono-Timestamps) auf Diarize-Segments.
    /// Source-Aware: Mic-Lines bleiben die lokale Person, weil sie
    /// bereits aus dem Mic-Stream kommen. Nur Lines
    /// aus dem System-Audio-Stream werden mit Speaker-IDs aus Diarization
    /// geupdated. Pattern aus `tonton-golio/meeting-recorder`: separate Stems
    /// → keine Cross-Source-Verwechslung.
    private func mergeSpeakers(
        lines: [TranscriptLine],
        captionEvents: [CaptionEvent],
        platformEvents: [PlatformTranscriptEvent] = [],
        diarization: [DiarizedSpeakerSegment]
    ) -> [TranscriptLine] {
        TranscriptMerger.merge(
            audioLines: lines,
            captionEvents: captionEvents,
            platformTranscriptEvents: platformEvents,
            diarization: diarization
        )
    }

    private func collectParticipants(
        lines: [TranscriptLine],
        baseDuration: String,
        diarizationSegments: [DiarizedSpeakerSegment] = []
    ) -> [Participant] {
        let displayNames = Dictionary(
            lines.compactMap { line -> (String, String)? in
                guard let name = line.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !name.isEmpty
                else { return nil }
                return (line.who, name)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let speakerIds = Set(lines.map(\.who)).sorted { lhs, rhs in
            if LocalSpeakerProfile.isLocalSpeakerId(lhs) { return true }
            if LocalSpeakerProfile.isLocalSpeakerId(rhs) { return false }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        let fixedSpeakerIds = [LocalSpeakerProfile.id] + SpeakerPalette.fixedSpeakerIds
        let spokeBySpeaker = Self.spokenDurations(
            speakerIds: speakerIds,
            lines: lines,
            diarizationSegments: diarizationSegments,
            fallback: baseDuration
        )
        return speakerIds.compactMap { id in
            let spoke = spokeBySpeaker[id] ?? baseDuration
            if let known = speakerStore?.speaker(for: id) {
                return Participant(id: id, name: known.name, role: "Bekannt",
                                   colorHex: known.colorHex, spoke: spoke)
            }
            if let displayName = displayNames[id] {
                return Participant(id: id, name: displayName, role: "Caption",
                                   colorHex: SpeakerPalette.color(for: id), spoke: spoke)
            }
            guard fixedSpeakerIds.contains(id) else {
                return Participant(id: id, name: "Speaker \(id)", role: "Erkannt",
                                   colorHex: SpeakerPalette.color(for: id), spoke: spoke)
            }
            let name = LocalSpeakerProfile.isLocalSpeakerId(id) ? LocalSpeakerProfile.displayName : "Speaker \(id)"
            let role = LocalSpeakerProfile.isLocalSpeakerId(id) ? LocalSpeakerProfile.role : "Erkannt"
            return Participant(id: id, name: name, role: role,
                               colorHex: SpeakerPalette.color(for: id), spoke: spoke)
        }
    }

    /// Berechnet Sprechanteile pro Speaker. Diarization-Segmente sind die
    /// genaueste Quelle (entstehen direkt aus Audio-Energie). Fallback:
    /// Summe der TranscriptLine-Dauern. Letzter Fallback: `baseDuration`
    /// String, damit die UI nicht leer bleibt.
    nonisolated static func spokenDurations(
        speakerIds: [String],
        lines: [TranscriptLine],
        diarizationSegments: [DiarizedSpeakerSegment],
        fallback: String
    ) -> [String: String] {
        var diarTotals: [String: TimeInterval] = [:]
        for segment in diarizationSegments {
            let duration = max(0, segment.end - segment.start)
            guard duration > 0 else { continue }
            diarTotals[segment.speakerId, default: 0] += duration
        }

        var lineTotals: [String: TimeInterval] = [:]
        for line in lines {
            let duration = max(0, line.endSeconds - line.startSeconds)
            guard duration > 0 else { continue }
            lineTotals[line.who, default: 0] += duration
        }

        var result: [String: String] = [:]
        for id in speakerIds {
            if let seconds = diarTotals[id] {
                result[id] = formatSpoke(seconds: seconds)
            } else if let seconds = lineTotals[id] {
                result[id] = formatSpoke(seconds: seconds)
            } else {
                result[id] = fallback
            }
        }
        return result
    }

    nonisolated static func formatSpoke(seconds: TimeInterval) -> String {
        SpokenDuration.minutesSeconds(seconds)
    }

    private func persistCaptionIdentities(from lines: [TranscriptLine], platform: Platform) {
        guard let speakerStore else { return }
        SpeakerIdentityCoordinator(speakerStore: speakerStore)
            .persistIdentities(from: lines, platform: platform, kind: .caption)
    }

    private func persistPlatformIdentities(from lines: [TranscriptLine], platform: Platform) {
        guard let speakerStore else { return }
        SpeakerIdentityCoordinator(speakerStore: speakerStore)
            .persistIdentities(from: lines, platform: platform, kind: .platform)
    }

    private func generateTitle(from lines: [TranscriptLine], started: Date) -> String {
        if let first = lines.first?.body, !first.isEmpty {
            let prefix = first.split(separator: " ").prefix(7).joined(separator: " ")
            return prefix
        }
        return "Aufnahme \(MeetingTimeline.timeString(from: started))"
    }

    // MARK: - Internal wiring

    private func wireAudioCapture() {
        // Mic + Sys werden in AudioCapture in `micRecording`/`sysRecording`
        // gepuffert — der finale Whisper-Pass läuft erst in `persistMeeting`
        // über `collectFinalAudio`. Hier nur das Live-Audio-Level für die
        // Pille (Bars im Recording-Modus).
        levelCancellable = audioCapture.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.audioLevel = level
            }
    }

    private func startCaptionCapture(startedAt: Date, app: CallApp) {
        captionCapture.start(for: app, startedAt: startedAt)
    }

    private func startElapsedTimer() {
        elapsed = 0
        elapsedTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let start = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.cancel()
        elapsedTimer = nil
    }
}
