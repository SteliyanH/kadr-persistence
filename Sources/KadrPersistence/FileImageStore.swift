import Foundation
import CryptoKit
import Kadr

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// An ``ImageStore`` that keeps images as files in a directory you nominate.
///
/// This is the store most apps want and would otherwise write themselves: a
/// slideshow whose photos live in the app's own container, referenced by the
/// project rather than embedded in it.
///
/// ```swift
/// let images = try FileImageStore(directory: mediaDirectory)
/// let data = try KadrCoding.data(for: video, images: images)
/// let restored = try KadrCoding.video(from: data, images: images)
/// ```
///
/// ## Tokens are relative, on purpose
///
/// A token is `file:<name>.png`, resolved against ``directory`` — never an
/// absolute path. That is not tidiness; it is the difference between a project
/// that survives a reinstall and one that doesn't.
///
/// An iOS app's container lives at
/// `/var/mobile/Containers/Data/Application/<UUID>/`, and **that UUID changes**
/// — on reinstall, on restore from backup, sometimes across an OS update. An
/// absolute path written into a project file on Monday can point nowhere on
/// Friday, with the project itself perfectly intact. Storing the name and
/// resolving it against a directory the app locates at runtime is what makes
/// the reference durable.
///
/// ## Names are content hashes
///
/// The file is named for the SHA-256 of its own PNG bytes, which buys two
/// things: the same image imported twice is stored once, and a token is
/// **stable across saves**. A store that minted a fresh name per encode would
/// rewrite every byte of the project file on every save, defeating the
/// format's sorted-key determinism and making "is this project dirty?"
/// unanswerable.
///
/// Added in v0.5.
public final class FileImageStore: ImageStore, @unchecked Sendable {

    /// Where images are kept. Tokens resolve against this.
    public let directory: URL

    private let fileManager: FileManager
    private let lock = NSLock()
    private var cache: [String: PlatformImage] = [:]
    private var tokensByImage: [ObjectIdentifier: String] = [:]

    /// Create a store over `directory`, creating it if needed.
    ///
    /// - Throws: if the directory cannot be created.
    public init(directory: URL, fileManager: FileManager = .default) throws {
        self.directory = directory
        self.fileManager = fileManager
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    // MARK: - ImageStore

    public func token(for image: PlatformImage) throws -> String {
        lock.lock()
        if let known = tokensByImage[ObjectIdentifier(image)] {
            lock.unlock()
            return known
        }
        lock.unlock()

        guard let png = FileImageStore.pngData(from: image) else {
            throw PersistenceError.imageNotEncodable
        }
        let name = "\(FileImageStore.hex(SHA256.hash(data: png))).png"
        let token = "file:\(name)"
        let url = directory.appendingPathComponent(name)

        // Content-addressed, so an existing file with this name is byte-identical
        // and rewriting it would be pure churn.
        if !fileManager.fileExists(atPath: url.path) {
            try png.write(to: url, options: .atomic)
        }

        lock.lock()
        tokensByImage[ObjectIdentifier(image)] = token
        cache[token] = image
        lock.unlock()
        return token
    }

    public func image(for token: String) throws -> PlatformImage {
        lock.lock()
        if let cached = cache[token] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let url = url(for: token),
              let data = try? Data(contentsOf: url),
              let image = PlatformImage(data: data)
        else {
            throw PersistenceError.imageUnresolvable(token: token)
        }

        lock.lock()
        cache[token] = image
        tokensByImage[ObjectIdentifier(image)] = token
        lock.unlock()
        return image
    }

    // MARK: - Housekeeping

    /// Delete every stored image not named by `tokens`.
    ///
    /// Call after a save, with the tokens the saved composition refers to.
    /// Without it the directory keeps the bytes of every image ever removed
    /// from the project.
    ///
    /// - Returns: the number of files deleted.
    @discardableResult
    public func prune(keeping tokens: Set<String>) throws -> Int {
        let names = Set(tokens.compactMap { name(for: $0) })
        let contents = try fileManager.contentsOfDirectory(atPath: directory.path)
        var deleted = 0
        for file in contents where !names.contains(file) {
            try fileManager.removeItem(at: directory.appendingPathComponent(file))
            deleted += 1
        }
        lock.lock()
        cache = cache.filter { tokens.contains($0.key) }
        lock.unlock()
        return deleted
    }

    /// The file a token names, or `nil` if the token isn't one of ours.
    ///
    /// Absolute tokens — which earlier hand-rolled stores wrote — resolve as
    /// paths so old projects keep opening, but nothing here produces one.
    public func url(for token: String) -> URL? {
        guard let name = name(for: token) else { return nil }
        if name.hasPrefix("/") { return URL(fileURLWithPath: name) }
        if let absolute = URL(string: name), absolute.scheme != nil { return absolute }
        return directory.appendingPathComponent(name)
    }

    private func name(for token: String) -> String? {
        guard token.hasPrefix("file:") else { return nil }
        return String(token.dropFirst("file:".count))
    }

    // MARK: - Platform

    private static func hex(_ digest: SHA256Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    static func pngData(from image: PlatformImage) -> Data? {
        #if canImport(UIKit)
        return image.pngData()
        #else
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
        #endif
    }
}
