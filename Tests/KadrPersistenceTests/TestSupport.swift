import Foundation
import CoreGraphics
import Kadr
@testable import KadrPersistence

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum TestImages {
    /// A tiny opaque image. Content is irrelevant — every test that uses one is
    /// about identity, not pixels.
    static func solid(_ size: CGSize = CGSize(width: 4, height: 4)) -> PlatformImage {
        #if canImport(UIKit)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        #elseif canImport(AppKit)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.red.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
        #endif
    }
}

/// An `ImageStore` that hands out tokens and remembers what they meant.
///
/// **Stable for a given image instance**, which is what makes an encode →
/// decode → encode comparison meaningful: a store that minted a fresh token per
/// call would make every re-encode differ in the token alone, and the comparison
/// would fail for a reason that has nothing to do with the format. Real stores
/// behave this way too — a photo-library identifier or a file URL does not change
/// because you saved twice.
///
/// Keyed on instance identity rather than pixel content: this is testing that the
/// *token* survives the round trip, not that the package can hash a bitmap.
final class RecordingImageStore: ImageStore, @unchecked Sendable {
    private let lock = NSLock()
    private var images: [String: PlatformImage] = [:]
    private var tokensByImage: [ObjectIdentifier: String] = [:]
    private var next = 0

    /// Distinct tokens handed out, in order, so a test can assert how many
    /// distinct images were seen.
    private(set) var issued: [String] = []

    func token(for image: PlatformImage) throws -> String {
        lock.lock(); defer { lock.unlock() }
        let key = ObjectIdentifier(image)
        if let existing = tokensByImage[key] { return existing }
        next += 1
        let token = "image-\(next)"
        images[token] = image
        tokensByImage[key] = token
        issued.append(token)
        return token
    }

    func image(for token: String) throws -> PlatformImage {
        lock.lock(); defer { lock.unlock() }
        guard let image = images[token] else {
            throw PersistenceError.malformed("no such image: \(token)")
        }
        return image
    }
}

/// A store that always fails to resolve, for testing what a host sees when its
/// media has gone missing since the save.
struct BrokenImageStore: ImageStore {
    func token(for image: PlatformImage) throws -> String { "gone" }
    func image(for token: String) throws -> PlatformImage {
        throw PersistenceError.malformed("the image was deleted")
    }
}

extension URL {
    static func fixture(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/kadr-tests/\(name)") }
}
