import Testing
import Foundation
import CoreMedia
import CoreGraphics
import Kadr
@testable import KadrPersistence

/// Tests for `PrefetchedImageStore` — the resolve-then-encode answer to an
/// asynchronous image source.
struct PrefetchedImageStoreTests {

    @Test("An image resolves under the token it was registered with")
    func resolvesByToken() throws {
        let image = TestImages.solid()
        let store = PrefetchedImageStore(["photo:abc": image])
        #expect(try store.image(for: "photo:abc") === image)
    }

    @Test("Encoding reproduces the token it was given, not a new one")
    func encodingReusesTheToken() throws {
        let image = TestImages.solid()
        let store = PrefetchedImageStore(["photo:abc": image])
        #expect(try store.token(for: image) == "photo:abc")
    }

    @Test("An unregistered image is refused, never given an invented token")
    func unregisteredImageIsRefused() {
        let store = PrefetchedImageStore(["photo:abc": TestImages.solid()])
        // An invented token would encode cleanly and resolve to nothing on the
        // next open — the silent loss this package exists to prevent.
        #expect(throws: PersistenceError.self) {
            _ = try store.token(for: TestImages.solid())
        }
    }

    @Test("An unknown token reports which one")
    func unknownTokenIsReported() {
        let store = PrefetchedImageStore([:])
        do {
            _ = try store.image(for: "photo:missing")
            Issue.record("expected a refusal")
        } catch let error as PersistenceError {
            guard case let .imageUnresolvable(token) = error else {
                Issue.record("expected imageUnresolvable, got \(error)")
                return
            }
            #expect(token == "photo:missing")
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    // MARK: - Finding what to resolve

    @Test("Tokens are collected from clips, tracks and overlays alike")
    func tokensAreCollectedEverywhere() throws {
        let store = RecordingImageStore()
        let video = Video {
            ImageClip(TestImages.solid(), duration: 2.0)
            Track { ImageClip(TestImages.solid(CGSize(width: 6, height: 6)), duration: 1.0) }
        }
        .overlay(ImageOverlay(TestImages.solid(CGSize(width: 8, height: 8))))
        .overlay(StickerOverlay(TestImages.solid(CGSize(width: 10, height: 10))))

        let document = try KadrCoding.encode(video, images: store)
        let tokens = PrefetchedImageStore.tokens(in: document)

        // One nested inside a Track, two in overlays, one top-level clip.
        #expect(tokens.count == 4)
        #expect(tokens.allSatisfy { !$0.isEmpty })
    }

    @Test("A composition with no images asks for nothing")
    func noImagesMeansNoTokens() throws {
        let document = try KadrCoding.encode(
            Video { VideoClip(url: URL(fileURLWithPath: "/tmp/a.mov")) }
        )
        #expect(PrefetchedImageStore.tokens(in: document).isEmpty)
    }

    // MARK: - The documented flow, end to end

    @Test("Resolve, then decode — the pattern the docs describe")
    func resolveThenDecode() throws {
        // 1. A document written by some other store.
        let source = RecordingImageStore()
        let data = try KadrCoding.data(
            for: Video { ImageClip(TestImages.solid(), duration: 3.0).id(ClipID("photo")) },
            images: source
        )

        // 2. Read the document on its own and ask what it needs. This is the
        //    step that makes a synchronous store workable against an async
        //    source: the tokens are knowable before the composition is built.
        let document = try JSONDecoder().decode(KadrDocument.self, from: data)
        let needed = PrefetchedImageStore.tokens(in: document)
        #expect(needed.count == 1)

        // 3. Resolve them — asynchronously in a real app — then decode.
        var resolved: [String: PlatformImage] = [:]
        for token in needed { resolved[token] = try source.image(for: token) }

        let video = try KadrCoding.decode(document, images: PrefetchedImageStore(resolved))
        #expect(video.clips.count == 1)
        #expect(video.clips.first?.clipID == ClipID("photo"))
    }

    @Test("A round trip through the prefetched store is byte-stable")
    func roundTripIsStable() throws {
        let image = TestImages.solid()
        let store = PrefetchedImageStore(["photo:abc": image])
        let video = Video { ImageClip(image, duration: 2.0) }
        let first = try KadrCoding.data(for: video, images: store)
        let second = try KadrCoding.data(for: KadrCoding.video(from: first, images: store), images: store)
        #expect(first == second)
    }
}
