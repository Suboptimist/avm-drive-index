import Foundation

/// Dotted version numbers, compared the way people expect: 1.10 is newer than
/// 1.9, and "1.6" and "1.6.0" are the same version.
///
/// Deliberately free of any UI or actor isolation so it can be compiled and
/// tested on its own.
enum VersionCompare {
    static func isNewer(_ a: String, than b: String) -> Bool {
        let av = parts(a), bv = parts(b)
        for i in 0..<max(av.count, bv.count) {
            let x = i < av.count ? av[i] : 0
            let y = i < bv.count ? bv[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Tolerates a leading "v" and anything non-numeric in a component, so a
    /// malformed tag can never crash the updater — it just compares as 0.
    private static func parts(_ s: String) -> [Int] {
        let trimmed = s.hasPrefix("v") || s.hasPrefix("V") ? String(s.dropFirst()) : s
        return trimmed.split(separator: ".").map { component in
            Int(component.prefix { $0.isNumber }) ?? 0
        }
    }
}
