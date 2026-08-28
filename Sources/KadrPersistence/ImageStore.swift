import Foundation
import Kadr

/// How the host names its images, so a document can refer to them.
///
/// An ``Kadr/ImageClip`` holds a `PlatformImage` — decoded pixels, with no record
/// of where they came from. A document cannot write that down: embedding the bytes
/// would turn a small project file into a large one (a ten-photo slideshow at full
/// resolution is on the order of a hundred megabytes of base64), and every editor
/// worth the name references its media rather than swallowing it.
///
/// So the identity has to come from the host, which is the only layer that knows
/// it — a photo library identifier, a file URL, a row id. Supply a store and images
/// round-trip; supply nothing and they are reported as ``Lossy/Kind/image`` rather
/// than silently dropped.
///
/// ```swift
/// struct FileImageStore: ImageStore {
///     let directory: URL
///     func token(for image: PlatformImage) throws -> String { /* write, return name */ }
///     func image(for token: String) throws -> PlatformImage { /* read it back */ }
/// }
///
/// let data = try KadrCoding.data(for: video, images: FileImageStore(directory: mediaDirectory))
/// ```
///
/// Tokens are opaque to this package: it stores the string and hands it back. Any
/// stable string will do, as long as the same store can resolve it later.
public protocol ImageStore: Sendable {

    /// A stable, resolvable name for `image`.
    ///
    /// Called once per image at encode time. Throwing propagates out of
    /// ``KadrCoding/encode(_:allowingLoss:images:)`` unchanged.
    func token(for image: PlatformImage) throws -> String

    /// The image `token` names.
    ///
    /// - Throws: when the token no longer resolves — the file was deleted, the
    ///   photo removed from the library. Prefer throwing over substituting a
    ///   placeholder; the caller can decide what a missing image means.
    func image(for token: String) throws -> PlatformImage
}
