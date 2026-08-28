import Testing
import Foundation
import CoreMedia
import Kadr
@testable import KadrPersistence

/// Versioning, and what happens to a file this version should not be reading.
struct SchemaTests {

    private func document() throws -> KadrDocument {
        try KadrCoding.encode(Video { VideoClip(url: .fixture("a.mov")) })
    }

    @Test("A document written by this version declares the current schema")
    func currentSchemaIsStamped() throws {
        #expect(try document().schema == KadrDocument.currentSchema)
    }

    @Test("A document from the future is refused, not parsed on a best-effort basis")
    func futureSchemaIsRefused() throws {
        let future = KadrDocument(schema: KadrDocument.currentSchema + 1, video: try document().video)
        do {
            _ = try KadrCoding.decode(future)
            Issue.record("expected the decode to refuse")
        } catch let error as PersistenceError {
            guard case let .unsupportedSchema(found, supported) = error else {
                Issue.record("expected unsupportedSchema, got \(error)")
                return
            }
            #expect(found == KadrDocument.currentSchema + 1)
            #expect(supported == KadrDocument.currentSchema)
            #expect(error.errorDescription?.contains("newer version") == true)
            #expect(error.recoverySuggestion?.contains("Update") == true)
        }
    }

    @Test("Refusing the future is the point: a best-effort read would destroy the file")
    func futureSchemaIsNotSilentlyDowngraded() {
        // Reading a newer document, dropping the fields this version doesn't know,
        // and saving would erase them permanently. A refusal is the only behaviour
        // that cannot lose a user's work.
        let future = KadrDocument(schema: 99, video: VideoData(
            clips: [], audioTracks: [], preset: PresetData(kind: "auto", width: nil, height: nil, frameRate: nil, codec: nil),
            overlays: [], crop: nil,
            quality: QualityData(kind: "automatic", bitrate: nil, fileSizeBytes: nil), captions: []
        ))
        #expect(throws: PersistenceError.self) { _ = try KadrCoding.decode(future) }
    }

    @Test("An older schema is still readable")
    func olderSchemaIsAccepted() throws {
        let old = KadrDocument(schema: 0, video: try document().video)
        let video = try KadrCoding.decode(old)
        #expect(video.clips.count == 1)
    }

    // MARK: - Malformed input

    @Test("Bytes that aren't a document surface as malformed, not as a crash")
    func garbageBytes() {
        #expect(throws: PersistenceError.self) {
            _ = try KadrCoding.video(from: Data("not a project file".utf8))
        }
    }

    @Test("Empty data surfaces as malformed")
    func emptyData() {
        #expect(throws: PersistenceError.self) { _ = try KadrCoding.video(from: Data()) }
    }

    @Test("A clip discriminator naming a case that does not exist is rejected")
    func unknownClipKind() {
        let json = """
        {"schema":1,"video":{"audioTracks":[],"captions":[],"clips":[{"hologram":{}}],\
        "crop":null,"overlays":[],"preset":{"kind":"auto"},"quality":{"kind":"automatic"}}}
        """
        #expect(throws: PersistenceError.self) {
            _ = try KadrCoding.video(from: Data(json.utf8))
        }
    }

    @Test("An unknown filter name is rejected rather than silently becoming something else")
    func unknownFilterKind() throws {
        var document = try self.document()
        let clip = VideoClipData(
            url: "file:///tmp/a.mov", trimRange: nil, isReversed: false, isMuted: false,
            volumeLevel: 1.0, replacementAudioURL: nil, speedRate: 1.0, speedCurve: nil,
            filters: [FilterData(kind: "kaleidoscope", scalar: 1, url: nil, red: nil, green: nil, blue: nil, threshold: nil)],
            filterIDs: ["f1"], filterAnimations: [nil], clipID: nil, startTime: nil,
            transform: nil, transformAnimation: nil, opacity: nil, opacityAnimation: nil
        )
        document = KadrDocument(video: VideoData(
            clips: [.video(clip)], audioTracks: [], preset: document.video.preset,
            overlays: [], crop: nil, quality: document.video.quality, captions: []
        ))
        #expect(throws: PersistenceError.self) { _ = try KadrCoding.decode(document) }
    }

    @Test("A document referring to images without a store refuses, naming the token")
    func missingImageStore() throws {
        let store = RecordingImageStore()
        let video = Video { ImageClip(TestImages.solid(), duration: 2.0) }
        let data = try KadrCoding.data(for: video, images: store)
        do {
            _ = try KadrCoding.video(from: data)   // no store this time
            Issue.record("expected the decode to refuse")
        } catch let error as PersistenceError {
            guard case let .missingImageStore(token) = error else {
                Issue.record("expected missingImageStore, got \(error)")
                return
            }
            #expect(!token.isEmpty)
            #expect(error.errorDescription?.contains("images") == true)
        }
    }

    @Test("A store that can no longer resolve a token surfaces its own error")
    func brokenImageStore() throws {
        let store = RecordingImageStore()
        let data = try KadrCoding.data(
            for: Video { ImageClip(TestImages.solid(), duration: 2.0) }, images: store
        )
        #expect(throws: PersistenceError.self) {
            _ = try KadrCoding.video(from: data, images: BrokenImageStore())
        }
    }

    // MARK: - Format stability

    @Test("Keys are sorted, so two saves of the same project produce identical bytes")
    func bytesAreDeterministic() throws {
        let video = Video {
            VideoClip(url: .fixture("a.mov")).trimmed(to: 0...5)
            VideoClip(url: .fixture("b.mov"))
        }
        .audio { AudioTrack(url: .fixture("m.m4a")) }
        let first = try KadrCoding.data(for: video)
        let second = try KadrCoding.data(for: video)
        #expect(first == second)
        #expect(String(data: first, encoding: .utf8)?.hasPrefix("{\"schema\":1") == true)
    }

    @Test("The document is JSON a person can read and a diff can show")
    func documentIsLegibleJSON() throws {
        let data = try KadrCoding.data(for: Video { VideoClip(url: .fixture("a.mov")) })
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"schema\":1"))
        #expect(text.contains("a.mov"))
        #expect((try? JSONSerialization.jsonObject(with: data)) != nil)
    }
}
