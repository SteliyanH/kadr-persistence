import Testing
import Foundation
import CoreMedia
import CoreGraphics
import Kadr
@testable import KadrPersistence

/// Encode → decode → encode, comparing the two documents.
///
/// Comparing documents rather than compositions is deliberate: `Video` is not
/// `Equatable` (it holds existentials), and a second encode passes everything
/// through the *decode* side, so an asymmetry — a field written but never read —
/// shows up as a difference. A field missing from both sides still compares equal,
/// which is why `CompletenessTests` exists alongside this.
struct RoundTripTests {

    private func reencode(_ video: Video, images: (any ImageStore)? = nil) throws -> (KadrDocument, KadrDocument) {
        let first = try KadrCoding.encode(video, images: images)
        let restored = try KadrCoding.decode(first, images: images)
        let second = try KadrCoding.encode(restored, images: images)
        return (first, second)
    }

    private func expectStable(_ video: Video, images: (any ImageStore)? = nil,
                              _ comment: Comment? = nil) throws {
        let (first, second) = try reencode(video, images: images)
        #expect(first == second, comment ?? "the composition did not survive the round trip")
    }

    // MARK: - Clips

    @Test("A bare clip round-trips")
    func bareClip() throws {
        try expectStable(Video { VideoClip(url: .fixture("a.mov")) })
    }

    @Test("Every VideoClip modifier survives together")
    func fullyModifiedClip() throws {
        let video = Video {
            VideoClip(url: .fixture("a.mov"))
                .trimmed(to: 1...5)
                .reversed()
                .volume(0.4)
                .speed(.flat(1.5))
                .filter(.sepia(intensity: 0.3))
                .filter(.vignette(intensity: 0.6), animation: .keyframes([
                    .at(0.0, value: 0), .at(2.0, value: 1),
                ], timing: .easeInOut))
                .id(ClipID("hero"))
                .at(time: CMTime(seconds: 2, preferredTimescale: 600))
                .transform(Transform(center: .normalized(x: 0.4, y: 0.6), rotation: 0.3, scale: 1.2, anchor: .topLeft))
                .opacity(0.8)
        }
        try expectStable(video)
    }

    @Test("Filter identities survive, not just the filters")
    func filterIDsSurvive() throws {
        let video = Video {
            VideoClip(url: .fixture("a.mov"))
                .filter(.brightness(0.2))
                .filter(.contrast(1.4))
        }
        let original = video.clips.first as! VideoClip
        let restored = try KadrCoding.decode(KadrCoding.encode(video))
        let restoredClip = restored.clips.first as! VideoClip
        #expect(restoredClip.filterIDs == original.filterIDs)
        #expect(!original.filterIDs.isEmpty)
    }

    @Test("A muted clip stays muted, and a replaced-audio clip keeps its replacement")
    func audioReplacementAndMuting() throws {
        try expectStable(Video { VideoClip(url: .fixture("a.mov")).muted() })
        try expectStable(Video { VideoClip(url: .fixture("a.mov")).withAudio(.fixture("v.m4a")) })
    }

    @Test("A speed curve survives as a curve, not as a flat rate")
    func speedCurve() throws {
        let video = Video {
            VideoClip(url: .fixture("a.mov"))
                .speed(.curved(.keyframes([.at(0.0, value: 1.0), .at(3.0, value: 0.5)])))
        }
        let (first, second) = try reencode(video)
        #expect(first == second)
        guard case let .video(clip) = first.video.clips[0] else { return #expect(Bool(false)) }
        #expect(clip.speedCurve?.keyframes.count == 2)
    }

    @Test("Nested tracks round-trip, including their nesting")
    func nestedTracks() throws {
        let video = Video {
            Track(at: CMTime(seconds: 1, preferredTimescale: 600), name: "overlay") {
                VideoClip(url: .fixture("a.mov"))
                VideoClip(url: .fixture("b.mov")).opacity(0.5)
            }
            .opacity(0.7)
        }
        try expectStable(video)
    }

    @Test("Transitions round-trip, including slide direction")
    func transitions() throws {
        let video = Video {
            VideoClip(url: .fixture("a.mov"))
            Transition.slide(direction: .fromBottom, duration: 0.6)
            VideoClip(url: .fixture("b.mov"))
            Transition.dissolve(duration: 0.4)
            VideoClip(url: .fixture("c.mov"))
        }
        try expectStable(video)
        let document = try KadrCoding.encode(video)
        guard case let .transition(slide) = document.video.clips[1] else { return #expect(Bool(false)) }
        #expect(slide.kind == "slide")
        #expect(slide.direction == "fromBottom")
    }

    @Test("A title sequence round-trips with its full style")
    func titleSequence() throws {
        let style = TextStyle(
            fontName: "Menlo", fontSize: 48, color: .white, alignment: .center, weight: .bold,
            stroke: TextStroke(width: 2, color: .black),
            shadow: TextShadow(offset: CGSize(width: 1, height: 2), blur: 4)
        )
        let video = Video {
            TitleSequence("Chapter One", duration: 2.5, style: style, background: .black)
                .id(ClipID("title"))
                .opacity(0.9)
        }
        try expectStable(video)
    }

    @Test("An image clip round-trips through an ImageStore")
    func imageClipThroughStore() throws {
        let store = RecordingImageStore()
        let video = Video {
            ImageClip(TestImages.solid(), duration: 3.0)
                .background(.blue)
                .id(ClipID("photo"))
        }
        try expectStable(video, images: store)
        #expect(store.issued.count >= 1)
    }

    // MARK: - Composition level

    @Test("Audio tracks round-trip with every modifier, ramps included")
    func audioTracks() throws {
        let video = Video { VideoClip(url: .fixture("a.mov")) }
            .audio {
                AudioTrack(url: .fixture("music.m4a"))
                    .volume(0.6)
                    .fadeIn(1.0)
                    .fadeOut(2.0)
                    .ducking(0.2)
                    .at(time: 0.5)
                    .duration(20)
                    .crossfade(0.75)
                    .volumeRamp(start: 0.2, end: 0.9, during: 1.0...3.0)
                    .speed(1.25, algorithm: .timeDomain)
            }
        try expectStable(video)
        let document = try KadrCoding.encode(video)
        let track = document.video.audioTracks[0]
        #expect(track.volumeRamps.count == 1)
        #expect(track.pitchAlgorithm == "timeDomain")
    }

    @Test("The pitch algorithm is restored, not defaulted back to spectral")
    func pitchAlgorithmSurvives() throws {
        for algorithm in [AudioTimePitchAlgorithm.spectral, .timeDomain, .varispeed] {
            let video = Video { VideoClip(url: .fixture("a.mov")) }
                .audio { AudioTrack(url: .fixture("m.m4a")).speed(1.0, algorithm: algorithm) }
            let restored = try KadrCoding.decode(KadrCoding.encode(video))
            #expect(restored.audioTracks[0].pitchAlgorithm == algorithm)
        }
    }

    @Test("Export quality survives — every case")
    func quality() throws {
        for quality in [ExportQuality.automatic, .bitrate(4_000_000), .fileSize(bytes: 25_000_000)] {
            let video = Video { VideoClip(url: .fixture("a.mov")) }.quality(quality)
            let restored = try KadrCoding.decode(KadrCoding.encode(video))
            #expect(restored.quality == quality)
        }
    }

    @Test("Presets survive — every case")
    func presets() throws {
        let presets: [Preset] = [
            .auto, .reelsAndShorts, .tiktok, .square, .cinema,
            .custom(width: 1440, height: 1440, frameRate: 60, codec: .hevc),
        ]
        for preset in presets {
            let video = Video { VideoClip(url: .fixture("a.mov")) }.preset(preset)
            let restored = try KadrCoding.decode(KadrCoding.encode(video))
            #expect(restored.preset == preset)
        }
    }

    @Test("A crop region survives")
    func crop() throws {
        let video = Video { VideoClip(url: .fixture("a.mov")) }
            .crop(at: .percent(x: 40, y: 60), size: .pixels(width: 720, height: 720), anchor: .topRight)
        try expectStable(video)
        let restored = try KadrCoding.decode(KadrCoding.encode(video))
        #expect(restored.crop?.anchor == .topRight)
    }

    @Test("Captions survive with their exact time ranges")
    func captions() throws {
        let video = Video { VideoClip(url: .fixture("a.mov")) }
            .captions([
                Caption(text: "first", timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 30))),
                Caption(text: "second", timeRange: CMTimeRange(start: CMTime(value: 30, timescale: 30), duration: CMTime(value: 45, timescale: 30))),
            ])
        try expectStable(video)
        let restored = try KadrCoding.decode(KadrCoding.encode(video))
        #expect(restored.captions.count == 2)
        #expect(restored.captions[1].timeRange.start == CMTime(value: 30, timescale: 30))
    }

    @Test("A text overlay survives with its full style and visibility window")
    func textOverlay() throws {
        let video = Video { VideoClip(url: .fixture("a.mov")) }
            .overlay(
                TextOverlay("Hello", style: TextStyle(fontSize: 64, color: .yellow, weight: .medium))
                    .position(.normalized(x: 0.5, y: 0.2))
                    .size(.percent(width: 80, height: 20))
                    .anchor(.top)
                    .opacity(0.85)
                    .id(LayerID("caption-1"))
                    .visible(during: 1.0...4.0)
            )
        try expectStable(video)
    }

    @Test("Image and sticker overlays survive through a store")
    func imageAndStickerOverlays() throws {
        let store = RecordingImageStore()
        let video = Video { VideoClip(url: .fixture("a.mov")) }
            .overlay(
                ImageOverlay(TestImages.solid())
                    .position(.normalized(x: 0.2, y: 0.2))
                    .size(.normalized(width: 0.3, height: 0.3))
                    .id(LayerID("logo"))
            )
            .overlay(
                StickerOverlay(TestImages.solid())
                    .position(.normalized(x: 0.8, y: 0.8))
                    .rotation(0.5)
                    .shadow(StickerOverlay.Shadow(color: .black, radius: 12, offset: CGSize(width: 2, height: 3), opacity: 0.6))
            )
        try expectStable(video, images: store)
        #expect(store.issued.count == 2)
    }

    @Test("An overlay's position and size animations survive")
    func overlayAnimations() throws {
        let store = RecordingImageStore()
        let video = Video { VideoClip(url: .fixture("a.mov")) }
            .overlay(
                ImageOverlay(TestImages.solid())
                    .position(.normalized(x: 0.1, y: 0.1), animation: .keyframes([
                        .at(0.0, value: Position.normalized(x: 0.1, y: 0.1)),
                        .at(2.0, value: Position.normalized(x: 0.9, y: 0.9)),
                    ], timing: .easeOut))
                    .size(.normalized(width: 0.2, height: 0.2), animation: .keyframes([
                        .at(0.0, value: Size.normalized(width: 0.2, height: 0.2)),
                        .at(2.0, value: Size.normalized(width: 0.5, height: 0.5)),
                    ]))
            )
        try expectStable(video, images: store)
    }

    @Test("A nested aspect-fit size survives its recursion")
    func recursiveSize() throws {
        let store = RecordingImageStore()
        let video = Video { VideoClip(url: .fixture("a.mov")) }
            .overlay(
                ImageOverlay(TestImages.solid())
                    .size(.aspectFit(within: .normalized(width: 0.5, height: 0.5), sourceAspect: 1.777))
            )
        try expectStable(video, images: store)
    }

    // MARK: - Bytes

    @Test("JSON bytes are stable across a save/load/save cycle")
    func bytesAreStable() throws {
        let video = Video {
            VideoClip(url: .fixture("a.mov")).trimmed(to: 0...5).filter(.mono)
            Transition.fade(duration: 0.5)
            VideoClip(url: .fixture("b.mov"))
        }
        .preset(.reelsAndShorts)
        .quality(.bitrate(6_000_000))
        .audio { AudioTrack(url: .fixture("m.m4a")).volume(0.3) }

        let first = try KadrCoding.data(for: video)
        let second = try KadrCoding.data(for: KadrCoding.video(from: first))
        #expect(first == second)
    }

    @Test("A frame-accurate time survives as the same rational, not as rounded seconds")
    func framesSurviveExactly() throws {
        // 1/30 s is not representable in binary floating point. Stored as seconds
        // it comes back as 0.0333…, which is no longer frame 1 of a 30 fps timeline.
        let oneFrame = CMTime(value: 1, timescale: 30)
        let video = Video {
            VideoClip(url: .fixture("a.mov"))
                .trimmed(to: CMTimeRange(start: oneFrame, duration: CMTime(value: 90, timescale: 30)))
        }
        let restored = try KadrCoding.decode(KadrCoding.encode(video))
        let clip = restored.clips[0] as! VideoClip
        #expect(clip.trimRange?.start == oneFrame)
        #expect(clip.trimRange?.start.timescale == 30)
        #expect(clip.trimRange?.duration == CMTime(value: 90, timescale: 30))
    }

    @Test("An empty composition round-trips rather than throwing")
    func emptyComposition() throws {
        try expectStable(Video { })
    }
}
