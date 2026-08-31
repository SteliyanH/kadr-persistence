import Testing
import Foundation
import CoreMedia
import CoreGraphics
import QuartzCore
import Kadr
@testable import KadrPersistence

/// Text animations round-trip, and are no longer reported as unsaveable.
///
/// This is a regression suite. v0.1–v0.3 reported *every* `TextAnimation` as
/// lossy, which meant a composition using kadr's own animation picker could not
/// be saved at all under the default strict encoding — the reference app hit it
/// the moment someone added a fade.
struct TextAnimationTests {

    private func overlayVideo(_ animation: any TextAnimation) -> Video {
        Video { VideoClip(url: URL(fileURLWithPath: "/tmp/a.mov")) }
            .overlay(TextOverlay("Hello").id(LayerID("t")).animation(animation))
    }

    @Test("A composition with a stock animation encodes without loss")
    func stockAnimationIsNotLossy() {
        for animation: any TextAnimation in [
            FadeIn(duration: CMTime(seconds: 0.5, preferredTimescale: 600)),
            SlideIn(from: .fromBottom, duration: CMTime(seconds: 0.8, preferredTimescale: 600)),
            ScaleUp(from: 0.2, duration: CMTime(seconds: 0.4, preferredTimescale: 600)),
        ] {
            #expect(KadrCoding.lossyContent(in: overlayVideo(animation)).isEmpty)
        }
    }

    @Test("The composition saves under strict encoding")
    func strictEncodeSucceeds() throws {
        let document = try KadrCoding.encode(
            overlayVideo(FadeIn(duration: CMTime(seconds: 0.5, preferredTimescale: 600)))
        )
        guard case let .text(overlay) = document.video.overlays.first else {
            return #expect(Bool(false), "expected a text overlay")
        }
        #expect(overlay.textAnimation?.kind == "fadeIn")
    }

    @Test("A fade round-trips its duration, start opacity and begin time")
    func fadeRoundTrips() throws {
        let original = FadeIn(
            duration: CMTime(value: 1, timescale: 30), from: 0.25, beginTime: 2.5
        )
        let restored = try KadrCoding.decode(KadrCoding.encode(overlayVideo(original)))
        let overlay = try #require(restored.overlays.first as? TextOverlay)
        let animation = try #require(overlay.textAnimation as? FadeIn)
        #expect(animation.duration == CMTime(value: 1, timescale: 30))
        #expect(animation.from == 0.25)
        #expect(animation.beginTime == 2.5)
    }

    @Test("A slide round-trips its direction — every one of them")
    func slideRoundTripsEveryDirection() throws {
        for direction: SlideIn.Direction in [.fromLeft, .fromRight, .fromTop, .fromBottom] {
            let original = SlideIn(from: direction, duration: CMTime(seconds: 1, preferredTimescale: 600))
            let restored = try KadrCoding.decode(KadrCoding.encode(overlayVideo(original)))
            let overlay = try #require(restored.overlays.first as? TextOverlay)
            let animation = try #require(overlay.textAnimation as? SlideIn)
            #expect(animation.direction == direction)
        }
    }

    @Test("A scale-up round-trips its starting scale")
    func scaleRoundTrips() throws {
        let restored = try KadrCoding.decode(
            KadrCoding.encode(overlayVideo(ScaleUp(from: 0.3, duration: CMTime(seconds: 0.6, preferredTimescale: 600))))
        )
        let overlay = try #require(restored.overlays.first as? TextOverlay)
        let animation = try #require(overlay.textAnimation as? ScaleUp)
        #expect(abs(animation.from - 0.3) < 0.0001)
    }

    @Test("An animation's duration keeps its timescale, like every other time")
    func durationStaysRational() throws {
        let original = FadeIn(duration: CMTime(value: 1, timescale: 30))
        let document = try KadrCoding.encode(overlayVideo(original))
        guard case let .text(overlay) = document.video.overlays.first else {
            return #expect(Bool(false))
        }
        #expect(overlay.textAnimation?.durationTimescale == 30)
        #expect(overlay.textAnimation?.durationValue == 1)
    }

    @Test("An overlay with no animation stays that way")
    func noAnimationStaysNil() throws {
        let video = Video { VideoClip(url: URL(fileURLWithPath: "/tmp/a.mov")) }
            .overlay(TextOverlay("Plain").id(LayerID("p")))
        let document = try KadrCoding.encode(video)
        guard case let .text(overlay) = document.video.overlays.first else {
            return #expect(Bool(false))
        }
        #expect(overlay.textAnimation == nil)
        let restored = try KadrCoding.decode(document)
        #expect((restored.overlays.first as? TextOverlay)?.textAnimation == nil)
    }

    @Test("A conformer this version doesn't know is still reported, not guessed")
    func unknownConformerIsStillReported() {
        struct Swirl: TextAnimation {
            func makeAnimations(for layer: CALayer) -> [CAAnimation] { [] }
        }
        let lost = KadrCoding.lossyContent(in: overlayVideo(Swirl()))
        #expect(lost.count == 1)
        #expect(lost.first?.kind == .textAnimation)
    }

    @Test("Bytes stay stable across a save/load/save cycle with an animation")
    func bytesAreStable() throws {
        let video = overlayVideo(SlideIn(from: .fromTop, duration: CMTime(seconds: 0.7, preferredTimescale: 600)))
        let first = try KadrCoding.data(for: video)
        let second = try KadrCoding.data(for: KadrCoding.video(from: first))
        #expect(first == second)
    }

    @Test("A document written before v0.4 decodes with no animation, not a failure")
    func olderDocumentsStillDecode() throws {
        // The field is optional and appended, which is why this is not a schema
        // bump: strip it and the document must still read.
        let data = try KadrCoding.data(for: overlayVideo(FadeIn(duration: CMTime(seconds: 0.5, preferredTimescale: 600))))
        var json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("textAnimation"))
        // Sorted keys put `textAnimation` last in its object, so it carries a
        // leading comma rather than a trailing one.
        json = json.replacingOccurrences(
            of: #",?"textAnimation":\{[^}]*\}"#,
            with: "",
            options: .regularExpression
        )
        #expect(!json.contains("textAnimation"))
        let restored = try KadrCoding.video(from: Data(json.utf8))
        #expect(restored.overlays.count == 1)
        #expect((restored.overlays.first as? TextOverlay)?.textAnimation == nil)
    }
}
