import AppKit
import ApplicationServices
import Combine
import Foundation

struct AXNodeDump: Codable, Hashable {
    let role: String?
    let subrole: String?
    let identifier: String?
    let title: String?
    let value: String?
    let descriptionText: String?
    let path: String
    let depth: Int
    let childCount: Int
}

struct AXAppDump: Codable {
    let bundleIdentifier: String
    let processName: String
    let capturedAt: Date
    let nodes: [AXNodeDump]
    let truncated: Bool
}

struct CaptionDebugSnapshot: Codable {
    let capturedAt: Date
    let accessibilityTrusted: Bool
    let apps: [AXAppDump]
}

@MainActor
enum CaptionDebugDumper {
    static let userDefaultEnabled = "caption_debug_dump"
    static let userDefaultIntervalSeconds = "caption_debug_dump_interval"
    static let directoryName = "debug-axdumps"

    private static var pollTimer: AnyCancellable?

    static func isEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: userDefaultEnabled)
    }

    static func installIfEnabled() {
        guard isEnabled() else { return }
        let interval = max(2.0, UserDefaults.standard.double(forKey: userDefaultIntervalSeconds))
        let chosen = interval == 0 ? 5.0 : interval
        startLiveDumping(every: chosen)
    }

    static func startLiveDumping(every interval: TimeInterval = 5.0) {
        stopLiveDumping()
        pollTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                _ = try? writeSnapshot()
            }
        _ = try? writeSnapshot()
    }

    static func stopLiveDumping() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    @discardableResult
    static func writeSnapshot(to overrideDirectory: URL? = nil) throws -> URL {
        let snapshot = snapshotMeetingApps()
        let dir = try directory(override: overrideDirectory)
        let filename = "axdump-\(timestamp()).json"
        let target = dir.appendingPathComponent(filename)
        let data = try JSONEncoder.pretty.encode(snapshot)
        try data.write(to: target, options: [.atomic])
        return target
    }

    static func snapshotMeetingApps(now: Date = Date()) -> CaptionDebugSnapshot {
        let trusted = AXIsProcessTrusted()
        guard trusted else {
            return CaptionDebugSnapshot(
                capturedAt: now,
                accessibilityTrusted: false,
                apps: []
            )
        }
        let bundleIds = Set(CallApp.allKnownBundleIdentifiers)
        let runningApps = NSWorkspace.shared.runningApplications.filter { app in
            guard let bundleId = app.bundleIdentifier else { return false }
            return bundleIds.contains { target in
                bundleId == target || bundleId.hasPrefix(target + ".")
            }
        }
        let dumps = runningApps.map { app -> AXAppDump in
            dumpAccessibilityTree(of: app, now: now)
        }
        return CaptionDebugSnapshot(capturedAt: now, accessibilityTrusted: true, apps: dumps)
    }

    private static func dumpAccessibilityTree(of app: NSRunningApplication, now: Date) -> AXAppDump {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var collected: [AXNodeDump] = []
        var truncated = false
        let limit = 600
        walk(element: element, depth: 0, path: "app", limit: limit, collected: &collected, truncated: &truncated)
        return AXAppDump(
            bundleIdentifier: app.bundleIdentifier ?? "",
            processName: app.localizedName ?? "",
            capturedAt: now,
            nodes: collected,
            truncated: truncated
        )
    }

    private static func walk(
        element: AXUIElement,
        depth: Int,
        path: String,
        limit: Int,
        collected: inout [AXNodeDump],
        truncated: inout Bool
    ) {
        guard depth <= 11 else { return }
        guard collected.count < limit else {
            truncated = true
            return
        }
        let role = stringAttribute(element, kAXRoleAttribute)
        let subrole = stringAttribute(element, kAXSubroleAttribute)
        let identifier = stringAttribute(element, kAXIdentifierAttribute)
        let title = stringAttribute(element, kAXTitleAttribute)
        let value = stringAttribute(element, kAXValueAttribute)
        let descriptionText = stringAttribute(element, kAXDescriptionAttribute)
        let children = arrayAttribute(element, kAXChildrenAttribute)

        let dump = AXNodeDump(
            role: role,
            subrole: subrole,
            identifier: identifier,
            title: trimForDump(title),
            value: trimForDump(value),
            descriptionText: trimForDump(descriptionText),
            path: path,
            depth: depth,
            childCount: children.count
        )
        if dump.hasUsefulContent {
            collected.append(dump)
        }

        for (index, child) in children.enumerated() {
            if collected.count >= limit {
                truncated = true
                return
            }
            walk(
                element: child,
                depth: depth + 1,
                path: "\(path)/\(role ?? "?")[\(index)]",
                limit: limit,
                collected: &collected,
                truncated: &truncated
            )
        }
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        if let str = value as? String { return str }
        if let attr = value as? NSAttributedString { return attr.string }
        return nil
    }

    private static func arrayAttribute(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let array = value as? [AXUIElement] else { return [] }
        return array
    }

    private static func trimForDump(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let collapsed = raw
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
        let truncated = collapsed.count <= 480 ? collapsed : String(collapsed.prefix(480)) + "…"
        return truncated.isEmpty ? nil : truncated
    }

    private static func directory(override: URL?) throws -> URL {
        if let override {
            try FileManager.default.createDirectory(at: override, withIntermediateDirectories: true)
            return override
        }
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let target = support
            .appendingPathComponent("NeoQuill", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }
}

extension AXNodeDump {
    var hasUsefulContent: Bool {
        let candidates = [title, value, descriptionText].compactMap { $0 }
        return candidates.contains { !$0.isEmpty }
    }
}

private extension JSONEncoder {
    static let pretty: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension CallApp {
    static var allKnownBundleIdentifiers: [String] {
        let cases: [CallApp] = [.teams, .zoom, .browser, .facetime, .slack, .webex, .discord]
        return cases.flatMap { $0.bundleIdentifiers }
    }
}
