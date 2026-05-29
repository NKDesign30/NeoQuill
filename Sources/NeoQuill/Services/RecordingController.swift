import Foundation
import Combine
import AVFoundation

// Orchestrator für eine Live-Aufnahme:
// - PermissionGate prüft Mic/Audio.
// - AudioCapture liefert dual-stream Float-Chunks (Mic + System-Audio via ProcessTap).
// - LiveTranscriber (WhisperKit) verarbeitet Chunks → TranscriptSegments.
// - SpeakerDiarizer (FluidAudio) labelt Speaker auf dem System-Audio-Stream (Phase 4b).
// - LiveLines werden gepublished für RecordingView.
// - Auf Stop: finales Transcript wird in MeetingStore persistiert (Phase 4b).

@MainActor
final class RecordingController: ObservableObject {

    // MARK: - Published state für UI

    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var liveLines: [TranscriptLine] = []
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var device: String = "Mikrofon"
    @Published private(set) var modelLabel: String = "WhisperKit ANE"
    @Published private(set) var statusText: String = "Bereit"
    @Published private(set) var captionStatusText: String = "Captions aus"
    @Published private(set) var captionEventCount: Int = 0
    @Published private(set) var hasMicPermission: Bool = false
    /// Live-Audio-Level (RMS, 0..~1) — UI-Header/Pille zeigt Live-Bars.
    @Published private(set) var audioLevel: Float = 0

    // MARK: - Dependencies

    private let audioCapture = AudioCapture()
    private let captionCapture = CaptionCaptureService()
    /// Single Whisper-Instance fuer Post-Recording. Mic- und Sys-Stem laufen
    /// sequenziell durch. Ein Modell = halbe RAM-Last + kein ANE-Konflikt.
    private let transcriber = LiveTranscriber()
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
    private var deviceCancellable: AnyCancellable?
    private var levelCancellable: AnyCancellable?
    private var captionStateCancellable: AnyCancellable?
    private var captionEventsCancellable: AnyCancellable?
    private var autoDetectActive = false

    private var elapsedTimer: AnyCancellable?
    private var startedAt: Date?
    private var micChunkOffset: TimeInterval = 0
    private var sysChunkOffset: TimeInterval = 0

    // MARK: - Lifecycle

    init() {
        wireTranscriber()
        wireAudioCapture()
        wireCaptionCapture()
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
        modelLabel = FinalSTTTranscriber.isAvailable ? FinalSTTTranscriber.label : "WhisperKit ANE"
        if !FinalSTTTranscriber.isAvailable {
            let model = UserDefaults.standard.stringOr(AppSettings.whisperModel, default: "openai_whisper-small")
            let lang  = UserDefaults.standard.stringOr(AppSettings.language, default: "auto")
            _ = await transcriber.loadModel(model: model, language: lang)
            modelLabel = friendlyModelLabel(model)
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
        modelLabel = FinalSTTTranscriber.isAvailable ? FinalSTTTranscriber.label : friendlyModelLabel(model)

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
            // BundleIds vor `start()` setzen — sonst tappt der ProcessTap einen
            // generischen Stereo-Mix statt gezielt Teams/Zoom. Bei Auto-Detect liefert
            // der Detector bereits die App, sonst probieren wir einmal `detectOnce`.
            if detector.detectedApp == .unknown {
                detector.detectOnce()
            }
            audioCapture.targetBundleIds = detector.detectedApp.bundleIdentifiers
            try await audioCapture.start()
            liveLines.removeAll()
            micChunkOffset = 0
            sysChunkOffset = 0
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

        let runtime = elapsed
        let started = startedAt ?? Date()
        let captionEvents = captionCapture.stop()

        // UI sofort entlasten: Provisional-Detail einsetzen + State auf idle,
        // sodass die RecordingView verlassen und die Detail-View mit
        // "Wird transkribiert…" angezeigt wird. Whisper + Claude laufen im
        // Hintergrund und updaten das Detail wenn fertig.
        let meetingId = "rec-\(Int(started.timeIntervalSince1970))"
        insertProvisionalMeeting(id: meetingId, runtime: runtime, started: started)

        state = .idle
        statusText = "Bereit"
        // Detector wurde nicht pausiert — kein Resume noetig. Self-Trigger
        // verhindert via State-Check in `handleDetectorChange`.

        // Heavy Lifting im Hintergrund — Whisper auf Stems, FluidAudio-Diarize,
        // Claude-Summary. Updated das Provisional-Detail Schritt fuer Schritt.
        Task { [weak self] in
            await self?.persistMeeting(
                meetingId: meetingId,
                runtime: runtime,
                started: started,
                captionEvents: captionEvents
            )
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
        let orphans = store.details.values
            .filter { $0.processing && $0.transcript.isEmpty }
            .map(\.id)
        guard !orphans.isEmpty else { return }
        Task { [weak self] in
            guard let self, let store = self.store else { return }
            for id in orphans {
                // Clear the stuck `processing` flag first — reprocessMeetingAsync
                // bails out on `!detail.processing`, which is exactly the state an
                // orphaned meeting is in. Without this the re-run is a no-op.
                if var detail = store.detail(for: id) {
                    detail.processing = false
                    store.updateDetail(detail)
                }
                await self.reprocessMeetingAsync(id)
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

        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }

        let fileName = url.deletingPathExtension().lastPathComponent
        statusText = "Audio wird gelesen"

        let samples: [Float]
        do {
            samples = try await Task.detached(priority: .userInitiated) {
                try AudioImporter.decodeToWhisperSamples(url: url)
            }.value
        } catch {
            statusText = "Bereit"
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            NSLog("[RecordingController] Audio-Import fehlgeschlagen: \(message)")
            return message
        }

        let started = Date()
        let runtime = TimeInterval(samples.count) / AudioImporter.targetSampleRate
        let meetingId = "import-\(Int(started.timeIntervalSince1970))"

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
        platform: Platform? = nil
    ) {
        guard let store else { return }
        let durationShort = formatDurationShort(runtime)
        let timeShort = Self.timeFormatter.string(from: started)
        let dateShort = Self.dateShortFormatter.string(from: started)
        let dateLong = Self.dateLongFormatter.string(from: started)
        let endDate = started.addingTimeInterval(runtime)
        let timeRange = "\(timeShort) – \(Self.timeFormatter.string(from: endDate))"
        let provisionalTitle = title ?? "Aufnahme \(timeShort)"
        let resolvedPlatform = platform ?? detectedPlatform()
        let participants: [Participant] = [LocalSpeakerProfile.participant(spoke: durationShort)]

        let summary = MeetingSummary(
            id: id, title: provisionalTitle, date: dateShort, time: timeShort,
            duration: durationShort, platform: resolvedPlatform, wordCount: 0,
            group: "Diesen Monat", participantIds: [LocalSpeakerProfile.id], unread: true
        )
        let provisional = MeetingDetail(
            id: id, title: provisionalTitle, dateLong: dateLong, timeRange: timeRange,
            duration: durationShort, platform: resolvedPlatform, wordCount: 0,
            participants: participants,
            tldr: "Wird transkribiert…",
            highlights: [], tasks: [], chapters: [],
            transcript: [], audioURL: nil, processing: true
        )
        store.insert(summary: summary, detail: provisional)
    }

    private func persistMeeting(
        meetingId: String,
        runtime: TimeInterval,
        started: Date,
        captionEvents: [CaptionEvent]
    ) async {
        guard let store else { return }
        let id = meetingId
        let durationShort = formatDurationShort(runtime)
        let timeShort = Self.timeFormatter.string(from: started)
        let dateLong = Self.dateLongFormatter.string(from: started)
        let endDate = started.addingTimeInterval(runtime)
        let timeRange = "\(timeShort) – \(Self.timeFormatter.string(from: endDate))"

        let captured = audioCapture.collectFinalAudio()
        let capturedHQ = audioCapture.collectFinalAudioHQ()
        let audioURL = persistCapturedAudio(meetingId: id, captured: captured, capturedHQ: capturedHQ)

        let lang = UserDefaults.standard.stringOr(AppSettings.language, default: "auto")
        statusText = FinalSTTTranscriber.isAvailable ? "Final-STT läuft" : "Transkribiere"

        var allLines = await transcribeFinalAudio(
            meetingId: id,
            mic: captured.mic,
            system: captured.sys,
            mixed: captured.mixed,
            language: lang
        )
        var participants: [Participant] = [LocalSpeakerProfile.participant(spoke: durationShort)]

        var pendingEmbeddings: [String: [Float]] = [:]
        var diarizationSegments: [DiarizedSpeakerSegment] = []
        // FluidAudio-Diarize auf System-Audio (>= 5s) — labelt S1 ggf. um in S2/S3
        // bzw. matcht gegen bekannte Speaker (Re-ID via SpeakerStore).
        if UserDefaults.standard.boolOr(AppSettings.speakerDiarization, default: false), diarizer.isReady {
            if captured.sys.count > 16_000 * 5 {
                statusText = "Erkenne Sprecher"
                diarizationSegments = await runDiarization(samples: captured.sys)
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
            persistCaptionIdentities(from: allLines, platform: detectedPlatform())
            participants = collectParticipants(
                lines: allLines,
                baseDuration: durationShort,
                diarizationSegments: diarizationSegments
            )
        }

        let summaryLines = TranscriptNoiseFilter.filtered(allLines)
        let wordCount = TranscriptNoiseFilter.wordCount(allLines)
        let provisionalTitle = generateTitle(from: summaryLines.isEmpty ? allLines : summaryLines, started: started)

        // Detail mit echten Lines updaten (Provisional ist schon eingefuegt).
        let transcribed = MeetingDetail(
            id: id,
            title: provisionalTitle,
            dateLong: dateLong,
            timeRange: timeRange,
            duration: durationShort,
            platform: detectedPlatform(),
            wordCount: wordCount,
            participants: participants,
            tldr: "KI-Zusammenfassung läuft…",
            highlights: [],
            tasks: [],
            chapters: [],
            transcript: allLines,
            audioURL: nil,
            processing: true
        )
        store.updateDetail(transcribed, summaryTitle: provisionalTitle)
        statusText = "KI verarbeitet"

        // Embeddings frisch entdeckter Speaker für später vorhalten — UI-Labeling-Sheet
        // greift darauf zu, wenn der User "S1 = Thorsten" tippt.
        for (speakerId, embedding) in pendingEmbeddings where !embedding.isEmpty {
            self.lastEmbeddings[speakerId] = embedding
        }

        // 2. Async: WAV speichern + Claude-Summary holen, dann Detail updaten.
        let result = await PostProcessor.process(
            meetingId: id,
            mixedSamples: [],
            transcriptLines: summaryLines.isEmpty ? allLines : summaryLines,
            locale: lang,
            licenseAllowsSummary: { [weak self] in self?.licenseAllowsSummary() ?? true }
        )

        let highlights = result.highlights.map { mapAIHighlight($0) }
        let tasks = result.tasks.enumerated().map { idx, t in
            ActionItem(
                id: "\(id)-task-\(idx)",
                who: t.who.isEmpty ? "??" : t.who,
                task: t.task,
                due: t.due,
                status: t.status == "done" ? .done : .open
            )
        }
        let chapters = result.chapters.enumerated().map { idx, c in
            Chapter(
                id: "\(id)-ch-\(idx)",
                timestamp: c.timestamp,
                label: c.label,
                duration: c.duration
            )
        }

        let finalAudioPath = result.audioURL?.path ?? audioURL?.path
        let shouldDeleteAudio = UserDefaults.standard.boolOr(AppSettings.deleteAudioAfterTranscription, default: false)
        let finalDetail = MeetingDetail(
            id: id,
            title: result.title.isEmpty ? provisionalTitle : result.title,
            dateLong: dateLong,
            timeRange: timeRange,
            duration: durationShort,
            platform: detectedPlatform(),
            wordCount: wordCount,
            participants: participants,
            tldr: result.tldr,
            highlights: highlights,
            tasks: tasks,
            chapters: chapters,
            transcript: allLines,
            audioURL: shouldDeleteAudio ? nil : finalAudioPath,
            processing: false
        )

        store.updateDetail(
            finalDetail,
            summaryTitle: result.title.isEmpty ? nil : result.title
        )
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
        let durationShort = formatDurationShort(runtime)
        let timeShort = Self.timeFormatter.string(from: started)
        let dateLong = Self.dateLongFormatter.string(from: started)
        let endDate = started.addingTimeInterval(runtime)
        let timeRange = "\(timeShort) – \(Self.timeFormatter.string(from: endDate))"
        let lang = UserDefaults.standard.stringOr(AppSettings.language, default: "auto")
        let audioPath = AudioWriter.url(id: meetingId, stem: .mix).path
        let shouldDeleteAudio = UserDefaults.standard.boolOr(AppSettings.deleteAudioAfterTranscription, default: false)

        statusText = FinalSTTTranscriber.isAvailable ? "Final-STT läuft" : "Transkribiere"
        let lines = await transcribeFinalAudio(
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
                audioURL: shouldDeleteAudio ? nil : audioPath, processing: false
            )
            store.updateDetail(empty, summaryTitle: empty.title)
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
            audioURL: audioPath, processing: true
        )
        store.updateDetail(transcribed, summaryTitle: fileName)
        statusText = "KI verarbeitet"

        let result = await PostProcessor.process(
            meetingId: meetingId,
            mixedSamples: [],
            transcriptLines: summaryLines.isEmpty ? lines : summaryLines,
            locale: lang,
            licenseAllowsSummary: { [weak self] in self?.licenseAllowsSummary() ?? true }
        )
        let highlights = result.highlights.map { mapAIHighlight($0) }
        let tasks = result.tasks.enumerated().map { idx, t in
            ActionItem(
                id: "\(meetingId)-task-\(idx)",
                who: t.who.isEmpty ? "??" : t.who,
                task: t.task,
                due: t.due,
                status: t.status == "done" ? .done : .open
            )
        }
        let chapters = result.chapters.enumerated().map { idx, c in
            Chapter(id: "\(meetingId)-ch-\(idx)", timestamp: c.timestamp, label: c.label, duration: c.duration)
        }
        let finalTitle = result.title.isEmpty ? fileName : result.title
        let finalDetail = MeetingDetail(
            id: meetingId, title: finalTitle, dateLong: dateLong, timeRange: timeRange,
            duration: durationShort, platform: .call, wordCount: wordCount,
            participants: participants, tldr: result.tldr,
            highlights: highlights, tasks: tasks, chapters: chapters, transcript: lines,
            audioURL: shouldDeleteAudio ? nil : (result.audioURL?.path ?? audioPath), processing: false
        )
        store.updateDetail(finalDetail, summaryTitle: finalTitle)
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

        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }

        statusText = "Zusatz-Audio wird gelesen"
        let samples: [Float]
        do {
            samples = try await Task.detached(priority: .userInitiated) {
                try AudioImporter.decodeToWhisperSamples(url: url)
            }.value
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
        store.updateDetail(rebuiltDetail(from: detail, tldr: "Zusatz-Audio wird eingearbeitet…", processing: true))
        statusText = FinalSTTTranscriber.isAvailable ? "Final-STT läuft" : "Transkribiere"

        let lang = UserDefaults.standard.stringOr(AppSettings.language, default: "auto")
        let incoming = await transcribeFinalAudio(
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
            store.updateDetail(rebuiltDetail(from: detail, tldr: detail.tldr, processing: false))
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
                colorHex: colorHex(forSpeakerId: Self.mergedExternalSpeakerId),
                spoke: ""
            ))
        }

        store.updateDetail(rebuiltDetail(
            from: detail,
            wordCount: wordCount,
            participants: participants,
            tldr: "KI-Zusammenfassung läuft…",
            transcript: mergedLines,
            processing: true
        ))
        statusText = "KI verarbeitet"

        let result = await PostProcessor.process(
            meetingId: meetingId,
            mixedSamples: [],
            transcriptLines: summaryLines.isEmpty ? mergedLines : summaryLines,
            locale: lang,
            licenseAllowsSummary: { [weak self] in self?.licenseAllowsSummary() ?? true }
        )
        let highlights = result.highlights.map { mapAIHighlight($0) }
        let tasks = result.tasks.enumerated().map { idx, t in
            ActionItem(
                id: "\(meetingId)-merge-task-\(idx)",
                who: t.who.isEmpty ? "??" : t.who,
                task: t.task,
                due: t.due,
                status: t.status == "done" ? .done : .open
            )
        }
        let chapters = result.chapters.enumerated().map { idx, c in
            Chapter(id: "\(meetingId)-merge-ch-\(idx)", timestamp: c.timestamp, label: c.label, duration: c.duration)
        }
        store.updateDetail(rebuiltDetail(
            from: detail,
            title: result.title.isEmpty ? detail.title : result.title,
            wordCount: wordCount,
            participants: participants,
            tldr: result.tldr.isEmpty ? detail.tldr : result.tldr,
            highlights: highlights,
            tasks: tasks,
            chapters: chapters,
            transcript: mergedLines,
            processing: false
        ), summaryTitle: result.title.isEmpty ? nil : result.title)
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
        let busy = rebuiltDetail(
            from: detail,
            tldr: "Final-STT läuft…",
            highlights: [],
            tasks: [],
            chapters: [],
            processing: true
        )
        store.updateDetail(busy)
        statusText = "Final-STT läuft"

        let storedAudio = readStoredAudio(meetingId: meetingId, detail: detail)
        let lang = UserDefaults.standard.stringOr(AppSettings.language, default: "auto")
        var allLines = await transcribeFinalAudio(
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
            let empty = rebuiltDetail(
                from: detail,
                title: "Aufnahme ohne Sprache",
                wordCount: 0,
                participants: participants,
                tldr: "Keine Sprach-Inhalte erkannt.",
                highlights: [],
                tasks: [],
                chapters: [],
                transcript: [],
                audioURL: shouldDeleteAudio ? nil : (storedAudio.audioURL?.path ?? detail.audioURL),
                processing: false
            )
            store.updateDetail(empty, summaryTitle: empty.title)
            if shouldDeleteAudio {
                _ = try? PrivacyDataService.deleteAudioFiles(for: meetingId)
            }
            statusText = "Bereit"
            return
        }

        let transcribed = rebuiltDetail(
            from: detail,
            title: generateTitle(from: summaryLines.isEmpty ? allLines : summaryLines, started: Date()),
            wordCount: wordCount,
            participants: participants,
            tldr: "KI-Zusammenfassung läuft…",
            highlights: [],
            tasks: [],
            transcript: allLines,
            audioURL: storedAudio.audioURL?.path ?? detail.audioURL,
            processing: true
        )
        store.updateDetail(transcribed, summaryTitle: transcribed.title)

        statusText = "KI verarbeitet"
        let result = await PostProcessor.process(
            meetingId: detail.id,
            mixedSamples: [],
            transcriptLines: summaryLines.isEmpty ? allLines : summaryLines,
            locale: lang,
            licenseAllowsSummary: { [weak self] in self?.licenseAllowsSummary() ?? true }
        )
        let highlights = result.highlights.map { mapAIHighlight($0) }
        let tasks = result.tasks.enumerated().map { idx, t in
            ActionItem(
                id: "\(detail.id)-reprocess-task-\(idx)",
                who: t.who.isEmpty ? "??" : t.who,
                task: t.task,
                due: t.due,
                status: t.status == "done" ? .done : .open
            )
        }
        let chapters = result.chapters.enumerated().map { idx, c in
            Chapter(
                id: "\(detail.id)-reprocess-ch-\(idx)",
                timestamp: c.timestamp,
                label: c.label,
                duration: c.duration
            )
        }
        let final = rebuiltDetail(
            from: transcribed,
            title: result.title.isEmpty ? transcribed.title : result.title,
            wordCount: wordCount,
            participants: participants,
            tldr: result.tldr,
            highlights: highlights,
            tasks: tasks,
            chapters: chapters,
            transcript: allLines,
            audioURL: shouldDeleteAudio ? nil : (storedAudio.audioURL?.path ?? detail.audioURL),
            processing: false
        )
        store.updateDetail(final, summaryTitle: result.title.isEmpty ? nil : result.title)
        if shouldDeleteAudio {
            _ = try? PrivacyDataService.deleteAudioFiles(for: meetingId)
        }
        statusText = "Bereit"
    }

    private func mapAIHighlight(_ ai: HighlightAI) -> Highlight {
        let tone: HighlightTone
        switch ai.tone.lowercased() {
        case "warning":  tone = .warning
        case "info":     tone = .info
        default:         tone = .brand
        }
        return Highlight(label: ai.label, text: ai.text, tone: tone)
    }

    private func persistCapturedAudio(
        meetingId: String,
        captured: (mic: [Float], sys: [Float], mixed: [Float]),
        capturedHQ: (micHQ: [Float], sysHQ: [Float])
    ) -> URL? {
        do {
            let mixURL = try AudioWriter.persist(id: meetingId, stem: .mix, samples: captured.mixed)
            _ = try AudioWriter.persist(id: meetingId, stem: .mic, samples: captured.mic)
            _ = try AudioWriter.persist(id: meetingId, stem: .system, samples: captured.sys)

            // High-resolution stereo archive (mic = left, system = right) is the
            // user-facing playback/export file. Falls back to the 16 kHz mix if no
            // HQ samples were captured (e.g. mic-only legacy path).
            let hqURL = try AudioWriter.persistStereo(
                id: meetingId,
                stem: .hq,
                left: capturedHQ.micHQ,
                right: capturedHQ.sysHQ
            )
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

    /// User labelt "S1 → Thorsten" → SpeakerStore + bekannte Aufnahme rueckwirkend.
    /// Gibt zurueck wieviele weitere Meetings ueber Embedding-Match auf den
    /// gleichen Speaker migriert wurden (fuer UI-Feedback).
    @discardableResult
    func labelSpeaker(
        internalId: String,
        name: String,
        colorHex: UInt32,
        meetingId: String?,
        knownSpeakerId: String? = nil
    ) -> Int {
        let embedding = lastEmbeddings[internalId]
            ?? meetingId.flatMap { speakerStore?.meetingEmbedding(meetingId: $0, internalId: internalId) }
            ?? []
        let canonicalId = Self.canonicalSpeakerId(
            name: name,
            knownSpeakerId: knownSpeakerId,
            existingSpeakers: speakerStore?.speakers ?? []
        )
        if !embedding.isEmpty {
            speakerStore?.upsert(id: canonicalId, name: name, embedding: embedding, colorHex: colorHex)
        } else {
            speakerStore?.upsertIdentity(id: canonicalId, name: name, colorHex: colorHex)
        }
        if let meetingId {
            store?.relabelSpeaker(
                meetingId: meetingId,
                from: internalId,
                to: canonicalId,
                name: name,
                colorHex: colorHex
            )
            speakerStore?.renameMeetingInternalId(meetingId: meetingId, from: internalId, to: canonicalId)
        }
        guard licenseAllowsCrossMeetingSpeakerID() else { return 0 }
        return backfillCrossMeetings(
            embedding: embedding,
            canonicalId: canonicalId,
            name: name,
            colorHex: colorHex,
            currentMeetingId: meetingId
        )
    }

    /// Sucht Embedding-Treffer in anderen Meetings und migriert sie auf
    /// den jetzt bekannten Speaker. Pro Meeting hoechstens ein Treffer
    /// (der mit dem hoechsten Score), damit ein Speaker nicht zwei Slots
    /// im selben Meeting belegt.
    private func backfillCrossMeetings(
        embedding: [Float],
        canonicalId: String,
        name: String,
        colorHex: UInt32,
        currentMeetingId: String?
    ) -> Int {
        guard !embedding.isEmpty, let speakerStore, let store else { return 0 }
        let matches = speakerStore.meetingMatches(
            for: embedding,
            excluding: currentMeetingId
        )
        var seenMeetings: Set<String> = []
        var migrated = 0
        for match in matches {
            guard !seenMeetings.contains(match.meetingId) else { continue }
            guard match.internalId != canonicalId else {
                seenMeetings.insert(match.meetingId)
                continue
            }
            store.relabelSpeaker(
                meetingId: match.meetingId,
                from: match.internalId,
                to: canonicalId,
                name: name,
                colorHex: colorHex
            )
            speakerStore.renameMeetingInternalId(
                meetingId: match.meetingId,
                from: match.internalId,
                to: canonicalId
            )
            seenMeetings.insert(match.meetingId)
            migrated += 1
        }
        return migrated
    }

    private func persistMeetingEmbeddings(meetingId: String, embeddings: [String: [Float]]) {
        guard let speakerStore, !embeddings.isEmpty else { return }
        for (internalId, embedding) in embeddings where !embedding.isEmpty {
            speakerStore.recordMeetingEmbedding(
                meetingId: meetingId,
                internalId: internalId,
                embedding: embedding
            )
        }
    }

    static func canonicalSpeakerId(
        name: String,
        knownSpeakerId: String? = nil,
        existingSpeakers: [LabeledSpeaker] = []
    ) -> String {
        if let knownSpeakerId = knownSpeakerId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !knownSpeakerId.isEmpty {
            return knownSpeakerId
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedName = normalizedSpeakerName(trimmed)
        if !normalizedName.isEmpty,
           let existingSpeaker = existingSpeakers.first(where: { normalizedSpeakerName($0.name) == normalizedName }) {
            return existingSpeaker.id
        }
        return generatedSpeakerId(for: trimmed)
    }

    private static func normalizedSpeakerName(_ name: String) -> String {
        let folded = name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        return folded.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func generatedSpeakerId(for name: String) -> String {
        let separator = UnicodeScalar("-")
        let folded = name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        var scalars: [UnicodeScalar] = []
        var lastWasSeparator = true
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                scalars.append(scalar)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                scalars.append(separator)
                lastWasSeparator = true
            }
        }
        if scalars.last == separator {
            scalars.removeLast()
        }
        let slug = String(String.UnicodeScalarView(scalars))
        return slug.isEmpty ? "speaker-unknown" : "speaker-\(slug)"
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
        return (mic: mic, system: system, mixed: mixed, audioURL: mixURL)
    }

    private func transcribeFinalAudio(
        meetingId: String,
        mic: [Float],
        system: [Float],
        mixed: [Float],
        language: String
    ) async -> [TranscriptLine] {
        let micLines = await transcribeFinalStem(
            audioData: mic,
            speaker: LocalSpeakerProfile.id,
            language: language,
            meetingId: meetingId,
            stem: "mic"
        )
        let systemLines = await transcribeFinalStem(
            audioData: system,
            speaker: "S1",
            language: language,
            meetingId: meetingId,
            stem: "system"
        )
        var lines = sortedTranscript(micLines + systemLines)

        if transcriptNeedsMixedFallback(lines: lines, totalSamples: max(mic.count, system.count)),
           !mixed.isEmpty {
            let mixedLines = await transcribeFinalStem(
                audioData: mixed,
                speaker: "S1",
                language: language,
                meetingId: meetingId,
                stem: "mixed"
            )
            if transcriptWordCount(mixedLines) > transcriptWordCount(lines) {
                lines = sortedTranscript(mixedLines)
            }
        }

        return lines
    }

    private func sortedTranscript(_ lines: [TranscriptLine]) -> [TranscriptLine] {
        lines.sorted { lhs, rhs in
            parseTimestampSeconds(lhs.timestamp) < parseTimestampSeconds(rhs.timestamp)
        }
    }

    private func transcriptNeedsMixedFallback(lines: [TranscriptLine], totalSamples: Int) -> Bool {
        let words = transcriptWordCount(lines)
        if lines.isEmpty { return true }
        let seconds = totalSamples / 16_000
        if seconds >= 12 && words < max(4, seconds / 3) { return true }
        let quality = TranscriptQualityScorer.evaluate(
            lines: lines,
            audioDurationSeconds: TimeInterval(totalSamples) / AudioImporter.targetSampleRate
        )
        if quality.status == .failed { return true }
        let uniqueTexts = Set(lines.map { $0.body.lowercased() })
        if lines.count >= 4 && uniqueTexts.count <= lines.count / 2 { return true }
        return false
    }

    private func transcriptWordCount(_ lines: [TranscriptLine]) -> Int {
        lines.reduce(0) { $0 + $1.body.split(separator: " ").count }
    }

    private func rebuiltDetail(
        from detail: MeetingDetail,
        title: String? = nil,
        wordCount: Int? = nil,
        participants: [Participant]? = nil,
        tldr: String? = nil,
        highlights: [Highlight]? = nil,
        tasks: [ActionItem]? = nil,
        chapters: [Chapter]? = nil,
        transcript: [TranscriptLine]? = nil,
        audioURL: String? = nil,
        processing: Bool? = nil
    ) -> MeetingDetail {
        MeetingDetail(
            id: detail.id,
            title: title ?? detail.title,
            dateLong: detail.dateLong,
            timeRange: detail.timeRange,
            duration: detail.duration,
            platform: detail.platform,
            wordCount: wordCount ?? detail.wordCount,
            participants: participants ?? detail.participants,
            tldr: tldr ?? detail.tldr,
            highlights: highlights ?? detail.highlights,
            tasks: tasks ?? detail.tasks,
            chapters: chapters ?? detail.chapters,
            transcript: transcript ?? detail.transcript,
            audioURL: audioURL ?? detail.audioURL,
            processing: processing ?? detail.processing
        )
    }

    private func transcribeFinalStem(
        audioData: [Float],
        speaker: String,
        language: String,
        meetingId: String,
        stem: String
    ) async -> [TranscriptLine] {
        guard !audioData.isEmpty else { return [] }
        if FinalSTTTranscriber.isAvailable {
            do {
                let result = try await FinalSTTTranscriber.transcribe(
                    audioData: audioData,
                    speaker: speaker,
                    language: language,
                    meetingId: meetingId,
                    stem: stem
                )
                persistTranscriptRun(result.run)
                return result.lines
            } catch FinalSTTError.qualityRejected(let run) {
                persistTranscriptRun(run)
                NSLog("[NeoQuill] Final-STT Quality rejected (\(speaker)/\(stem)): \(run.quality.warnings.map(\.rawValue).joined(separator: ","))")
                return []
            } catch {
                NSLog("[NeoQuill] Final-STT Fallback auf WhisperKit (\(speaker)/\(stem)): \(error)")
            }
        }
        let model = UserDefaults.standard.stringOr(AppSettings.whisperModel, default: "openai_whisper-small")
        let lang = UserDefaults.standard.stringOr(AppSettings.language, default: language)
        _ = await transcriber.loadModel(model: model, language: lang)
        let lines = await transcriber.transcribeFull(audioData: audioData, speaker: speaker)
        let duration = TimeInterval(audioData.count) / AudioImporter.targetSampleRate
        let settings = TranscriptRunSettings(
            language: lang,
            maxContextTokens: 0,
            vadEnabled: false,
            fullJSON: false,
            chunkDurationSeconds: duration,
            overlapSeconds: 0
        )
        let run = TranscriptRun.fromLines(
            meetingId: meetingId,
            stem: stem,
            audioSampleRate: AudioImporter.targetSampleRate,
            audioDurationSeconds: duration,
            engine: TranscriptEngineInfo(name: "WhisperKit", model: model, version: nil),
            settings: settings,
            lines: lines,
            audioSha256: AudioFingerprint.sha256(samples: audioData)
        )
        persistTranscriptRun(run)
        if run.quality.status == .failed {
            NSLog("[NeoQuill] WhisperKit Quality rejected (\(speaker)/\(stem)): \(run.quality.warnings.map(\.rawValue).joined(separator: ","))")
            return []
        }
        return lines
    }

    private func persistTranscriptRun(_ run: TranscriptRun) {
        do {
            _ = try TranscriptRunStore.write(run)
        } catch {
            NSLog("[NeoQuill] Transcript-Run konnte nicht gespeichert werden: \(error)")
        }
    }

    private func detectedPlatform() -> Platform {
        switch detector.detectedApp {
        case .teams:    return .teams
        case .zoom:     return .zoom
        case .browser:  return .meet
        case .facetime, .slack, .discord, .webex, .unknown:
            return .call
        }
    }

    /// Diarisiert den System-Audio-Stream und gibt Speaker-Timeline zurück.
    /// Match gegen bekannte Sprecher (SpeakerStore) → labelt mit dem persistenten Namen
    /// statt anonymem `S1`/`S2`. Neue Embeddings werden im Store automatisch erfasst,
    /// sobald der User sie über das "Wer ist das?"-Sheet labelt.
    private func runDiarization(samples: [Float]) async -> [DiarizedSpeakerSegment] {
        do {
            let result = try await diarizer.diarize(samples)
            return result.segments.compactMap { seg in
                let duration = TimeInterval(seg.endTimeSeconds - seg.startTimeSeconds)
                guard duration >= Self.minDiarizationSegmentDuration else { return nil }
                let resolvedId: String
                let source: SpeakerIdentitySource
                let confidence: Double
                if let match = speakerStore?.bestMatch(for: seg.embedding) {
                    resolvedId = match.id
                    source = .knownVoice
                    confidence = Double(match.score)
                } else {
                    resolvedId = displaySpeakerId(for: seg.speakerId)
                    source = .diarization
                    confidence = 0.72
                }
                return DiarizedSpeakerSegment(
                    start: TimeInterval(seg.startTimeSeconds),
                    end: TimeInterval(seg.endTimeSeconds),
                    speakerId: resolvedId,
                    embedding: seg.embedding,
                    speakerSource: source,
                    confidence: confidence
                )
            }
        } catch {
            NSLog("[Recorder] Diarize failed: \(error)")
            return []
        }
    }

    static let minDiarizationSegmentDuration: TimeInterval = 1.2

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

    private func displaySpeakerId(for rawId: String) -> String {
        let trimmed = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "S1" }
        let upper = trimmed.uppercased()
        if upper.hasPrefix("S"), upper.dropFirst().allSatisfy(\.isNumber) { return upper }
        if let numeric = Int(trimmed) { return "S\(numeric + 1)" }
        let trailingDigits = String(trimmed.reversed().prefix { $0.isNumber }.reversed())
        if let numeric = Int(trailingDigits) { return "S\(numeric + 1)" }
        return upper.count <= 3 ? upper : "S1"
    }

    private func parseTimestampSeconds(_ ts: String) -> TimeInterval {
        let parts = ts.split(separator: ":")
        guard parts.count == 2,
              let m = Int(parts[0]), let s = Int(parts[1]) else { return 0 }
        return TimeInterval(m * 60 + s)
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
        let palette: [(String, UInt32)] = [
            (LocalSpeakerProfile.id, LocalSpeakerProfile.colorHex), ("S1", 0x7C8AFF), ("S2", 0xFFB340),
            ("S3", 0x409CFF), ("S4", 0xD4845A)
        ]
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
                                   colorHex: colorHex(forSpeakerId: id), spoke: spoke)
            }
            guard let entry = palette.first(where: { $0.0 == id }) else {
                return Participant(id: id, name: "Speaker \(id)", role: "Erkannt",
                                   colorHex: colorHex(forSpeakerId: id), spoke: spoke)
            }
            let name = LocalSpeakerProfile.isLocalSpeakerId(id) ? LocalSpeakerProfile.displayName : "Speaker \(id)"
            let role = LocalSpeakerProfile.isLocalSpeakerId(id) ? LocalSpeakerProfile.role : "Erkannt"
            return Participant(id: id, name: name, role: role,
                               colorHex: entry.1, spoke: spoke)
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
        let total = max(0, Int(seconds.rounded()))
        let minutes = total / 60
        let remainder = total % 60
        return "\(minutes)m \(remainder)s"
    }

    private func persistCaptionIdentities(from lines: [TranscriptLine], platform: Platform) {
        var seen: Set<String> = []
        for line in lines where line.speakerSource == .caption {
            guard !LocalSpeakerProfile.isLocalSpeakerId(line.who),
                  let displayName = line.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !displayName.isEmpty,
                  !seen.contains(line.who)
            else { continue }
            seen.insert(line.who)
            speakerStore?.upsertIdentity(
                id: line.who,
                name: displayName,
                colorHex: colorHex(forSpeakerId: line.who)
            )
            speakerStore?.upsertAlias(
                speakerId: line.who,
                alias: displayName,
                source: "caption",
                platform: platform,
                externalId: nil
            )
        }
    }

    private func persistPlatformIdentities(from lines: [TranscriptLine], platform: Platform) {
        var seen: Set<String> = []
        for line in lines where line.speakerSource == .platformApi {
            guard !LocalSpeakerProfile.isLocalSpeakerId(line.who),
                  let displayName = line.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !displayName.isEmpty,
                  !seen.contains(line.who)
            else { continue }
            seen.insert(line.who)
            speakerStore?.upsertIdentity(
                id: line.who,
                name: displayName,
                colorHex: colorHex(forSpeakerId: line.who)
            )
            speakerStore?.upsertAlias(
                speakerId: line.who,
                alias: displayName,
                source: "platform",
                platform: platform,
                externalId: line.who
            )
        }
    }

    private func colorHex(forSpeakerId id: String) -> UInt32 {
        if LocalSpeakerProfile.isLocalSpeakerId(id) { return LocalSpeakerProfile.colorHex }
        let fixed: [String: UInt32] = [
            "S1": 0x7C8AFF,
            "S2": 0xFFB340,
            "S3": 0x409CFF,
            "S4": 0xD4845A,
        ]
        if let color = fixed[id] { return color }
        let colors: [UInt32] = [0x7C8AFF, 0xFFB340, 0x409CFF, 0xD4845A, 0xFF6259, 0x2EAB73]
        let checksum = id.unicodeScalars.reduce(UInt32(0)) { partial, scalar in
            partial &+ scalar.value
        }
        return colors[Int(checksum % UInt32(colors.count))]
    }

    private func generateTitle(from lines: [TranscriptLine], started: Date) -> String {
        if let first = lines.first?.body, !first.isEmpty {
            let prefix = first.split(separator: " ").prefix(7).joined(separator: " ")
            return prefix
        }
        return "Aufnahme \(Self.timeFormatter.string(from: started))"
    }

    private func formatDurationShort(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let remainder = Int(seconds) % 60
        if minutes == 0 { return "\(remainder)s" }
        return "\(minutes)m \(remainder)s"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dateShortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd. MMM."
        return f
    }()

    private static let dateLongFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE, dd. MMMM"
        return f
    }()

    // MARK: - Internal wiring

    private func wireTranscriber() {
        // Post-Recording-Architektur — Live-Callbacks bewusst NICHT mehr verdrahtet.
        // Whisper laeuft beim Stop einmal pro Stem (Mic + Sys) ueber das volle
        // Float-Array statt chunk-weise. Vorteile: keine RMS-Drops bei leisem
        // Mic-Pegel, kein isBusy-Lock-Konflikt zwischen Streams, mehr Kontext
        // fuer Whisper (-> bessere Transkription).
    }

    private func wireAudioCapture() {
        // Mic + Sys werden in AudioCapture in `micRecording`/`sysRecording`
        // gepuffert. Wir lassen die Live-Callbacks bewusst leer — der finale
        // Whisper-Pass laeuft erst in `persistMeeting` ueber `collectFinalAudio`.
        audioCapture.onMicChunk = nil
        audioCapture.onSysChunk = nil

        // UI-Header bekommt den echten Mic-Namen statt "Built-in Mic" hardcoded.
        deviceCancellable = audioCapture.$currentMicName
            .receive(on: DispatchQueue.main)
            .sink { [weak self] name in
                guard let self, !name.isEmpty else { return }
                self.device = name
            }

        // Live-Audio-Level fuer die Pille (Bars im Recording-Modus).
        levelCancellable = audioCapture.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.audioLevel = level
            }
    }

    private func wireCaptionCapture() {
        captionStateCancellable = captionCapture.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] captureState in
                self?.captionStatusText = captureState.label
            }
        captionEventsCancellable = captionCapture.$events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] events in
                self?.captionEventCount = events.count
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

    static func formatTimestamp(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private func friendlyModelLabel(_ raw: String) -> String {
        switch raw {
        case "openai_whisper-tiny":   return "Whisper Tiny"
        case "openai_whisper-base":   return "Whisper Base"
        case "openai_whisper-small":  return "Whisper Small"
        case "openai_whisper-medium": return "Whisper Medium"
        default: return raw
        }
    }
}
