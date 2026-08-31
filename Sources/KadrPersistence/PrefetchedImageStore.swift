import Foundation
import Kadr

/// An ``ImageStore`` over images you have already resolved.
///
/// ## The problem this solves
///
/// ``ImageStore`` is synchronous. That fits files and in-memory bytes, and it
/// does not fit a photo library: resolving a `PHAsset` means `PHImageManager`,
/// which is callback-based. A host backing its images with the photo library
/// therefore had nowhere to put the `await`.
///
/// The obvious answer — an async `ImageStore`, and async `encode` / `decode` to
/// match — was rejected, because it makes the encode path async for *every*
/// consumer, including the many with no images at all, to serve the one case
/// that needs it.
///
/// This is the other answer: resolve first, then encode. The `await` stays in
/// the layer that already had one, and the format's surface stays synchronous.
///
/// ```swift
/// // 1. Resolve, asynchronously, in the layer that owns the async.
/// var images: [String: PlatformImage] = [:]
/// for id in assetIdentifiers {
///     images["photo:\(id)"] = try await photoLibrary.image(for: id)
/// }
///
/// // 2. Encode or decode, synchronously.
/// let store = PrefetchedImageStore(images)
/// let video = try KadrCoding.video(from: data, images: store)
/// ```
///
/// ## Getting the tokens to resolve
///
/// Decoding needs the tokens *before* it runs, which is a chicken-and-egg
/// problem only until you notice the document is readable on its own:
/// ``PrefetchedImageStore/tokens(in:)`` walks a decoded ``KadrDocument`` and
/// returns every image token it refers to, including inside tracks. Decode the
/// JSON, ask for the tokens, resolve them, then build the composition.
///
/// ## Encoding
///
/// Encoding is the easier direction: you already hold the images, so the
/// mapping is yours to choose. Supply `token(for:)` by seeding the store with
/// the tokens you intend — or use ``FileImageStore``, which has no async
/// problem because a file is a file.
///
/// Added in v0.6.
public struct PrefetchedImageStore: ImageStore {

    private let byToken: [String: PlatformImage]
    private let tokenForImage: [ObjectIdentifier: String]

    /// Create a store from token-to-image pairs you have already resolved.
    public init(_ images: [String: PlatformImage]) {
        byToken = images
        // The reverse map, so encoding a composition built from these images
        // reproduces the same tokens rather than inventing new ones.
        var reverse: [ObjectIdentifier: String] = [:]
        for (token, image) in images {
            reverse[ObjectIdentifier(image)] = token
        }
        tokenForImage = reverse
    }

    public func token(for image: PlatformImage) throws -> String {
        guard let token = tokenForImage[ObjectIdentifier(image)] else {
            // Refused rather than invented: a made-up token would encode
            // cleanly and resolve to nothing on the next open, which is the
            // silent-loss failure this package exists to avoid.
            throw PersistenceError.imageNotEncodable
        }
        return token
    }

    public func image(for token: String) throws -> PlatformImage {
        guard let image = byToken[token] else {
            throw PersistenceError.imageUnresolvable(token: token)
        }
        return image
    }
}

extension PrefetchedImageStore {

    /// Every image token a document refers to, including inside tracks.
    ///
    /// Call this on a decoded ``KadrDocument`` to learn what to resolve before
    /// building the composition:
    ///
    /// ```swift
    /// let document = try JSONDecoder().decode(KadrDocument.self, from: data)
    /// let needed = PrefetchedImageStore.tokens(in: document)
    /// let store = PrefetchedImageStore(try await resolve(needed))
    /// let video = try KadrCoding.decode(document, images: store)
    /// ```
    public static func tokens(in document: KadrDocument) -> Set<String> {
        var found: Set<String> = []

        func walk(_ clips: [ClipData]) {
            for clip in clips {
                switch clip {
                case .image(let data): found.insert(data.imageToken)
                case .track(let data): walk(data.clips)
                case .video, .title, .transition: break
                }
            }
        }
        walk(document.video.clips)

        for overlay in document.video.overlays {
            switch overlay {
            case .image(let data):   found.insert(data.imageToken)
            case .sticker(let data): found.insert(data.imageToken)
            case .text: break
            }
        }
        return found
    }
}
