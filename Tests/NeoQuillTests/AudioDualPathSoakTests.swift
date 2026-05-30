import AVFoundation
import XCTest
@testable import NeoQuill

final class AudioDualPathSoakTests: XCTestCase {
    private struct DualPathBuffers {
        var micASR: [Float] = []
        var systemASR: [Float] = []
        var micHQ: [Float] = []
        var systemHQ: [Float] = []

        var mixedASR: [Float] {
            AudioCapture.alignedMix(
                mic: micASR,
                micOffset: nil,
                system: systemASR,
                systemOffset: nil,
                sampleRate: 16_000
            )
        }

        var retainedSampleBytes: Int {
            (micASR.count + systemASR.count + mixedASR.count + micHQ.count + systemHQ.count) * MemoryLayout<Float>.size
        }
    }

    private struct PersistedURLs {
        let mix: URL
        let mic: URL
        let system: URL
        let hq: URL

        func removeAll() {
            try? FileManager.default.removeItem(at: mix)
            try? FileManager.default.removeItem(at: mic)
            try? FileManager.default.removeItem(at: system)
            try? FileManager.default.removeItem(at: hq)
        }
    }

    func testLongDualPathSoakPersists48kStereoArchiveAnd16kASRStems() throws {
        let seconds = 120
        let framesPerChunk = 2_400
        let chunks = seconds * 48_000 / framesPerChunk
        let expectedASRFrames = seconds * 16_000
        let expectedHQFrames = seconds * 48_000

        var buffers = DualPathBuffers()
        let micASRConverter = try XCTUnwrap(PCMStreamConverter(targetSampleRate: 16_000))
        let micHQConverter = try XCTUnwrap(PCMStreamConverter(targetSampleRate: 48_000))
        let systemASRConverter = try XCTUnwrap(PCMStreamConverter(targetSampleRate: 16_000))
        let systemHQConverter = try XCTUnwrap(PCMStreamConverter(targetSampleRate: 48_000))
        var micPhase = 0.0
        var systemPhase = 0.0

        for _ in 0..<chunks {
            let mic = monoBuffer(
                sampleRate: 48_000,
                frames: framesPerChunk,
                frequency: 181,
                amplitude: 0.28,
                phase: &micPhase
            )
            let system = interleavedStereoBuffer(
                sampleRate: 48_000,
                frames: framesPerChunk,
                leftFrequency: 317,
                rightFrequency: 421,
                amplitude: 0.22,
                phase: &systemPhase
            )

            append(micASRConverter.convert(mic), to: &buffers.micASR)
            append(micHQConverter.convert(mic), to: &buffers.micHQ)
            append(systemASRConverter.convert(system), to: &buffers.systemASR)
            append(systemHQConverter.convert(system), to: &buffers.systemHQ)
        }

        XCTAssertEqual(buffers.micASR.count, expectedASRFrames, accuracy: 4_096)
        XCTAssertEqual(buffers.systemASR.count, expectedASRFrames, accuracy: 4_096)
        XCTAssertEqual(buffers.micHQ.count, expectedHQFrames, accuracy: 1)
        XCTAssertEqual(buffers.systemHQ.count, expectedHQFrames, accuracy: 1)
        XCTAssertLessThan(buffers.retainedSampleBytes, 96 * 1_024 * 1_024)

        let id = "dual-path-soak-\(UUID().uuidString)"
        let urls = PersistedURLs(
            mix: AudioWriter.url(id: id, stem: .mix),
            mic: AudioWriter.url(id: id, stem: .mic),
            system: AudioWriter.url(id: id, stem: .system),
            hq: AudioWriter.url(id: id, stem: .hq)
        )
        defer { urls.removeAll() }

        let mixed = buffers.mixedASR
        XCTAssertEqual(mixed.count, expectedASRFrames, accuracy: 4_096)

        let mixURL = try XCTUnwrap(AudioWriter.persist(id: id, stem: .mix, samples: mixed))
        let micURL = try XCTUnwrap(AudioWriter.persist(id: id, stem: .mic, samples: buffers.micASR))
        let systemURL = try XCTUnwrap(AudioWriter.persist(id: id, stem: .system, samples: buffers.systemASR))
        let hqURL = try XCTUnwrap(AudioWriter.persistStereo(id: id, stem: .hq, left: buffers.micHQ, right: buffers.systemHQ))

        assertMonoASRFile(mixURL, expectedFrames: expectedASRFrames)
        assertMonoASRFile(micURL, expectedFrames: expectedASRFrames)
        assertMonoASRFile(systemURL, expectedFrames: expectedASRFrames)
        assertStereoHQFile(hqURL, expectedFrames: expectedHQFrames)

        let hqFile = try AVAudioFile(forReading: hqURL)
        let hqDuration = Double(hqFile.length) / hqFile.fileFormat.sampleRate
        let correction = AudioPlaybackPitchGuard.decide(fileDuration: hqDuration, expectedDuration: Double(seconds))
        XCTAssertFalse(correction.corrected)

        let preview = try readStereoPreview(hqURL, frames: 4_096)
        XCTAssertGreaterThan(meanAbsoluteDifference(preview.left, preview.right), 0.02)
    }

    func testLongStreamingConvertersPreserveSampleRateRatiosWithoutRetainingAudio() throws {
        let seconds = 600
        let framesPerChunk = 1_024
        let chunks = seconds * 48_000 / framesPerChunk
        let expectedInputFrames = chunks * framesPerChunk
        let expectedASRFrames = Double(expectedInputFrames) / 3.0
        let asrConverter = try XCTUnwrap(PCMStreamConverter(targetSampleRate: 16_000))
        let hqConverter = try XCTUnwrap(PCMStreamConverter(targetSampleRate: 48_000))
        var phase = 0.0
        var asrFrames = 0
        var hqFrames = 0

        for _ in 0..<chunks {
            let buffer = interleavedStereoBuffer(
                sampleRate: 48_000,
                frames: framesPerChunk,
                leftFrequency: 233,
                rightFrequency: 311,
                amplitude: 0.2,
                phase: &phase
            )
            asrFrames += asrConverter.convert(buffer)?.count ?? 0
            hqFrames += hqConverter.convert(buffer)?.count ?? 0
        }

        XCTAssertEqual(Double(asrFrames), expectedASRFrames, accuracy: 4_096)
        XCTAssertEqual(hqFrames, expectedInputFrames)
    }

    func testSampleRateInvariantsStaySplitBetweenArchiveAndASR() throws {
        XCTAssertEqual(AudioImporter.targetSampleRate, 16_000)
        XCTAssertEqual(RecordingAudioStem.hq.suffix, ".hq")
        XCTAssertEqual(RecordingAudioStem.mix.suffix, "")
        XCTAssertEqual(RecordingAudioStem.mic.suffix, ".mic")
        XCTAssertEqual(RecordingAudioStem.system.suffix, ".system")

        let id = "sample-rate-invariant-\(UUID().uuidString)"
        let urls = PersistedURLs(
            mix: AudioWriter.url(id: id, stem: .mix),
            mic: AudioWriter.url(id: id, stem: .mic),
            system: AudioWriter.url(id: id, stem: .system),
            hq: AudioWriter.url(id: id, stem: .hq)
        )
        defer { urls.removeAll() }

        let mono = sineSamples(sampleRate: 16_000, seconds: 1, frequency: 220, amplitude: 0.25)
        let stereoLeft = sineSamples(sampleRate: 48_000, seconds: 1, frequency: 220, amplitude: 0.25)
        let stereoRight = sineSamples(sampleRate: 48_000, seconds: 1, frequency: 330, amplitude: 0.25)

        let mixURL = try XCTUnwrap(AudioWriter.persist(id: id, stem: .mix, samples: mono))
        let hqURL = try XCTUnwrap(AudioWriter.persistStereo(id: id, stem: .hq, left: stereoLeft, right: stereoRight))

        assertMonoASRFile(mixURL, expectedFrames: 16_000)
        assertStereoHQFile(hqURL, expectedFrames: 48_000)
    }

    func testCaptureEntryPointsKeepDualPathRatesAndOrderingConsistent() throws {
        let audioCapture = try sourceText("Sources/NeoQuill/Services/AudioCapture.swift")
        let processTap = try sourceText("Sources/NeoQuill/Services/ProcessAudioTap.swift")
        let sckCapture = try sourceText("Sources/NeoQuill/Services/SCKAudioCapture.swift")
        let finalSTT = try sourceText("Sources/NeoQuill/Services/FinalSTTTranscriber.swift")
        let diarizer = try sourceText("Sources/NeoQuill/Services/SpeakerDiarizer.swift")

        for source in [audioCapture, processTap, sckCapture] {
            XCTAssertTrue(source.contains("PCMStreamConverter(targetSampleRate: 16_000)"))
            XCTAssertTrue(source.contains("PCMStreamConverter(targetSampleRate: 48_000)"))
        }
        XCTAssertTrue(finalSTT.contains("private static let sampleRate: Double = 16_000"))
        XCTAssertTrue(diarizer.contains("sampleRate: 16_000"))

        assertOrdering(
            in: audioCapture,
            first: "self.micHQConverter?.convert(pcmBuffer)",
            second: "self.micASRConverter?.convert(pcmBuffer)"
        )
        assertOrdering(
            in: processTap,
            first: "hqConverter?.convert(pcmBuffer)",
            second: "asrConverter?.convert(pcmBuffer)"
        )
        assertOrdering(
            in: sckCapture,
            first: "hqConverter?.convert(pcmBuffer)",
            second: "resampleTo16kHzMono(pcmBuffer)"
        )
    }

    func testFortyFourPointOneKMicInputStillProduces16kASRAnd48kHQDurations() throws {
        let seconds = 180
        let framesPerChunk = 4_410
        let chunks = seconds * 44_100 / framesPerChunk
        let expectedASRFrames = seconds * 16_000
        let expectedHQFrames = seconds * 48_000
        let asrConverter = try XCTUnwrap(PCMStreamConverter(targetSampleRate: 16_000))
        let hqConverter = try XCTUnwrap(PCMStreamConverter(targetSampleRate: 48_000))
        var phase = 0.0
        var asrFrames = 0
        var hqFrames = 0

        for _ in 0..<chunks {
            let buffer = monoBuffer(
                sampleRate: 44_100,
                frames: framesPerChunk,
                frequency: 190,
                amplitude: 0.25,
                phase: &phase
            )
            asrFrames += asrConverter.convert(buffer)?.count ?? 0
            hqFrames += hqConverter.convert(buffer)?.count ?? 0
        }

        XCTAssertEqual(asrFrames, expectedASRFrames, accuracy: 4_096)
        XCTAssertEqual(hqFrames, expectedHQFrames, accuracy: 8_192)
    }

    private func monoBuffer(
        sampleRate: Double,
        frames: Int,
        frequency: Double,
        amplitude: Float,
        phase: inout Double
    ) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        let increment = 2.0 * Double.pi * frequency / sampleRate
        let channel = buffer.floatChannelData![0]
        for index in 0..<frames {
            channel[index] = Float(sin(phase)) * amplitude
            phase += increment
        }
        return buffer
    }

    private func interleavedStereoBuffer(
        sampleRate: Double,
        frames: Int,
        leftFrequency: Double,
        rightFrequency: Double,
        amplitude: Float,
        phase: inout Double
    ) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: true
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        let audioBuffer = buffer.mutableAudioBufferList.pointee.mBuffers
        let samples = audioBuffer.mData!.assumingMemoryBound(to: Float.self)
        let leftIncrement = 2.0 * Double.pi * leftFrequency / sampleRate
        let rightIncrement = 2.0 * Double.pi * rightFrequency / sampleRate
        for index in 0..<frames {
            samples[index * 2] = Float(sin(phase)) * amplitude
            samples[index * 2 + 1] = Float(sin(phase * rightIncrement / leftIncrement)) * amplitude
            phase += leftIncrement
        }
        return buffer
    }

    private func sineSamples(
        sampleRate: Double,
        seconds: Int,
        frequency: Double,
        amplitude: Float
    ) -> [Float] {
        let frames = Int(sampleRate) * seconds
        let increment = 2.0 * Double.pi * frequency / sampleRate
        return (0..<frames).map { index in
            Float(sin(Double(index) * increment)) * amplitude
        }
    }

    private func append(_ samples: [Float]?, to destination: inout [Float]) {
        guard let samples, !samples.isEmpty else { return }
        destination.append(contentsOf: samples)
    }

    private func sourceText(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func assertOrdering(
        in source: String,
        first: String,
        second: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let firstRange = source.range(of: first), let secondRange = source.range(of: second) else {
            XCTFail("Missing expected source markers", file: file, line: line)
            return
        }
        XCTAssertLessThan(firstRange.lowerBound, secondRange.lowerBound, file: file, line: line)
    }

    private func assertMonoASRFile(_ url: URL, expectedFrames: Int, file: StaticString = #filePath, line: UInt = #line) {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            XCTAssertEqual(audioFile.fileFormat.sampleRate, 16_000, accuracy: 0.1, file: file, line: line)
            XCTAssertEqual(audioFile.fileFormat.channelCount, 1, file: file, line: line)
            XCTAssertEqual(audioFile.length, AVAudioFramePosition(expectedFrames), accuracy: 4_096, file: file, line: line)
        } catch {
            XCTFail("Could not read ASR file \(url.lastPathComponent): \(error)", file: file, line: line)
        }
    }

    private func assertStereoHQFile(_ url: URL, expectedFrames: Int, file: StaticString = #filePath, line: UInt = #line) {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            XCTAssertEqual(audioFile.fileFormat.sampleRate, 48_000, accuracy: 0.1, file: file, line: line)
            XCTAssertEqual(audioFile.fileFormat.channelCount, 2, file: file, line: line)
            XCTAssertEqual(audioFile.length, AVAudioFramePosition(expectedFrames), accuracy: 1, file: file, line: line)
        } catch {
            XCTFail("Could not read HQ file \(url.lastPathComponent): \(error)", file: file, line: line)
        }
    }

    private func readStereoPreview(_ url: URL, frames: Int) throws -> (left: [Float], right: [Float]) {
        let file = try AVAudioFile(forReading: url)
        let frameCount = min(AVAudioFrameCount(frames), AVAudioFrameCount(file.length))
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount)!
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData, buffer.format.channelCount >= 2 else {
            return ([], [])
        }
        let count = Int(buffer.frameLength)
        return (
            Array(UnsafeBufferPointer(start: channels[0], count: count)),
            Array(UnsafeBufferPointer(start: channels[1], count: count))
        )
    }

    private func meanAbsoluteDifference(_ lhs: [Float], _ rhs: [Float]) -> Float {
        let count = min(lhs.count, rhs.count)
        guard count > 0 else { return 0 }
        var total: Float = 0
        for index in 0..<count {
            total += abs(lhs[index] - rhs[index])
        }
        return total / Float(count)
    }
}
