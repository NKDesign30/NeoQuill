import Foundation
import AudioToolbox
import AVFoundation
import os.log

private let logger = Logger(subsystem: "com.neon.neoquill", category: "ProcessAudioTap")

private func tapDiagLog(_ msg: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "[TAP \(ts)] \(msg)\n"
    let logPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/meeting-scribe/meetings/quill-diag.log")
    if let handle = try? FileHandle(forWritingTo: logPath) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8) ?? Data())
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath.path, contents: line.data(using: .utf8))
    }
}

/// CoreAudio Process Tap — captured Audio direkt vom Output-Stream einer App.
///
/// Vorteile:
/// - Keine Bildschirmaufnahme-Berechtigung (nur "System Audio Recording", einmalig)
/// - Kein BlackHole, kein Multi-Output Device, kein Default-Device-Wechsel
/// - App merkt nichts davon (Tap ist unsichtbar)
/// - Funktioniert unabhaengig vom Output-Device der App
final class ProcessAudioTap: @unchecked Sendable {

    /// Called with 16kHz mono Float32 samples
    var onSamples: (([Float]) -> Void)?

    /// Called with 48kHz mono Float32 samples for the high-resolution archive.
    var onSamplesHQ: (([Float]) -> Void)?

    private var processTapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var deviceProcID: AudioDeviceIOProcID?
    private var tapStreamDescription: AudioStreamBasicDescription?
    private let audioQueue = DispatchQueue(label: "com.quill.process-tap", qos: .userInitiated)

    private var formatConverter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!
    private lazy var hqConverter = PCMStreamConverter(targetSampleRate: 48_000)
    private var callbackCount = 0

    /// Startet den Process Tap fuer die angegebenen Bundle IDs.
    /// Wenn keine Bundle IDs angegeben, wird gesamtes System-Audio getappt.
    func start(bundleIdentifiers: [String]) throws {
        logger.warning("ProcessTap start fuer: \(bundleIdentifiers.isEmpty ? ["*ALL*"] : bundleIdentifiers, privacy: .public)")

        // 1. Audio-Prozesse finden die zu den Bundle IDs gehoeren
        let processObjectIDs = findAudioProcesses(for: bundleIdentifiers)

        // 2. Process Tap erstellen
        let tapDescription: CATapDescription
        if processObjectIDs.isEmpty {
            // Fallback: Alle Prozesse tappen (Stereo Mixdown)
            logger.warning("Keine spezifischen Prozesse gefunden, tappe gesamtes System-Audio")
            tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        } else {
            logger.warning("Tappe \(processObjectIDs.count, privacy: .public) Prozesse: \(processObjectIDs, privacy: .public)")
            tapDescription = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        }
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = .unmuted

        var tapID: AudioObjectID = kAudioObjectUnknown
        var err = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard err == noErr else {
            let errStr = fourCharString(err)
            logger.error("AudioHardwareCreateProcessTap fehlgeschlagen: \(err, privacy: .public) ('\(errStr, privacy: .public)')")
            throw TapError.tapCreationFailed(err)
        }
        processTapID = tapID
        logger.warning("Process Tap erstellt (ID: \(tapID, privacy: .public))")

        // 3. Tap-Format lesen
        tapStreamDescription = try readTapFormat(tapID)
        if let desc = tapStreamDescription {
            logger.warning("Tap Format: \(desc.mSampleRate, privacy: .public) Hz, \(desc.mChannelsPerFrame, privacy: .public) ch")
        }

        // 4. Aggregate Device mit Tap erstellen
        let systemOutputID = try readDefaultSystemOutputDevice()
        let outputUID = try readDeviceUID(systemOutputID)

        let aggDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Quill-Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString
                ]
            ]
        ]

        aggregateDeviceID = kAudioObjectUnknown
        err = AudioHardwareCreateAggregateDevice(aggDescription as CFDictionary, &aggregateDeviceID)
        guard err == noErr else {
            logger.error("Aggregate Device fehlgeschlagen: \(err, privacy: .public)")
            throw TapError.aggregateDeviceFailed(err)
        }
        logger.warning("Aggregate Device erstellt (ID: \(self.aggregateDeviceID, privacy: .public))")

        // 5. IOProc starten — hier kommen die Audio-Daten
        callbackCount = 0
        formatConverter = nil

        err = AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, aggregateDeviceID, audioQueue) {
            [weak self] inNow, inInputData, inInputTime, outOutputData, inOutputTime in
            self?.handleAudioData(inInputData)
        }
        guard err == noErr else {
            logger.error("IOProc erstellen fehlgeschlagen: \(err, privacy: .public)")
            throw TapError.ioProcFailed(err)
        }

        err = AudioDeviceStart(aggregateDeviceID, deviceProcID)
        guard err == noErr else {
            logger.error("AudioDeviceStart fehlgeschlagen: \(err, privacy: .public)")
            throw TapError.deviceStartFailed(err)
        }

        logger.warning("ProcessAudioTap laeuft!")
        tapDiagLog("TAP STARTED: bundleIds=\(bundleIdentifiers), processCount=\(processObjectIDs.count), tapID=\(tapID), aggDevice=\(aggregateDeviceID), format=\(tapStreamDescription?.mSampleRate ?? 0)Hz/\(tapStreamDescription?.mChannelsPerFrame ?? 0)ch")
    }

    func stop() {
        logger.warning("ProcessTap stop")

        if aggregateDeviceID != kAudioObjectUnknown {
            if let procID = deviceProcID {
                AudioDeviceStop(aggregateDeviceID, procID)
                AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
                deviceProcID = nil
            }
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }

        if processTapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(processTapID)
            processTapID = kAudioObjectUnknown
        }

        formatConverter = nil
        tapStreamDescription = nil
        logger.warning("ProcessTap gestoppt")
    }

    deinit { stop() }

    // MARK: - Audio Callback

    private func handleAudioData(_ bufferList: UnsafePointer<AudioBufferList>) {
        guard var desc = tapStreamDescription else { return }

        // AVAudioFormat aus Tap-Format
        let sourceFormat: AVAudioFormat
        if let fmt = AVAudioFormat(streamDescription: &desc) {
            sourceFormat = fmt
        } else if let fmt = AVAudioFormat(
            standardFormatWithSampleRate: desc.mSampleRate,
            channels: desc.mChannelsPerFrame
        ) {
            sourceFormat = fmt
        } else {
            return
        }

        processBuffer(bufferList, sourceFormat: sourceFormat)
    }

    private func processBuffer(_ bufferList: UnsafePointer<AudioBufferList>, sourceFormat: AVAudioFormat) {

        // BufferList → AVAudioPCMBuffer
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, bufferListNoCopy: bufferList) else { return }
        guard pcmBuffer.frameLength > 0 else { return }

        // Converter erstellen/cachen
        if formatConverter == nil {
            formatConverter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        }
        guard let converter = formatConverter else { return }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(pcmBuffer.frameLength) * ratio)
        guard outputFrameCount > 0 else { return }

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCount
        ) else { return }

        var error: NSError?
        var hasData = true
        converter.reset()

        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if hasData {
                hasData = false
                outStatus.pointee = .haveData
                return pcmBuffer
            } else {
                outStatus.pointee = .noDataNow
                return nil
            }
        }

        guard error == nil,
              let channelData = outputBuffer.floatChannelData,
              outputBuffer.frameLength > 0 else { return }

        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
        guard !samples.isEmpty else { return }

        callbackCount += 1
        if callbackCount <= 5 {
            let maxVal = samples.map { abs($0) }.max() ?? 0
            let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1)))
            logger.warning("Tap #\(self.callbackCount): \(samples.count) samples, max=\(String(format: "%.6f", maxVal), privacy: .public), rms=\(String(format: "%.6f", rms), privacy: .public)")
            tapDiagLog("TAP CALLBACK #\(callbackCount): \(samples.count) samples, rms=\(String(format: "%.6f", rms)), max=\(String(format: "%.6f", maxVal)), format=\(sourceFormat)")
        }
        // Alle 1000 Callbacks (~30s) ein Diagnose-Log
        if callbackCount % 1000 == 0 {
            let maxVal = samples.map { abs($0) }.max() ?? 0
            let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1)))
            tapDiagLog("TAP PERIODIC #\(callbackCount): rms=\(String(format: "%.6f", rms)), max=\(String(format: "%.6f", maxVal))")
        }

        onSamples?(samples)

        // High-resolution archive path: convert the same native buffer to 48 kHz
        // mono with the drain-correct converter (independent of the 16 kHz ASR path).
        if let onSamplesHQ, let hq = hqConverter?.convert(pcmBuffer), !hq.isEmpty {
            onSamplesHQ(hq)
        }
    }

    // MARK: - Process Discovery

    private func findAudioProcesses(for bundleIdentifiers: [String]) -> [AudioObjectID] {
        guard !bundleIdentifiers.isEmpty else { return [] }

        // Alle Audio-Prozesse vom System holen
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var err = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize)
        guard err == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }

        var objectIDs = [AudioObjectID](repeating: kAudioObjectUnknown, count: count)
        err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &objectIDs)
        guard err == noErr else { return [] }

        // Bundle IDs der Prozesse prüfen
        var matched: [AudioObjectID] = []
        for objectID in objectIDs {
            guard let bundleID = readProcessBundleID(objectID) else { continue }

            let isMatch = bundleIdentifiers.contains(where: { target in
                bundleID == target || bundleID.hasPrefix(target + ".")
            })

            if isMatch {
                // Nur Prozesse die Audio Output haben
                let isRunning = readProcessIsRunning(objectID)
                logger.warning("  Prozess Match: \(bundleID, privacy: .public) (objectID: \(objectID, privacy: .public), audioActive: \(isRunning, privacy: .public))")
                matched.append(objectID)
            }
        }

        tapDiagLog("PROCESS DISCOVERY: searched=\(bundleIdentifiers), totalProcesses=\(count), matched=\(matched.count) IDs=\(matched)")
        return matched
    }

    // MARK: - CoreAudio Helpers

    private func readDefaultSystemOutputDevice() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard err == noErr else { throw TapError.noOutputDevice }
        return deviceID
    }

    private func readDeviceUID(_ deviceID: AudioDeviceID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let err = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
        guard err == noErr, let uid else { throw TapError.formatError }
        return uid.takeUnretainedValue() as String
    }

    private func readTapFormat(_ tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var desc = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let err = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &desc)
        guard err == noErr else { throw TapError.formatError }
        return desc
    }

    private func readProcessBundleID(_ objectID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var bundleID: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let err = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &bundleID)
        guard err == noErr, let bundleID else { return nil }
        let result = bundleID.takeUnretainedValue() as String
        return result.isEmpty ? nil : result
    }

    private func readProcessIsRunning(_ objectID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunning,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let err = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
        return err == noErr && value != 0
    }

    private func fourCharString(_ code: OSStatus) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "\(code)"
    }
}

// MARK: - Errors

enum TapError: LocalizedError {
    case tapCreationFailed(OSStatus)
    case aggregateDeviceFailed(OSStatus)
    case ioProcFailed(OSStatus)
    case deviceStartFailed(OSStatus)
    case noOutputDevice
    case formatError

    var errorDescription: String? {
        switch self {
        case .tapCreationFailed(let s): return "Process Tap fehlgeschlagen (OSStatus \(s))"
        case .aggregateDeviceFailed(let s): return "Aggregate Device fehlgeschlagen (OSStatus \(s))"
        case .ioProcFailed(let s): return "IOProc fehlgeschlagen (OSStatus \(s))"
        case .deviceStartFailed(let s): return "Device Start fehlgeschlagen (OSStatus \(s))"
        case .noOutputDevice: return "Kein Output Device"
        case .formatError: return "Audio Format Fehler"
        }
    }
}
