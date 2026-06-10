import AppKit
import ApplicationServices
import Combine
import Foundation

@MainActor
final class CaptionCaptureService: ObservableObject {
    enum CaptureState: Equatable {
        case idle
        case disabled
        case missingAccessibilityPermission
        case unsupportedApp
        case listening(Platform)
        case noCaptionsSeen(Platform)

        var label: String {
            switch self {
            case .idle:
                return "Captions bereit"
            case .disabled:
                return "Captions aus"
            case .missingAccessibilityPermission:
                return "Accessibility fehlt"
            case .unsupportedApp:
                return "Captions nicht unterstützt"
            case .listening(let platform):
                return "Captions aktiv · \(platform.rawValue)"
            case .noCaptionsSeen(let platform):
                return "Keine Captions · \(platform.rawValue)"
            }
        }
    }

    @Published private(set) var state: CaptureState = .idle
    @Published private(set) var events: [CaptionEvent] = []

    private var timer: AnyCancellable?
    private var startedAt: Date?
    private var activeApp: CallApp = .unknown
    private var seenFingerprints: Set<String> = []
    private var noCaptionPollCount = 0

    func start(for app: CallApp, startedAt: Date) {
        stop()
        guard UserDefaults.standard.boolOr(AppSettings.liveCaptionCapture, default: false) else {
            state = .disabled
            return
        }
        guard AXIsProcessTrusted() else {
            state = .missingAccessibilityPermission
            return
        }
        guard app.supportsCaptionCapture else {
            state = .unsupportedApp
            return
        }

        self.startedAt = startedAt
        self.activeApp = app
        events.removeAll()
        seenFingerprints.removeAll()
        noCaptionPollCount = 0
        state = .noCaptionsSeen(app.platform)

        timer = Timer.publish(every: 0.8, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.poll()
            }
        poll()
    }

    @discardableResult
    func stop() -> [CaptionEvent] {
        timer?.cancel()
        timer = nil
        startedAt = nil
        activeApp = .unknown
        let snapshot = events
        if state != .disabled && state != .missingAccessibilityPermission {
            state = .idle
        }
        return snapshot
    }

    func snapshotEvents() -> [CaptionEvent] {
        events
    }

    /// Erzwingt einen Reset und spielt eine vorgespeicherte Fixture in
    /// genau derselben Pipeline ab wie die Live-AX-Polling-Schleife.
    /// Nur fuer QA / Tests gedacht — kein Permission-Check, keine UserDefaults.
    func replayFixture(_ fixture: CaptionFixture, startedAt: Date = Date()) -> [CaptionEvent] {
        timer?.cancel()
        timer = nil
        self.startedAt = startedAt
        events.removeAll()
        seenFingerprints.removeAll()
        noCaptionPollCount = 0
        state = .listening(fixture.platform)
        CaptionFixtureReplayer.replay(fixture) { [weak self] offset, candidates in
            guard let self, let startedAt = self.startedAt else { return }
            self.consume(
                candidates,
                startSeconds: offset,
                observedAt: startedAt.addingTimeInterval(offset),
                platform: fixture.platform
            )
        }
        return events
    }

    /// Konfidenz für Captions ohne erkannten Sprecher bzw. mit Namen.
    static let anonymousCaptionConfidence: Double = 0.45
    static let namedCaptionConfidence: Double = 0.88

    /// Der EINE Weg von Kandidaten zu CaptionEvents — geteilt von Live-`poll()`
    /// und Fixture-Replay. Vorher duplizierte der Replay-Pfad die komplette
    /// Event-Konstruktion (gleicher CaptionEvent-Block, gleiche Konfidenzen);
    /// die versprochene "genau dieselbe Pipeline" teilte real nur die Dedupe.
    @discardableResult
    private func consume(
        _ candidates: [CaptionCandidate],
        startSeconds: TimeInterval,
        observedAt: Date,
        platform: Platform
    ) -> Int {
        var appended = 0
        for candidate in candidates {
            let fingerprint = CaptionTextParser.fingerprint(candidate: candidate, platform: platform)
            guard !seenFingerprints.contains(fingerprint) else { continue }
            seenFingerprints.insert(fingerprint)
            events.append(CaptionEvent(
                platform: platform,
                appBundleIdentifier: candidate.bundleIdentifier,
                speakerName: candidate.speakerName,
                text: candidate.text,
                startSeconds: startSeconds,
                endSeconds: startSeconds + candidate.estimatedDuration,
                observedAt: observedAt,
                confidence: candidate.speakerName == nil
                    ? Self.anonymousCaptionConfidence
                    : Self.namedCaptionConfidence,
                rawPayload: candidate.rawText
            ))
            appended += 1
        }
        return appended
    }

    private func poll() {
        guard let startedAt else { return }
        let platform = activeApp.platform
        let bundleIds = activeApp.bundleIdentifiers
        let running = NSWorkspace.shared.runningApplications.filter { app in
            guard let bundleId = app.bundleIdentifier else { return false }
            return bundleIds.contains { target in
                bundleId == target || bundleId.hasPrefix(target + ".")
            }
        }
        guard !running.isEmpty else {
            state = .unsupportedApp
            return
        }

        let candidates = running.flatMap { extractCaptionCandidates(from: $0) }
        let now = Date()
        let appended = consume(
            candidates,
            startSeconds: now.timeIntervalSince(startedAt),
            observedAt: now,
            platform: platform
        )

        if appended > 0 {
            state = .listening(platform)
            noCaptionPollCount = 0
        } else {
            noCaptionPollCount += 1
            if noCaptionPollCount >= 4, events.isEmpty {
                state = .noCaptionsSeen(platform)
            }
        }
    }

    private func extractCaptionCandidates(from app: NSRunningApplication) -> [CaptionCandidate] {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        let windows = copyArrayAttribute(element, kAXWindowsAttribute as CFString)
        let texts = windows.flatMap { window in
            collectText(from: window, depth: 0, budget: 220)
        }
        let uniqueTexts = Array(Set(texts.map(CaptionTextParser.normalizeVisibleText))).filter { !$0.isEmpty }
        return uniqueTexts.compactMap { text in
            CaptionTextParser.parseCandidate(text, bundleIdentifier: app.bundleIdentifier)
        }
    }

    private func collectText(from element: AXUIElement, depth: Int, budget: Int) -> [String] {
        guard depth <= 9, budget > 0 else { return [] }
        var output: [String] = []
        for attribute in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
            if let value = copyStringAttribute(element, attribute as CFString),
               CaptionTextParser.isUsefulVisibleText(value) {
                output.append(value)
            }
        }
        let children = copyArrayAttribute(element, kAXChildrenAttribute as CFString)
        var remaining = max(0, budget - output.count)
        for child in children where remaining > 0 {
            let childText = collectText(from: child, depth: depth + 1, budget: remaining)
            output.append(contentsOf: childText)
            remaining = max(0, remaining - childText.count)
        }
        return output
    }

    private func copyStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else { return nil }
        if let string = value as? String { return string }
        if let attributed = value as? NSAttributedString { return attributed.string }
        return nil
    }

    private func copyArrayAttribute(_ element: AXUIElement, _ attribute: CFString) -> [AXUIElement] {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let array = value as? [AXUIElement] else { return [] }
        return array
    }

}

private extension CallApp {
    var supportsCaptionCapture: Bool {
        switch self {
        case .teams, .zoom, .browser:
            return true
        case .facetime, .slack, .webex, .discord, .unknown:
            return false
        }
    }

    var platform: Platform {
        switch self {
        case .teams:
            return .teams
        case .zoom:
            return .zoom
        case .browser:
            return .meet
        case .facetime, .slack, .webex, .discord, .unknown:
            return .call
        }
    }
}
