import Foundation

struct AppVersionInfo: Equatable {
    let version: String
    let build: String
    let gitCommit: String
    let gitBranch: String
    let gitDirty: String
    let buildDate: String

    var displayVersion: String {
        "v\(version) (\(build))"
    }

    var displayGit: String {
        let suffix = gitDirty == "dirty" ? " dirty" : ""
        return "\(gitBranch)@\(gitCommit)\(suffix)"
    }

    static func current(bundle: Bundle = .main) -> AppVersionInfo {
        from(info: bundle.infoDictionary ?? [:])
    }

    static func from(info: [String: Any]) -> AppVersionInfo {
        AppVersionInfo(
            version: string("CFBundleShortVersionString", in: info, fallback: "0.0.0"),
            build: string("CFBundleVersion", in: info, fallback: "0"),
            gitCommit: string("NeoQuillGitCommit", in: info, fallback: "unknown"),
            gitBranch: string("NeoQuillGitBranch", in: info, fallback: "unknown"),
            gitDirty: string("NeoQuillGitDirty", in: info, fallback: "unknown"),
            buildDate: string("NeoQuillBuildDate", in: info, fallback: "unknown")
        )
    }

    private static func string(_ key: String, in info: [String: Any], fallback: String) -> String {
        guard let value = info[key] as? String else { return fallback }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
