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
    @Published private(set) var hasMicPermission: Bool = false
    /// Live-Audio-Level (RMS, 0..~1) — UI-Header/Pille zeigt Live-Bars.
    @Published private(set) var audioLevel: Float = 0

    // MARK: - Dependencies

    private let audioCapture = AudioCapture()
    /// Single Whisper-Instance fuer Post-Recording. Mic- und Sys-Stem laufen
    /// sequenziell durch. Ein Modell = halbe RAM-Last + kein ANE-Konflikt.
    private let transcriber = LiveTranscriber()
    private let permissions = PermissionGate()
    private let diarizer = SpeakerDiarizer()
    let detector = MeetingDetector()
    weak var store: MeetingStore?
    weak var speakerStore: SpeakerStore?

    private var detectorCancellable: AnyCancellable?
    private var deviceCancellable: AnyCancellable?
    private var levelCancellable: AnyCancellable?
    private var autoDetectActive = false

    private var elapsedTimer: AnyCancellable?
    private var startedAt: Date?
    private var micChunkOffset: TimeInterval = 0
    private var sysChunkOffset: TimeInterval = 0

    // MARK: - Lifecycle

    init() {
        wireTranscriber()
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
        modelLabel = FinalSTTTranscriber.isAvailable ? FinalSTTTranscriber.label : "WhisperKit ANE"
        if !FinalSTTTranscriber.isAvailable {
            let model = UserDefaults.standard.stringOr(AppSettings.whisperModel, default: "openai_whisper-small")
            let lang  = UserDefaults.standard.stringOr(AppSettings.language, default: "de")
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
        let lang  = UserDefaults.standard.stringOr(AppSettings.language,     default: "de")
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
            await self?.persistMeeting(meetingId: meetingId, runtime: runtime, started: started)
        }
    }

    func reprocessMeeting(_ meetingId: String) {
        Task { [weak self] in
            await self?.reprocessMeetingAsync(meetingId)
        }
    }

    /// Setzt direkt nach Stop ein Provisional-Meeting in den Store, damit
    /// AppState in Detail-View wechselt waehrend die echte Transkription laeuft.
    private func insertProvisionalMeeting(id: String, runtime: TimeInterval, started: Date) {
        guard let store else { return }
        let durationShort = formatDurationShort(runtime)
        let timeShort = Self.timeFormatter.string(from: started)
        let dateShort = Self.dateShortFormatter.string(from: started)
        let dateLong = Self.dateLongFormatter.string(from: started)
        let endDate = started.addingTimeInterval(runtime)
        let timeRange = "\(timeShort) – \(Self.timeFormatter.string(from: endDate))"
        let provisionalTitle = "Aufnahme \(timeShort)"
        let participants: [Participant] = [
            .init(id: "NK", name: "Niko Knez", role: "NK Design", colorHex: 0x2EAB73, spoke: durationShort)
        ]

        let summary = MeetingSummary(
            id: id, title: provisionalTitle, date: dateShort, time: timeShort,
            duration: durationShort, platform: detectedPlatform(), wordCount: 0,
            group: "Diesen Monat", participantIds: ["NK"], unread: true
        )
        let provisional = MeetingDetail(
            id: id, title: provisionalTitle, dateLong: dateLong, timeRange: timeRange,
            duration: durationShort, platform: detectedPlatform(), wordCount: 0,
            participants: participants,
            tldr: "Wird transkribiert…",
            highlights: [], tasks: [], chapters: [],
            transcript: [], audioURL: nil, processing: true
        )
        store.insert(summary: summary, detail: provisional)
    }

    private func persistMeeting(meetingId: String, runtime: TimeInterval, started: Date) async {
        guard let store else { return }
        let id = meetingId
        let durationShort = formatDurationShort(runtime)
        let timeShort = Self.timeFormatter.string(from: started)
        let dateLong = Self.dateLongFormatter.string(from: started)
        let endDate = started.addingTimeInterval(runtime)
        let timeRange = "\(timeShort) – \(Self.timeFormatter.string(from: endDate))"

        let captured = audioCapture.collectFinalAudio()
        let audioURL = persistCapturedAudio(meetingId: id, captured: captured)

        let lang = UserDefaults.standard.stringOr(AppSettings.language, default: "de")
        statusText = FinalSTTTranscriber.isAvailable ? "Final-STT läuft" : "Transkribiere"

        var allLines = await transcribeFinalAudio(
            mic: captured.mic,
            system: captured.sys,
            mixed: captured.mixed,
            language: lang
        )
        let provisionalTitle = generateTitle(from: allLines, started: started)
        var participants: [Participant] = [
            .init(id: "NK", name: "Niko Knez", role: "NK Design", colorHex: 0x2EAB73, spoke: durationShort)
        ]

        // FluidAudio-Diarize auf System-Audio (>= 5s) — labelt S1 ggf. um in S2/S3
        // bzw. matcht gegen bekannte Speaker (Re-ID via SpeakerStore).
        var pendingEmbeddings: [String: [Float]] = [:]
        if UserDefaults.standard.boolOr(AppSettings.speakerDiarization, default: false), diarizer.isReady {
            if captured.sys.count > 16_000 * 5 {
                statusText = "Erkenne Sprecher"
                let diar = await runDiarization(samples: captured.sys)
                allLines = mergeSpeakers(lines: allLines, diarization: diar)
                participants = collectParticipants(lines: allLines, baseDuration: durationShort)
                for entry in diar {
                    if pendingEmbeddings[entry.speakerId] == nil {
                        pendingEmbeddings[entry.speakerId] = entry.embedding
                    }
                }
            }
        }

        let enrichedLines = allLines
        let wordCount = enrichedLines.reduce(0) { $0 + $1.body.split(separator: " ").count }

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
            transcript: enrichedLines,
            audioURL: nil,
            processing: true
        )
        store.updateDetail(transcribed, summaryTitle: provisionalTitle)
        statusText = "KI verarbeitet"

        // Embeddings frisch entdeckter Speaker für später vorhalten — UI-Labeling-Sheet
        // greift darauf zu, wenn Niko "S1 = Thorsten" tippt.
        for (speakerId, embedding) in pendingEmbeddings where !embedding.isEmpty {
            self.lastEmbeddings[speakerId] = embedding
        }

        // 2. Async: WAV speichern + Claude-Summary holen, dann Detail updaten.
        let result = await PostProcessor.process(
            meetingId: id,
            mixedSamples: [],
            transcriptLines: enrichedLines,
            locale: lang
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
            transcript: enrichedLines,
            audioURL: result.audioURL?.path ?? audioURL?.path,
            processing: false
        )

        store.updateDetail(
            finalDetail,
            summaryTitle: result.title.isEmpty ? nil : result.title
        )
    }

    private func reprocessMeetingAsync(_ meetingId: String) async {
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
        let lang = UserDefaults.standard.stringOr(AppSettings.language, default: "de")
        var allLines = await transcribeFinalAudio(
            mic: storedAudio.mic,
            system: storedAudio.system,
            mixed: storedAudio.mixed,
            language: lang
        )

        var participants = allLines.isEmpty
            ? detail.participants
            : collectParticipants(lines: allLines, baseDuration: detail.duration)

        if UserDefaults.standard.boolOr(AppSettings.speakerDiarization, default: false),
           diarizer.isReady,
           storedAudio.system.count > 16_000 * 5 {
            statusText = "Erkenne Sprecher"
            let diar = await runDiarization(samples: storedAudio.system)
            allLines = mergeSpeakers(lines: allLines, diarization: diar)
            participants = collectParticipants(lines: allLines, baseDuration: detail.duration)
        }

        let wordCount = allLines.reduce(0) { $0 + $1.body.split(separator: " ").count }
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
                audioURL: storedAudio.audioURL?.path ?? detail.audioURL,
                processing: false
            )
            store.updateDetail(empty, summaryTitle: empty.title)
            statusText = "Bereit"
            return
        }

        let transcribed = rebuiltDetail(
            from: detail,
            title: generateTitle(from: allLines, started: Date()),
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
            transcriptLines: allLines,
            locale: lang
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
            audioURL: storedAudio.audioURL?.path ?? detail.audioURL,
            processing: false
        )
        store.updateDetail(final, summaryTitle: result.title.isEmpty ? nil : result.title)
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
        captured: (mic: [Float], sys: [Float], mixed: [Float])
    ) -> URL? {
        do {
            let mixURL = try AudioWriter.persist(id: meetingId, stem: .mix, samples: captured.mixed)
            _ = try AudioWriter.persist(id: meetingId, stem: .mic, samples: captured.mic)
            _ = try AudioWriter.persist(id: meetingId, stem: .system, samples: captured.sys)
            return mixURL
        } catch {
            NSLog("[RecordingController] Stem persist failed: \(error)")
            return nil
        }
    }

    /// Embeddings der letzten Aufnahme — verfügbar für das Speaker-Labeling-Sheet.
    private(set) var lastEmbeddings: [String: [Float]] = [:]

    /// Niko labelt "S1 → Thorsten" → SpeakerStore + alle bekannten Aufnahmen rückwirkend.
    func labelSpeaker(internalId: String, name: String, colorHex: UInt32, meetingId: String?) {
        let embedding = lastEmbeddings[internalId] ?? []
        let canonicalId = canonicalize(name: name)
        if !embedding.isEmpty {
            speakerStore?.upsert(id: canonicalId, name: name, embedding: embedding, colorHex: colorHex)
        }
        if let meetingId {
            store?.relabelSpeaker(
                meetingId: meetingId,
                from: internalId,
                to: canonicalId,
                name: name,
                colorHex: colorHex
            )
        }
    }

    private func canonicalize(name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let initials = trimmed.split(separator: " ").compactMap { $0.first.map(String.init) }.joined()
        return initials.isEmpty ? trimmed : initials.uppercased()
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
        mic: [Float],
        system: [Float],
        mixed: [Float],
        language: String
    ) async -> [TranscriptLine] {
        let micLines = await transcribeFinalStem(audioData: mic, speaker: "NK", language: language)
        let systemLines = await transcribeFinalStem(audioData: system, speaker: "S1", language: language)
        var lines = sortedTranscript(micLines + systemLines)

        if transcriptNeedsMixedFallback(lines: lines, totalSamples: max(mic.count, system.count)),
           !mixed.isEmpty {
            let mixedLines = await transcribeFinalStem(audioData: mixed, speaker: "S1", language: language)
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

    private func transcribeFinalStem(audioData: [Float], speaker: String, language: String) async -> [TranscriptLine] {
        guard !audioData.isEmpty else { return [] }
        if FinalSTTTranscriber.isAvailable {
            do {
                return try await FinalSTTTranscriber.transcribe(
                    audioData: audioData,
                    speaker: speaker,
                    language: language
                )
            } catch {
                print("[NeoQuill] Final-STT Fallback auf WhisperKit (\(speaker)): \(error)")
            }
        }
        let model = UserDefaults.standard.stringOr(AppSettings.whisperModel, default: "openai_whisper-small")
        let lang = UserDefaults.standard.stringOr(AppSettings.language, default: language)
        _ = await transcriber.loadModel(model: model, language: lang)
        return await transcriber.transcribeFull(audioData: audioData, speaker: speaker)
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
    /// sobald Niko sie über das "Wer ist das?"-Sheet labelt.
    private func runDiarization(samples: [Float]) async -> [(start: TimeInterval, end: TimeInterval, speakerId: String, embedding: [Float])] {
        do {
            let result = try await diarizer.diarize(samples)
            return result.segments.map { seg in
                let resolvedId: String
                if let match = speakerStore?.bestMatch(for: seg.embedding) {
                    resolvedId = match.id
                } else {
                    resolvedId = displaySpeakerId(for: seg.speakerId)
                }
                return (
                    TimeInterval(seg.startTimeSeconds),
                    TimeInterval(seg.endTimeSeconds),
                    resolvedId,
                    seg.embedding
                )
            }
        } catch {
            NSLog("[Recorder] Diarize failed: \(error)")
            return []
        }
    }

    /// Match TranscriptLines (mit Mono-Timestamps) auf Diarize-Segments.
    /// Source-Aware: Mic-Lines (`who == "NK"`) bleiben **immer** NK, weil sie
    /// bereits aus dem Mic-Stream kommen — der ist garantiert Niko. Nur Lines
    /// aus dem System-Audio-Stream werden mit Speaker-IDs aus Diarization
    /// geupdated. Pattern aus `tonton-golio/meeting-recorder`: separate Stems
    /// → keine Cross-Source-Verwechslung.
    private func mergeSpeakers(
        lines: [TranscriptLine],
        diarization: [(start: TimeInterval, end: TimeInterval, speakerId: String, embedding: [Float])]
    ) -> [TranscriptLine] {
        guard !diarization.isEmpty else { return lines }
        return lines.map { line in
            // Mic-Stream-Lines unangetastet lassen — der Mic ist immer Niko.
            guard line.who != "NK" else { return line }

            let secs = parseTimestampSeconds(line.timestamp)
            if let match = diarization.first(where: { secs >= $0.start && secs <= $0.end }) {
                return TranscriptLine(
                    who: match.speakerId,
                    timestamp: line.timestamp,
                    body: line.body,
                    highlight: line.highlight
                )
            }
            return line
        }
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
        baseDuration: String
    ) -> [Participant] {
        let speakerIds = Set(lines.map(\.who)).sorted { lhs, rhs in
            if lhs == "NK" { return true }
            if rhs == "NK" { return false }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        let palette: [(String, UInt32)] = [
            ("NK", 0x2EAB73), ("S1", 0x7C8AFF), ("S2", 0xFFB340),
            ("S3", 0x409CFF), ("S4", 0xD4845A)
        ]
        return speakerIds.compactMap { id in
            if let known = speakerStore?.speaker(for: id) {
                return Participant(id: id, name: known.name, role: "Bekannt",
                                   colorHex: known.colorHex, spoke: baseDuration)
            }
            guard let entry = palette.first(where: { $0.0 == id }) else {
                return Participant(id: id, name: "Speaker \(id)", role: "Erkannt",
                                   colorHex: 0x8E8E8A, spoke: baseDuration)
            }
            let name = id == "NK" ? "Niko Knez" : "Speaker \(id)"
            let role = id == "NK" ? "NK Design" : "Erkannt"
            return Participant(id: id, name: name, role: role,
                               colorHex: entry.1, spoke: baseDuration)
        }
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
