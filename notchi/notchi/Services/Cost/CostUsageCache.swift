import Foundation

struct CostUsageCache: Codable, Equatable {
    struct FileState: Codable, Equatable {
        var size: Int64
        var mtime: Double
        var offset: Int64
    }

    static let currentVersion = 1
    var version: Int
    var files: [String: FileState]   // [filePath: state]
    var buckets: DayModelBuckets
}

enum CostUsageCacheStore {
    static func load(url: URL) -> CostUsageCache {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CostUsageCache.self, from: data),
              decoded.version == CostUsageCache.currentVersion
        else { return CostUsageCache(version: CostUsageCache.currentVersion, files: [:], buckets: [:]) }
        return decoded
    }

    static func save(_ cache: CostUsageCache, to url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".tmp-\(UUID().uuidString)")
        guard let data = try? JSONEncoder().encode(cache), (try? data.write(to: tmp, options: .atomic)) != nil
        else { return }
        _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }
}
