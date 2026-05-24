import AVFoundation
import XCTest
@testable import NeoQuill

final class AudioPlaybackFileCorrectorTests: XCTestCase {
    func testRenderCorrectedCopyStretchesShortAudioToExpectedDuration() throws {
        let id = "playback-corrector-\(UUID().uuidString)"
        let originalURL = AudioWriter.url(id: id, stem: .mix)
        defer { try? FileManager.default.removeItem(at: originalURL) }

        let samples = (0..<1_600).map { index in
            Float(sin(Double(index) * 0.03)) * 0.25
        }
        let writtenURL = try XCTUnwrap(AudioWriter.persist(id: id, stem: .mix, samples: samples))

        let correctedURL = try XCTUnwrap(
            AudioPlaybackFileCorrector.renderCorrectedCopy(
                from: writtenURL,
                expectedDuration: 0.2,
                correctionRate: 0.5
            )
        )
        defer { try? FileManager.default.removeItem(at: correctedURL) }

        let correctedFile = try AVAudioFile(forReading: correctedURL)
        XCTAssertEqual(correctedFile.fileFormat.sampleRate, 16_000, accuracy: 0.1)
        XCTAssertEqual(correctedFile.length, 3_200)

        let correctedSamples = try AudioWriter.readSamples(from: correctedURL)
        XCTAssertEqual(correctedSamples.count, 3_200)
        XCTAssertNotEqual(correctedURL, writtenURL)
    }

    func testRenderCorrectedCopyRejectsExtremeExpansion() throws {
        let id = "playback-corrector-extreme-\(UUID().uuidString)"
        let originalURL = AudioWriter.url(id: id, stem: .mix)
        defer { try? FileManager.default.removeItem(at: originalURL) }

        let samples = Array(repeating: Float(0.1), count: 1_600)
        let writtenURL = try XCTUnwrap(AudioWriter.persist(id: id, stem: .mix, samples: samples))

        let correctedURL = try AudioPlaybackFileCorrector.renderCorrectedCopy(
            from: writtenURL,
            expectedDuration: 1,
            correctionRate: 0.1
        )

        XCTAssertNil(correctedURL)
    }

    func testResampleInterpolatesTargetCount() {
        let corrected = AudioPlaybackFileCorrector.resample(samples: [0, 1], targetCount: 5)

        XCTAssertEqual(corrected.count, 5)
        XCTAssertEqual(corrected[0], 0, accuracy: 0.0001)
        XCTAssertEqual(corrected[1], 0.25, accuracy: 0.0001)
        XCTAssertEqual(corrected[2], 0.5, accuracy: 0.0001)
        XCTAssertEqual(corrected[3], 0.75, accuracy: 0.0001)
        XCTAssertEqual(corrected[4], 1, accuracy: 0.0001)
    }
}
