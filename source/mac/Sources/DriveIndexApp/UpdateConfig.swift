import Foundation

/// Where the app looks for updates.
///
/// The repository is public, so no key is needed and nothing secret ships
/// inside the app — GitHub's unauthenticated API is enough (60 requests an
/// hour per address, against a once-a-day check).
enum UpdateConfig {
    static let owner = "Suboptimist"
    static let repo = "avm-drive-index"

    /// The release asset the Mac updater downloads.
    static let macAsset = "AVM-Drive-Index-Mac.zip"

    static var releasesURL: URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
    }

    static var downloadPage: URL {
        URL(string: "https://github.com/\(owner)/\(repo)/releases/latest")!
    }
}
