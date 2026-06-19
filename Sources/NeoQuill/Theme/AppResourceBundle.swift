import Foundation

enum AppResourceBundle {
    private static let packageBundleName = "NeoQuill_NeoQuill"

    static func candidates() -> [Bundle] {
        cachedCandidates
    }

    private static let cachedCandidates: [Bundle] = {
        var bundles: [Bundle] = [.main]

        for url in packageBundleURLs() {
            guard let bundle = Bundle(url: url),
                  !bundles.contains(where: { $0.bundleURL == bundle.bundleURL }) else {
                continue
            }
            bundles.append(bundle)
        }

        return bundles
    }()

    static func url(forResource name: String, withExtension ext: String, subdirectory: String? = nil) -> URL? {
        for bundle in candidates() {
            if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
                return url
            }
            if subdirectory != nil,
               let url = bundle.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    private static func packageBundleURLs() -> [URL] {
        var roots: [URL] = []
        func appendRoot(_ url: URL) {
            let standardized = url.standardizedFileURL
            if !roots.contains(standardized) {
                roots.append(standardized)
            }
        }

        func appendRootAndParents(_ url: URL) {
            var current = url.standardizedFileURL
            for _ in 0..<5 {
                appendRoot(current)
                let parent = current.deletingLastPathComponent().standardizedFileURL
                if parent == current {
                    break
                }
                current = parent
            }
        }

        if let resourceURL = Bundle.main.resourceURL {
            appendRootAndParents(resourceURL)
        }
        if let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() {
            appendRootAndParents(executableDirectory)
            appendRoot(executableDirectory.appendingPathComponent("../Resources"))
        }
        for bundle in Bundle.allBundles + Bundle.allFrameworks {
            if bundle.bundleURL.deletingPathExtension().lastPathComponent == packageBundleName {
                appendRoot(bundle.bundleURL.deletingLastPathComponent())
            }
            if let resourceURL = bundle.resourceURL {
                appendRootAndParents(resourceURL)
            }
            if let executableDirectory = bundle.executableURL?.deletingLastPathComponent() {
                appendRootAndParents(executableDirectory)
            }
        }

        var urls: [URL] = []
        for root in roots {
            let url = root.appendingPathComponent(packageBundleName).appendingPathExtension("bundle")
            if FileManager.default.fileExists(atPath: url.path),
               !urls.contains(url) {
                urls.append(url)
            }
        }
        return urls
    }
}
