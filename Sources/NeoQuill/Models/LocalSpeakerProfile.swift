import Foundation

enum LocalSpeakerProfile {
    static let id = "ME"
    static let legacyIds: Set<String> = ["NK"]
    static let colorHex: UInt32 = 0x2EAB73

    static var displayName: String {
        let stored = UserDefaults.standard.string(forKey: AppSettings.ownerDisplayName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty { return stored }

        let systemName = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        if !systemName.isEmpty { return systemName }

        return "Ich"
    }

    static var role: String {
        let stored = UserDefaults.standard.string(forKey: AppSettings.ownerRole)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stored?.isEmpty == false ? stored! : "Eigene Stimme"
    }

    static func isLocalSpeakerId(_ speakerId: String) -> Bool {
        speakerId == id || legacyIds.contains(speakerId)
    }

    static func participant(spoke: String) -> Participant {
        Participant(
            id: id,
            name: displayName,
            role: role,
            colorHex: colorHex,
            spoke: spoke
        )
    }
}
