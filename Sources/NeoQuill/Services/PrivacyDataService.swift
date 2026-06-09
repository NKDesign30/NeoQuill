import AppKit
import Foundation

struct PrivacyDeleteResult: Equatable {
    let audioFilesDeleted: Int
}

enum PrivacyDataService {
    static func openLocalDataFolder() {
        NSWorkspace.shared.open(MeetingStore.applicationSupportDirectory())
    }

    @discardableResult
    static func deleteAudioFiles(directory: URL = AudioWriter.recordingsDirectory()) throws -> Int {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return 0 }
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "wav" }
        for file in files {
            try fileManager.removeItem(at: file)
        }
        return files.count
    }

    @discardableResult
    static func deleteAudioFiles(for meetingId: String, directory: URL = AudioWriter.recordingsDirectory()) throws -> Int {
        // RecordingArtifacts ist die Single Source of Truth über alle Spur-Dateien
        // eines Meetings — inklusive der früher vergessenen `.hq`-Spur.
        try RecordingArtifacts(meetingId: meetingId, directory: directory).deleteAll()
    }

    @discardableResult
    static func deleteAllLocalMeetingData(store: MeetingStore) throws -> PrivacyDeleteResult {
        store.deleteAllMeetings()
        let deletedAudio = try deleteAudioFiles()
        return PrivacyDeleteResult(audioFilesDeleted: deletedAudio)
    }
}
