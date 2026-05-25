import Foundation

enum AppResourceBundle {
    private static let packageBundleName = "NeoQuill_NeoQuill"

    static func candidates() -> [Bundle] {
        var bundles: [Bundle] = [.main]

        for url in packageBundleURLs() {
            guard let bundle = Bundle(url: url),
                  !bundles.contains(where: { $0.bundleURL == bundle.bundleURL }) else {
                continue
            }
            bundles.append(bundle)
        }

        return bundles
    }

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
        if let resourceURL = Bundle.main.resourceURL {
            roots.append(resourceURL)
        }
        if let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() {
            roots.append(executableDirectory)
            roots.append(executableDirectory.appendingPathComponent("../Resources").standardizedFileURL)
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
