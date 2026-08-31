import Testing
import Foundation
import CoreMedia
import Kadr
@testable import KadrPersistence

/// Tests for `FileImageStore`.
struct FileImageStoreTests {

    private func makeStore() throws -> (FileImageStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("file-store-\(UUID().uuidString)")
        return (try FileImageStore(directory: dir), dir)
    }

    private func files(in dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    @Test("The directory is created if it isn't there")
    func directoryIsCreated() throws {
        let (_, dir) = try makeStore()
        #expect(FileManager.default.fileExists(atPath: dir.path))
    }

    @Test("An image is written once and named for its own bytes")
    func imageIsWrittenAndHashed() throws {
        let (store, dir) = try makeStore()
        let token = try store.token(for: TestImages.solid())
        #expect(token.hasPrefix("file:"))
        #expect(token.hasSuffix(".png"))
        #expect(files(in: dir).count == 1)
    }

    @Test("The token is relative, so it survives the container path changing")
    func tokenIsRelative() throws {
        let (store, dir) = try makeStore()
        let token = try store.token(for: TestImages.solid())
        // The whole point: an iOS container UUID changes between installs, so an
        // absolute path written into a project file can point nowhere later.
        #expect(!token.contains("/"))
        #expect(!token.contains(dir.path))
    }

    @Test("A store rebuilt over the same directory resolves an old token")
    func tokenSurvivesANewStore() throws {
        let (store, dir) = try makeStore()
        let token = try store.token(for: TestImages.solid())

        // Same directory, fresh store — the case a relaunch produces.
        let reopened = try FileImageStore(directory: dir)
        #expect(throws: Never.self) { _ = try reopened.image(for: token) }
    }

    @Test("A directory that moved still resolves, because tokens are relative")
    func tokenSurvivesTheDirectoryMoving() throws {
        let (store, dir) = try makeStore()
        let token = try store.token(for: TestImages.solid())

        // Stand in for a container UUID change: same files, different path.
        let moved = FileManager.default.temporaryDirectory
            .appendingPathComponent("moved-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: dir, to: moved)

        let reopened = try FileImageStore(directory: moved)
        #expect(throws: Never.self) { _ = try reopened.image(for: token) }
    }

    @Test("The same image twice is stored once and keeps one token")
    func contentAddressingDeduplicates() throws {
        let (store, dir) = try makeStore()
        let image = TestImages.solid()
        let first = try store.token(for: image)
        let second = try store.token(for: image)
        #expect(first == second)
        #expect(files(in: dir).count == 1)
    }

    @Test("Two identical images from different instances share one file")
    func identicalBytesShareAFile() throws {
        let (store, dir) = try makeStore()
        let a = try store.token(for: TestImages.solid())
        let b = try store.token(for: TestImages.solid())   // separate instance, same pixels
        #expect(a == b)
        #expect(files(in: dir).count == 1)
    }

    @Test("Re-encoding an unchanged composition produces identical bytes")
    func encodingIsStable() throws {
        let (store, _) = try makeStore()
        let video = Video { ImageClip(TestImages.solid(), duration: 2.0).id(ClipID("photo")) }
        let first = try KadrCoding.data(for: video, images: store)
        let second = try KadrCoding.data(for: video, images: store)
        #expect(first == second)
    }

    @Test("A composition round-trips through the store")
    func compositionRoundTrips() throws {
        let (store, dir) = try makeStore()
        let video = Video {
            ImageClip(TestImages.solid(), duration: 3.0).id(ClipID("photo"))
            VideoClip(url: URL(fileURLWithPath: "/tmp/a.mov")).trimmed(to: 0...2)
        }
        let data = try KadrCoding.data(for: video, images: store)

        let reopened = try FileImageStore(directory: dir)
        let restored = try KadrCoding.video(from: data, images: reopened)
        #expect(restored.clips.count == 2)
        #expect(restored.clips.first?.clipID == ClipID("photo"))
    }

    @Test("Images are not lossy when a store is supplied")
    func imagesAreNotLossy() throws {
        let (store, _) = try makeStore()
        let video = Video { ImageClip(TestImages.solid(), duration: 1.0) }
        #expect(KadrCoding.lossyContent(in: video, images: store).isEmpty)
    }

    // MARK: - Pruning

    @Test("Pruning removes what the composition no longer refers to")
    func pruneRemovesOrphans() throws {
        let (store, dir) = try makeStore()
        let kept = try store.token(for: TestImages.solid(CGSize(width: 4, height: 4)))
        _ = try store.token(for: TestImages.solid(CGSize(width: 8, height: 8)))
        #expect(files(in: dir).count == 2)

        let deleted = try store.prune(keeping: [kept])
        #expect(deleted == 1)
        #expect(files(in: dir).count == 1)
        #expect(throws: Never.self) { _ = try store.image(for: kept) }
    }

    @Test("Pruning nothing keeps everything")
    func pruneIsNotDestructiveByDefault() throws {
        let (store, dir) = try makeStore()
        let a = try store.token(for: TestImages.solid(CGSize(width: 4, height: 4)))
        let b = try store.token(for: TestImages.solid(CGSize(width: 8, height: 8)))
        #expect(try store.prune(keeping: [a, b]) == 0)
        #expect(files(in: dir).count == 2)
    }

    // MARK: - Failure

    @Test("A token whose file is gone reports which token, not a crash")
    func missingFileIsReported() throws {
        let (store, dir) = try makeStore()
        let token = try store.token(for: TestImages.solid())
        try FileManager.default.removeItem(at: #require(store.url(for: token)))

        let reopened = try FileImageStore(directory: dir)
        do {
            _ = try reopened.image(for: token)
            Issue.record("expected a refusal")
        } catch let error as PersistenceError {
            guard case let .imageUnresolvable(reported) = error else {
                Issue.record("expected imageUnresolvable, got \(error)")
                return
            }
            #expect(reported == token)
            #expect(error.errorDescription?.isEmpty == false)
            #expect(error.recoverySuggestion?.isEmpty == false)
        }
    }

    @Test("A token from another store's scheme is not claimed")
    func foreignTokensAreNotClaimed() throws {
        let (store, _) = try makeStore()
        #expect(store.url(for: "png:abc123") == nil)
    }

    @Test("An absolute legacy token still resolves, so old projects keep opening")
    func absoluteLegacyTokensResolve() throws {
        let (store, _) = try makeStore()
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-\(UUID().uuidString).png")
        try #require(FileImageStore.pngData(from: TestImages.solid())).write(to: scratch)

        // Hand-rolled stores wrote absolute paths. Nothing here produces one,
        // but a document containing one must still open.
        let legacy = "file:\(scratch.path)"
        #expect(store.url(for: legacy)?.path == scratch.path)
        #expect(throws: Never.self) { _ = try store.image(for: legacy) }
    }
}
