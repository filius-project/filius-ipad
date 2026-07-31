import Foundation
import UIKit

enum TopologyParityAssetLoader {
    private final class CacheEntry {
        let image: UIImage?

        init(image: UIImage?) {
            self.image = image
        }
    }

    private static let cache: NSCache<NSString, CacheEntry> = {
        let cache = NSCache<NSString, CacheEntry>()
        cache.countLimit = 64
        return cache
    }()
    private static let lock = NSLock()
#if targetEnvironment(simulator)
    private static var decodeAttemptsByKey: [String: Int] = [:]
#endif

    static func load(relativePath: String, bundle: Bundle = .main) -> UIImage? {
        guard !relativePath.isEmpty else { return nil }

        let cacheKey = bundle.bundlePath + "\u{0}" + relativePath
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache.object(forKey: cacheKey as NSString) {
            return cached.image
        }

#if targetEnvironment(simulator)
        decodeAttemptsByKey[cacheKey, default: 0] += 1
#endif
        let image = decode(relativePath: relativePath, bundle: bundle)
        cache.setObject(CacheEntry(image: image), forKey: cacheKey as NSString)
        return image
    }

    private static func decode(relativePath: String, bundle: Bundle) -> UIImage? {
        let bundleRelativePath = "JavaParity/\(relativePath)"
        if let directURL = bundle.resourceURL?.appendingPathComponent(bundleRelativePath),
           FileManager.default.fileExists(atPath: directURL.path),
           let image = UIImage(contentsOfFile: directURL.path) {
            return image
        }

        let nsPath = bundleRelativePath as NSString
        let folder = nsPath.deletingPathExtension
        let ext = nsPath.pathExtension
        guard !ext.isEmpty,
              let fallbackURL = bundle.url(forResource: folder, withExtension: ext)
        else {
            return nil
        }
        return UIImage(contentsOfFile: fallbackURL.path)
    }

#if targetEnvironment(simulator)
    static func resetCacheForTesting() {
        lock.lock()
        cache.removeAllObjects()
        decodeAttemptsByKey.removeAll()
        lock.unlock()
    }

    static func decodeAttemptCountForTesting(relativePath: String, bundle: Bundle = .main) -> Int {
        let cacheKey = bundle.bundlePath + "\u{0}" + relativePath
        lock.lock()
        defer { lock.unlock() }
        return decodeAttemptsByKey[cacheKey, default: 0]
    }
#endif
}
