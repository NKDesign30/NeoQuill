import Foundation

/// Transkribiert die Audio-Stems eines Meetings zu einer sortierten
/// Transkript-Zeilen-Liste.
///
/// Kapselt die Multi-Stem-Orchestrierung (mic + system, mit Mixed-Fallback),
/// die Qualitäts-/Fallback-Heuristik und die WhisperKit-Rückfallebene — alles
/// Code, der früher als private Methoden im `RecordingController` (God-Object)
/// lag und an vier Call-Sites dupliziert aufgerufen wurde.
///
/// Interface: Stems rein, Zeilen raus. Der Aufrufer muss nichts über die drei
/// sequenziellen Whisper-Pässe, die Fallback-Entscheidung oder die
/// Qualitätsbewertung wissen.
struct MeetingTranscriber {
    /// WhisperKit-Rückfallebene, wenn `FinalSTTTranscriber` (whisper.cpp) nicht
    /// verfügbar ist.
    let whisperKitFallback: LiveTranscriber

    /// Transkribiert mic- und system-Stem, fällt bei dünnem/schlechtem Ergebnis
    /// auf den gemischten Stem zurück und gibt die zeitlich sortierten Zeilen.
    func transcribe(
        meetingId: String,
        mic: [Float],
        system: [Float],
        mixed: [Float],
        language: String
    ) async -> [TranscriptLine] {
        let micLines = await transcribeStem(
            audioData: mic,
            speaker: LocalSpeakerProfile.id,
            language: language,
            meetingId: meetingId,
            stem: "mic"
        )
        let systemLines = await transcribeStem(
            audioData: system,
            speaker: "S1",
            language: language,
            meetingId: meetingId,
            stem: "system"
        )
        var lines = sortedTranscript(micLines + systemLines)

        if needsMixedFallback(lines: lines, totalSamples: max(mic.count, system.count)),
           !mixed.isEmpty {
            let mixedLines = await transcribeStem(
                audioData: mixed,
                speaker: "S1",
                language: language,
                meetingId: meetingId,
                stem: "mixed"
            )
            if wordCount(mixedLines) > wordCount(lines) {
                lines = sortedTranscript(mixedLines)
            }
        }

        return lines
    }

    /// Entscheidet, ob der gemischte Stem als Fallback transkribiert werden muss.
    /// Der Scorer misst (Wörter, Wiederholung, Status), `TranscriptQualityPolicy`
    /// entscheidet — keine eigene Schwelle mehr. Internal für Tests.
    func needsMixedFallback(lines: [TranscriptLine], totalSamples: Int) -> Bool {
        let audioSeconds = TimeInterval(totalSamples) / AudioImporter.targetSampleRate
        let report = TranscriptQualityScorer.evaluate(lines: lines, audioDurationSeconds: audioSeconds)
        return TranscriptQualityPolicy.needsFallback(report, audioSeconds: Int(audioSeconds))
    }

    func wordCount(_ lines: [TranscriptLine]) -> Int {
        lines.reduce(0) { $0 + $1.body.split(separator: " ").count }
    }

    private func transcribeStem(
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
                persistRun(result.run)
                return result.lines
            } catch FinalSTTError.qualityRejected(let run) {
                persistRun(run)
                NSLog("[NeoQuill] Final-STT Quality rejected (\(speaker)/\(stem)): \(run.quality.warnings.map(\.rawValue).joined(separator: ","))")
                return []
            } catch {
                NSLog("[NeoQuill] Final-STT Fallback auf WhisperKit (\(speaker)/\(stem)): \(error)")
            }
        }
        let model = UserDefaults.standard.stringOr(AppSettings.whisperModel, default: "openai_whisper-small")
        let lang = UserDefaults.standard.stringOr(AppSettings.language, default: language)
        _ = await whisperKitFallback.loadModel(model: model, language: lang)
        let lines = await whisperKitFallback.transcribeFull(audioData: audioData, speaker: speaker)
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
        persistRun(run)
        if run.quality.status == .failed {
            NSLog("[NeoQuill] WhisperKit Quality rejected (\(speaker)/\(stem)): \(run.quality.warnings.map(\.rawValue).joined(separator: ","))")
            return []
        }
        return lines
    }

    private func sortedTranscript(_ lines: [TranscriptLine]) -> [TranscriptLine] {
        lines.sorted { lhs, rhs in
            parseTimestampSeconds(lhs.timestamp) < parseTimestampSeconds(rhs.timestamp)
        }
    }

    private func persistRun(_ run: TranscriptRun) {
        do {
            _ = try TranscriptRunStore.write(run)
        } catch {
            NSLog("[NeoQuill] Transcript-Run konnte nicht gespeichert werden: \(error)")
        }
    }

    private func parseTimestampSeconds(_ ts: String) -> TimeInterval {
        let parts = ts.split(separator: ":")
        guard parts.count == 2,
              let m = Int(parts[0]), let s = Int(parts[1]) else { return 0 }
        return TimeInterval(m * 60 + s)
    }
}
