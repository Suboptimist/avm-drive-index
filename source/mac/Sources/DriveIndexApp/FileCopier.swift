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

    static func copyOne(_ file: SourceFile, into folder: URL) -> Outcome {
        let fm = FileManager.default
        let target = folder.appendingPathComponent(file.name)

        if fm.fileExists(atPath: target.path) { return .skippedExists }

        do {
            try fm.copyItem(at: file.url, to: target)
        } catch {
            return .failed(error.localizedDescription)
        }

        // Check it arrived whole. A short copy means trouble, so the partial
        // file goes rather than sitting there looking valid.
        let written = (try? target.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        if let written, Int64(written) != file.size {
            try? fm.removeItem(at: target)
            return .failed("copied \(written) of \(file.size) bytes")
        }
        return .copied(bytes: file.size)
    }
}
