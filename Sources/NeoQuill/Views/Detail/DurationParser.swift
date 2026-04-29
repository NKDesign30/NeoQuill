import Foundation

// "32m 14s" / "29s" / "12m" / "1h 5m" → Sekunden. Wird vom AudioPlayer genutzt
// um die Total-Dauer aus dem MeetingDetail.duration-String abzuleiten.

func parseDuration(_ s: String) -> Int {
    let scanner = Scanner(string: s)
    scanner.charactersToBeSkipped = .whitespaces
    var total = 0
    while !scanner.isAtEnd {
        guard let value = scanner.scanInt() else { break }
        let unit = scanner.scanCharacter() ?? Character(" ")
        switch unit {
        case "h":  total += value * 3600
        case "m":  total += value * 60
        case "s":  total += value
        default:   total += value
        }
    }
    return total
}
