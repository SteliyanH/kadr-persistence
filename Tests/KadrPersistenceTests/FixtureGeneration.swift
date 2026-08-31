import Testing
import Foundation
import CoreMedia
import CoreGraphics
import Kadr
@testable import KadrPersistence

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Regenerates the committed fixture documents.
///
/// Disabled by design — it *writes* the files the corpus tests read, so running
/// it as part of the suite would let a format regression rewrite its own
/// evidence. Enable it deliberately, once, when a schema bump means the corpus
/// needs a new member, and commit what it produces.
struct FixtureGeneration {

    @Test(.disabled("Writes the fixture corpus. Run deliberately, then commit the output."))
    func regenerateSchema1() throws {
        let video = FixtureCompositions.broad()
        let data = try KadrCoding.data(for: video, images: FixtureImageStore())
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/schema-1-broad.json")
        try data.write(to: url)
    }
}

/// The composition the corpus is built from.
///
/// Deliberately broad: every clip kind, a nested track, a transition, filters
/// with identities, animations, audio with ramps, all three overlay kinds, crop,
/// captions, and a non-default preset and quality. A fixture that exercises one
/// field proves one field.
enum FixtureCompositions {

    static func broad() -> Video {
        let style = TextStyle(
            fontName: "Menlo", fontSize: 42, color: .white,
            alignment: .center, weight: .bold,
            stroke: TextStroke(width: 2, color: .black),
            shadow: TextShadow(offset: CGSize(width: 1, height: 2), blur: 4)
        )
        return Video {
            VideoClip(url: URL(fileURLWithPath: "/fixtures/a.mov"))
                .trimmed(to: CMTimeRange(start: CMTime(value: 30, timescale: 30),
                                         duration: CMTime(value: 150, timescale: 30)))
                .volume(0.6)
                .filter(.sepia(intensity: 0.4), id: FilterID("sepia-1"))
                .filter(.mono, id: FilterID("mono-1"))
                .id(ClipID("hero"))
                .transform(Transform(center: .normalized(x: 0.4, y: 0.6),
                                     rotation: 0.25, scale: 1.2, anchor: .topLeft))
                .opacity(0.9, animation: .keyframes([
                    .at(CMTime(value: 0, timescale: 30), value: 0.0),
                    .at(CMTime(value: 30, timescale: 30), value: 0.9),
                ], timing: .easeInOut))
            Transition.slide(direction: .fromBottom,
                             duration: CMTime(value: 15, timescale: 30))
            ImageClip(FixtureImageStore.pixel(), duration: CMTime(value: 60, timescale: 30))
                .id(ClipID("photo"))
            TitleSequence("Chapter One", duration: CMTime(value: 90, timescale: 30),
                          style: style, background: .black)
                .id(ClipID("title"))
            Track(at: CMTime(value: 200, timescale: 30), name: "overlayTrack") {
                VideoClip(url: URL(fileURLWithPath: "/fixtures/b.mov"))
                    .trimmed(to: CMTimeRange(start: .zero, duration: CMTime(value: 60, timescale: 30)))
                    .id(ClipID("nested"))
            }
            .opacity(0.7)
        }
        .preset(.custom(width: 1080, height: 1920, frameRate: 30, codec: .hevc))
        .quality(.bitrate(6_000_000))
        .crop(at: .percent(x: 50, y: 50), size: .normalized(width: 0.9, height: 0.9), anchor: .center)
        .captions([
            Caption(text: "first", timeRange: CMTimeRange(
                start: .zero, duration: CMTime(value: 30, timescale: 30))),
        ])
        .audio {
            AudioTrack(url: URL(fileURLWithPath: "/fixtures/music.m4a"))
                .volume(0.5)
                .fadeIn(CMTime(value: 30, timescale: 30))
                .fadeOut(CMTime(value: 60, timescale: 30))
                .ducking(0.2)
                .volumeRamp(start: 0.2, end: 0.8,
                            during: CMTimeRange(start: CMTime(value: 30, timescale: 30),
                                                duration: CMTime(value: 60, timescale: 30)))
                .speed(1.25, algorithm: .timeDomain)
        }
        .overlay(
            TextOverlay("Watermark", style: style)
                .position(.normalized(x: 0.5, y: 0.9))
                .anchor(.bottom)
                .opacity(0.8)
                .id(LayerID("wm"))
                .visible(during: CMTimeRange(start: .zero, duration: CMTime(value: 60, timescale: 30)))
                .animation(FadeIn(duration: CMTime(value: 15, timescale: 30), from: 0.1, beginTime: 0))
        )
        .overlay(
            ImageOverlay(FixtureImageStore.pixel())
                .position(.normalized(x: 0.2, y: 0.2))
                .size(.aspectFit(within: .normalized(width: 0.4, height: 0.4), sourceAspect: 1.5))
                .id(LayerID("logo"))
        )
        .overlay(
            StickerOverlay(FixtureImageStore.pixel())
                .position(.normalized(x: 0.8, y: 0.2))
                .rotation(0.4)
                .shadow(StickerOverlay.Shadow(color: .black, radius: 8,
                                              offset: CGSize(width: 2, height: 3), opacity: 0.5))
                .id(LayerID("sticker"))
        )
    }
}

/// A store that hands out fixed tokens, so the fixture's bytes are reproducible.
///
/// A content-addressing store would be reproducible too, but only as long as the
/// PNG encoder produces identical bytes — which is not something a committed
/// fixture should depend on.
struct FixtureImageStore: ImageStore {
    func token(for image: PlatformImage) throws -> String { "file:fixture-pixel.png" }
    func image(for token: String) throws -> PlatformImage { FixtureImageStore.pixel() }

    static func pixel() -> PlatformImage {
        #if canImport(UIKit)
        return UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        #else
        let image = NSImage(size: CGSize(width: 1, height: 1))
        image.lockFocus(); NSColor.red.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: 1, height: 1)).fill()
        image.unlockFocus()
        return image
        #endif
    }
}
