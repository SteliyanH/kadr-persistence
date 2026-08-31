import Testing
import Foundation
import CoreMedia
import CoreImage
import QuartzCore
import Kadr
@testable import KadrPersistence

/// What happens when a composition holds something a file cannot hold.
///
/// The whole design turns on one rule: **never drop something silently**. These
/// tests hold that rule to it. Each case must either refuse the save, or save and
/// say what it left behind — never save and stay quiet.
struct LossTests {

    private var clip: VideoClip { VideoClip(url: .fixture("a.mov")) }

    // MARK: - Compositors

    @Test("A clip compositor refuses the save by default")
    func compositorRefuses() {
        let video = Video {
            clip.id(ClipID("hero")).compositor { image, _ in image }
        }
        #expect(throws: PersistenceError.self) {
            _ = try KadrCoding.encode(video)
        }
    }

    @Test("The refusal names the clip and says why, in a sentence a person can act on")
    func refusalIsLegible() throws {
        let video = Video { clip.id(ClipID("hero")).compositor { image, _ in image } }
        do {
            _ = try KadrCoding.encode(video)
            Issue.record("expected the encode to refuse")
        } catch let error as PersistenceError {
            guard case let .lossyContent(items) = error else {
                Issue.record("expected lossyContent, got \(error)")
                return
            }
            #expect(items.count == 1)
            #expect(items[0].kind == .compositor)
            #expect(items[0].location.contains("hero"))
            #expect(error.errorDescription?.contains("code, not data") == true)
            #expect(error.recoverySuggestion != nil)
        }
    }

    @Test("allowingLoss saves the rest of the composition intact")
    func allowingLossKeepsEverythingElse() throws {
        let video = Video {
            clip.id(ClipID("hero")).compositor { image, _ in image }.opacity(0.5)
            VideoClip(url: .fixture("b.mov")).trimmed(to: 0...3)
        }
        .preset(.tiktok)

        let document = try KadrCoding.encode(video, allowingLoss: true)
        #expect(document.video.clips.count == 2)
        #expect(document.video.preset.kind == "tiktok")
        guard case let .video(first) = document.video.clips[0] else { return #expect(Bool(false)) }
        #expect(first.opacity == 0.5)     // the clip survives; only its compositor is gone
    }

    @Test("A composition-level compositor is reported too")
    func multiInputCompositorIsReported() {
        let video = Video { clip }
            .compositor { images, _ in images.first ?? CIImage.empty() }
        let lost = KadrCoding.lossyContent(in: video)
        #expect(lost.contains { $0.kind == .multiInputCompositor })
    }

    // MARK: - Custom timing

    @Test("A custom timing closure is reported, not quietly recorded as linear")
    func customTimingIsReported() {
        let video = Video {
            clip.id(ClipID("fader")).opacity(1.0, animation: .keyframes([
                .at(0.0, value: 0.0), .at(1.0, value: 1.0),
            ], timing: .custom { $0 * $0 }))
        }
        let lost = KadrCoding.lossyContent(in: video)
        #expect(lost.count == 1)
        #expect(lost[0].kind == .customTimingFunction)
        #expect(lost[0].location.contains("fader"))
    }

    @Test("Built-in timing curves are not reported as lossy")
    func builtInTimingIsNotLossy() {
        for timing in [TimingFunction.linear, .easeIn, .easeOut, .easeInOut,
                       .cubicBezier(CGPoint(x: 0.2, y: 0), CGPoint(x: 0.8, y: 1))] {
            let video = Video {
                clip.opacity(1.0, animation: .keyframes([.at(0.0, value: 0.0)], timing: timing))
            }
            #expect(KadrCoding.lossyContent(in: video).isEmpty)
        }
    }

    // MARK: - Images

    @Test("An image with no store is reported rather than dropped")
    func imageWithoutStoreIsReported() {
        let video = Video { ImageClip(TestImages.solid(), duration: 2.0).id(ClipID("photo")) }
        let lost = KadrCoding.lossyContent(in: video)
        #expect(lost.count == 1)
        #expect(lost[0].kind == .image)
        #expect(lost[0].location.contains("photo"))
    }

    @Test("An image with no store refuses the save by default")
    func imageWithoutStoreRefuses() {
        let video = Video { ImageClip(TestImages.solid(), duration: 2.0) }
        #expect(throws: PersistenceError.self) { _ = try KadrCoding.encode(video) }
    }

    @Test("With a store, images are not lossy at all")
    func imagesWithStoreAreNotLossy() {
        let video = Video { ImageClip(TestImages.solid(), duration: 2.0) }
        #expect(KadrCoding.lossyContent(in: video, images: RecordingImageStore()).isEmpty)
    }

    @Test("An image overlay with no store is dropped from the document, and reported")
    func imageOverlayWithoutStore() throws {
        let video = Video { clip }
            .overlay(TextOverlay("kept"))
            .overlay(ImageOverlay(TestImages.solid()))
        let document = try KadrCoding.encode(video, allowingLoss: true)
        // The text overlay survives; the image overlay is omitted rather than
        // written with an empty token that would fail to resolve on open.
        #expect(document.video.overlays.count == 1)
        #expect(KadrCoding.lossyContent(in: video).contains { $0.kind == .image })
    }

    @Test("A text animation kadr ships is not reported — it round-trips")
    func stockTextAnimationIsNotReported() {
        // Until v0.4 every animation was reported, which made a composition
        // using kadr's own animation picker unsaveable under strict encoding.
        let video = Video { clip }
            .overlay(TextOverlay("Hi").id(LayerID("title")).animation(FadeIn(duration: 0.5)))
        #expect(KadrCoding.lossyContent(in: video).isEmpty)
    }

    @Test("A text animation this version cannot represent is reported")
    func unknownTextAnimationIsReported() {
        struct Swirl: TextAnimation {
            func makeAnimations(for layer: CALayer) -> [CAAnimation] { [] }
        }
        let video = Video { clip }
            .overlay(TextOverlay("Hi").id(LayerID("title")).animation(Swirl()))
        let lost = KadrCoding.lossyContent(in: video)
        #expect(lost.contains { $0.kind == .textAnimation })
        #expect(lost.first { $0.kind == .textAnimation }?.location.contains("title") == true)
    }

    // MARK: - The honest default

    @Test("A composition with nothing unrepresentable reports nothing")
    func cleanCompositionIsClean() {
        let video = Video {
            clip.trimmed(to: 0...5).filter(.sepia(intensity: 0.4)).opacity(0.9)
            Transition.fade(duration: 0.3)
            TitleSequence("End", duration: 2)
        }
        .audio { AudioTrack(url: .fixture("m.m4a")).volume(0.5) }
        .quality(.bitrate(5_000_000))
        #expect(KadrCoding.lossyContent(in: video).isEmpty)
    }

    @Test("Everything lossy in one composition is reported together, not one at a time")
    func lossesAccumulate() {
        let video = Video {
            clip.id(ClipID("a")).compositor { image, _ in image }
            VideoClip(url: .fixture("b.mov")).id(ClipID("b")).compositor { image, _ in image }
            ImageClip(TestImages.solid(), duration: 1).id(ClipID("c"))
        }
        let lost = KadrCoding.lossyContent(in: video)
        #expect(lost.count == 3)
        #expect(Set(lost.map(\.kind)) == [.compositor, .image])
        #expect(Set(lost.map(\.location)).count == 3)
    }
}
