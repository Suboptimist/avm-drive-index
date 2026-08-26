import Foundation

/// One file's copy, kept apart from the UI so it can be tested on its own.
///
/// The rules, in order of importance: never remove anything from the source,
/// never overwrite anything at the destination, and never leave a partial file
/// behind if the copy came up short.
enum FileCopier {

    enum Outcome: Equatable {
        case copied(bytes: Int64)
        case skippedExists
        case failed(String)
    }

    /// Copies one file to `folder/relativePath`, making any folders the path
    /// needs along the way.
    static func copy(_ item: CopyItem, into folder: URL) -> Outcome {
        let fm = FileManager.default
        let target = folder.appendingPathComponent(item.relativePath)

        if fm.fileExists(atPath: target.path) { return .skippedExists }

        let parent = target.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path) {
            do {
                try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            } catch {
                return .failed("could not make \(parent.lastPathComponent): \(error.localizedDescription)")
            }
        }

        do {
            try fm.copyItem(at: item.source, to: target)
        } catch {
            return .failed(error.localizedDescription)
        }

        // Check it arrived whole. A short copy means trouble, so the partial
        // file goes rather than sitting there looking valid.
        let written = (try? target.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        if let written, Int64(written) != item.size {
            try? fm.removeItem(at: target)
            return .failed("copied \(written) of \(item.size) bytes")
        }
        return .copied(bytes: item.size)
    }
}
