import Testing
import Foundation
import CoreMedia
import Kadr
@testable import KadrPersistence

/// Documents committed to the repository, decoded on every run.
///
/// Every other test in this package encodes with today's code and reads it back
/// with today's code — which cannot detect a change that breaks *yesterday's*
/// files, because both sides move together. These read bytes that were written
/// once and never regenerated. If a format change stops an existing project
/// opening, it fails here, rather than in somebody's library.
///
/// `FixtureGeneration` writes the corpus and is disabled on purpose: a suite
/// that can rewrite its own evidence proves nothing.
struct FixtureCorpusTests {

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"),
            "fixture \(name).json is missing from the bundle"
        )
        return try Data(contentsOf: url)
    }

    private func document(_ name: String) throws -> KadrDocument {
        try JSONDecoder().decode(KadrDocument.self, from: fixture(name))
    }

    // MARK: - It still opens

    @Test("A schema-1 document still decodes into a composition")
    func schema1Decodes() throws {
        let video = try KadrCoding.video(from: fixture("schema-1-broad"), images: FixtureImageStore())
        #expect(video.clips.count == 5)
        #expect(video.overlays.count == 3)
        #expect(video.audioTracks.count == 1)
        #expect(video.captions.count == 1)
        #expect(video.crop != nil)
    }

    @Test("Its composition-level settings survive")
    func compositionSettingsSurvive() throws {
        let video = try KadrCoding.video(from: fixture("schema-1-broad"), images: FixtureImageStore())
        #expect(video.preset == .custom(width: 1080, height: 1920, frameRate: 30, codec: .hevc))
        #expect(video.quality == .bitrate(6_000_000))
    }

    @Test("Frame-exact times come back as the same rationals")
    func timesAreStillFrameExact() throws {
        let video = try KadrCoding.video(from: fixture("schema-1-broad"), images: FixtureImageStore())
        let hero = try #require(video.clips.first as? VideoClip)
        // Written as 30/30 and 150/30. Stored as seconds these would come back
        // as 1.0000000001-ish and no longer land on a frame boundary.
        #expect(hero.trimRange?.start == CMTime(value: 30, timescale: 30))
        #expect(hero.trimRange?.duration == CMTime(value: 150, timescale: 30))
        #expect(hero.trimRange?.start.timescale == 30)
    }

    @Test("Filter identities survive, not just the filters")
    func filterIdentitiesSurvive() throws {
        let video = try KadrCoding.video(from: fixture("schema-1-broad"), images: FixtureImageStore())
        let hero = try #require(video.clips.first as? VideoClip)
        #expect(hero.filterIDs == [FilterID("sepia-1"), FilterID("mono-1")])
        #expect(hero.filters.count == 2)
    }

    @Test("A nested track keeps its clips, offset and opacity")
    func nestedTrackSurvives() throws {
        let video = try KadrCoding.video(from: fixture("schema-1-broad"), images: FixtureImageStore())
        let track = try #require(video.clips.compactMap { $0 as? Track }.first)
        #expect(track.name == "overlayTrack")
        #expect(track.clips.count == 1)
        #expect(abs(track.opacityFactor - 0.7) < 0.0001)
    }

    @Test("Audio keeps its ramps and pitch algorithm")
    func audioSurvives() throws {
        let video = try KadrCoding.video(from: fixture("schema-1-broad"), images: FixtureImageStore())
        let track = try #require(video.audioTracks.first)
        #expect(track.volumeRamps.count == 1)
        #expect(track.pitchAlgorithm == .timeDomain)
        #expect(track.duckingLevel != nil)
    }

    @Test("A recursive aspect-fit size survives its nesting")
    func recursiveSizeSurvives() throws {
        let video = try KadrCoding.video(from: fixture("schema-1-broad"), images: FixtureImageStore())
        let overlay = try #require(video.overlays.compactMap { $0 as? ImageOverlay }.first)
        guard case let .aspectFit(within, aspect) = try #require(overlay.size) else {
            return #expect(Bool(false), "expected an aspectFit size")
        }
        #expect(abs(Double(aspect) - 1.5) < 0.0001)
        if case let .normalized(w, _) = within { #expect(abs(w - 0.4) < 0.0001) }
    }

    // MARK: - It still writes the same thing

    @Test("Re-encoding the fixture reproduces it byte for byte")
    func reEncodingIsIdentical() throws {
        // The strongest statement the corpus can make: today's encoder, fed
        // yesterday's document, writes yesterday's bytes. Any drift — a renamed
        // key, a reordered array, a time written as seconds — fails here with a
        // byte difference rather than passing quietly.
        let original = try fixture("schema-1-broad")
        let video = try KadrCoding.video(from: original, images: FixtureImageStore())
        let reencoded = try KadrCoding.data(for: video, images: FixtureImageStore())
        #expect(reencoded == original)
    }

    @Test("The fixture declares schema 1, and this build still reads it")
    func schemaIsStillSupported() throws {
        let document = try document("schema-1-broad")
        #expect(document.schema == 1)
        #expect(document.schema <= KadrDocument.currentSchema)
    }

    @Test("The fixture is a broad composition, not a token one")
    func fixtureIsBroad() throws {
        // A corpus that exercises one field proves one field. If the fixture is
        // ever regenerated from a thinner composition, this notices.
        let document = try document("schema-1-broad")
        let kinds = document.video.clips.map { clip -> String in
            switch clip {
            case .video: return "video"
            case .image: return "image"
            case .title: return "title"
            case .transition: return "transition"
            case .track: return "track"
            }
        }
        #expect(Set(kinds) == ["video", "image", "title", "transition", "track"])
        #expect(document.video.overlays.count == 3)
    }
}
