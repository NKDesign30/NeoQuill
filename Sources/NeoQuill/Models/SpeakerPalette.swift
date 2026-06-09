import Foundation

/// Die eine Stelle, die einem Speaker eine Farbe gibt.
///
/// Vorher war dieselbe Frage — „welche Farbe hat Speaker X?" — dreimal
/// hartkodiert: in `collectParticipants` als Tupel-Palette, in
/// `colorHex(forSpeakerId:)` als Dictionary und im Hash-Fallback-Array. Drei
/// Quellen für eine Antwort; eine S2-Änderung hätte alle drei treffen müssen.
enum SpeakerPalette {
    /// Stabile Farbe für den lokalen Sprecher und die fixen S1–S4. Unbekannte
    /// IDs bekommen eine deterministische Hash-Farbe aus `fallbackColors`.
    static func color(for id: String) -> UInt32 {
        if LocalSpeakerProfile.isLocalSpeakerId(id) { return LocalSpeakerProfile.colorHex }
        if let fixed = fixedColors[id] { return fixed }
        let checksum = id.unicodeScalars.reduce(UInt32(0)) { partial, scalar in
            partial &+ scalar.value
        }
        return fallbackColors[Int(checksum % UInt32(fallbackColors.count))]
    }

    /// Die festen Slots S1–S4.
    static let fixedSpeakerIds: [String] = ["S1", "S2", "S3", "S4"]

    private static let fixedColors: [String: UInt32] = [
        "S1": 0x7C8AFF,
        "S2": 0xFFB340,
        "S3": 0x409CFF,
        "S4": 0xD4845A,
    ]

    private static let fallbackColors: [UInt32] = [
        0x7C8AFF, 0xFFB340, 0x409CFF, 0xD4845A, 0xFF6259, 0x2EAB73,
    ]
}
