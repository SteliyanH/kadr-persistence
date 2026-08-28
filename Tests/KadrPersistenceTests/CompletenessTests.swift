import Testing
import Foundation
import CoreMedia
import Kadr
@testable import KadrPersistence

/// The guard that makes this package survive kadr changing underneath it.
///
/// Every bug this package exists to prevent has the same shape: a field exists
/// upstream, the mirror doesn't know about it, and nothing fails. No round-trip
/// test catches that — a field absent from both sides of the comparison compares
/// equal. The reference app lost three fields exactly this way, and the first
/// draft of *this* package silently dropped six of `Video`'s ten.
///
/// So instead of testing values, these tests test the *shape*: reflect over each
/// kadr type and assert its stored properties are exactly the set this package
/// has been taught to handle. When kadr adds a field, these fail — and the fix is
/// to encode it, or to add it to the list with a reason.
struct CompletenessTests {

    private func storedProperties<T>(of value: T) -> Set<String> {
        Set(Mirror(reflecting: value).children.compactMap(\.label))
    }

    private func check<T>(
        _ value: T,
        encoded: Set<String>,
        deliberatelyNotEncoded: Set<String> = [],
        computed: Set<String> = [],
        _ name: String
    ) {
        let actual = storedProperties(of: value)
        let known = encoded.union(deliberatelyNotEncoded).union(computed)
        let unknown = actual.subtracting(known)
        let vanished = known.subtracting(actual).subtracting(computed)
        #expect(
            unknown.isEmpty,
            """
            \(name) has \(unknown.sorted()) which KadrPersistence knows nothing about.
            Encode it, or add it to `deliberatelyNotEncoded` with a reason.
            """
        )
        #expect(
            vanished.isEmpty,
            "\(name) no longer has \(vanished.sorted()) — the mirror is encoding a field that is gone."
        )
    }

    @Test("Video's stored properties are all accounted for")
    func videoIsComplete() {
        check(
            Video { VideoClip(url: URL(fileURLWithPath: "/tmp/a.mov")) },
            encoded: ["clips", "audioTracks", "preset", "overlays", "crop", "quality", "captions"],
            deliberatelyNotEncoded: [
                // Code, not data. Reported as Lossy rather than dropped.
                "multiInputCompositor",
                // Only meaningful alongside the compositor it windows.
                "compositorWindow",
                // Derived, not independent state: `Video.duration` is a cache of
                // `clips.reduce(+)`, recomputed by the initialiser. Encoding it
                // would let a document assert a duration its own clips contradict.
                // `durationIsRecomputedOnDecode` below proves it comes back right.
                "duration",
            ],
            "Video"
        )
    }

    @Test("VideoClip's stored properties are all accounted for")
    func videoClipIsComplete() {
        check(
            VideoClip(url: URL(fileURLWithPath: "/tmp/a.mov")),
            encoded: [
                "url", "trimRange", "isReversed", "isMuted", "volumeLevel",
                "replacementAudioURL", "speedRate", "speedCurve", "filters",
                "filterIDs", "filterAnimations", "clipID", "startTime", "transform",
                "transformAnimation", "opacity", "opacityAnimation",
            ],
            deliberatelyNotEncoded: [
                "compositors",   // code, reported as Lossy
            ],
            "VideoClip"
        )
    }

    @Test("AudioTrack's stored properties are all accounted for")
    func audioTrackIsComplete() {
        check(
            AudioTrack(url: URL(fileURLWithPath: "/tmp/a.m4a")),
            encoded: [
                "url", "volumeLevel", "fadeInDuration", "fadeOutDuration", "duckingLevel",
                "startTime", "explicitDuration", "crossfadeDuration", "volumeRamps",
                "speedRate", "pitchAlgorithm",
            ],
            "AudioTrack"
        )
    }

    @Test("Track's stored properties are all accounted for")
    func trackIsComplete() {
        check(
            Track(at: .zero, name: "t") { VideoClip(url: URL(fileURLWithPath: "/tmp/a.mov")) },
            encoded: ["clips", "startTime", "name", "opacityFactor"],
            "Track"
        )
    }

    @Test("ImageClip's stored properties are all accounted for")
    func imageClipIsComplete() {
        check(
            ImageClip(TestImages.solid(), duration: 3.0),
            encoded: [
                "image", "backgroundColor", "audioURL", "clipID", "startTime",
                "transform", "transformAnimation", "opacity", "opacityAnimation",
                "_duration",   // storage behind the computed `duration`; encoded as `duration`
            ],
            "ImageClip"
        )
    }

    @Test("TitleSequence's stored properties are all accounted for")
    func titleSequenceIsComplete() {
        check(
            TitleSequence("Hi", duration: 2.0),
            encoded: [
                "text", "style", "backgroundColor", "clipID", "startTime",
                "transform", "transformAnimation", "opacity", "opacityAnimation",
                "_duration",   // storage behind the computed `duration`; encoded as `duration`
            ],
            "TitleSequence"
        )
    }

    @Test("TextStyle's stored properties are all accounted for")
    func textStyleIsComplete() {
        check(
            TextStyle(),
            encoded: ["fontName", "fontSize", "color", "alignment", "weight", "stroke", "shadow"],
            "TextStyle"
        )
    }

    @Test("TextOverlay's stored properties are all accounted for")
    func textOverlayIsComplete() {
        check(
            TextOverlay("Hi"),
            encoded: ["text", "style", "position", "size", "anchor", "opacity", "layerID", "visibilityRange"],
            deliberatelyNotEncoded: ["textAnimation"],   // code, reported as Lossy
            "TextOverlay"
        )
    }

    @Test("ImageOverlay's stored properties are all accounted for")
    func imageOverlayIsComplete() {
        check(
            ImageOverlay(TestImages.solid()),
            encoded: [
                "image", "position", "size", "anchor", "opacity", "layerID",
                "visibilityRange", "positionAnimation", "sizeAnimation",
            ],
            "ImageOverlay"
        )
    }

    @Test("StickerOverlay's stored properties are all accounted for")
    func stickerOverlayIsComplete() {
        check(
            StickerOverlay(TestImages.solid()),
            encoded: [
                "image", "position", "size", "anchor", "opacity", "layerID",
                "rotation", "shadow", "visibilityRange", "positionAnimation", "sizeAnimation",
            ],
            "StickerOverlay"
        )
    }

    @Test("CropRegion's stored properties are all accounted for")
    func cropRegionIsComplete() {
        let cropped = Video { VideoClip(url: URL(fileURLWithPath: "/tmp/a.mov")) }
            .crop(at: .normalized(x: 0.5, y: 0.5), size: .normalized(width: 0.8, height: 0.8))
        #expect(cropped.crop != nil)
        check(cropped.crop!, encoded: ["position", "size", "anchor"], "CropRegion")
    }

    @Test("Video.duration is recomputed on decode, not carried in the file")
    func durationIsRecomputedOnDecode() throws {
        let video = Video {
            VideoClip(url: .fixture("a.mov")).trimmed(to: 0...4)
            VideoClip(url: .fixture("b.mov")).trimmed(to: 0...6)
        }
        let restored = try KadrCoding.decode(KadrCoding.encode(video))
        #expect(restored.duration == video.duration)
        #expect(restored.duration.seconds == 10)
    }

    @Test("Caption's stored properties are all accounted for")
    func captionIsComplete() {
        check(
            Caption(text: "hi", timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 600))),
            encoded: ["text", "timeRange"],
            "Caption"
        )
    }
}

/// A client must be able to *construct* a document, not only read one.
///
/// Swift synthesises a memberwise initialiser for a `public struct`, but that
/// initialiser is `internal` — invisible outside the module. Every mirror type
/// here was therefore readable and un-constructible from outside, which this
/// package found the same way it finds everything else: by being consumed.
struct PublicConstructionTests {

    @Test("The document types can be built from outside the module")
    func documentIsConstructible() throws {
        let document = KadrDocument(video: VideoData(
            clips: [.transition(TransitionData(
                kind: "fade",
                duration: TimeData(CMTime(seconds: 0.5, preferredTimescale: 600)),
                direction: nil
            ))],
            audioTracks: [],
            preset: PresetData(kind: "tiktok", width: nil, height: nil, frameRate: nil, codec: nil),
            overlays: [],
            crop: nil,
            quality: QualityData(kind: "bitrate", bitrate: 4_000_000, fileSizeBytes: nil),
            captions: [CaptionData(
                text: "hi",
                timeRange: TimeRangeData(CMTimeRange(
                    start: .zero,
                    duration: CMTime(seconds: 1, preferredTimescale: 600)
                ))
            )]
        ))
        let video = try KadrCoding.decode(document)
        #expect(video.clips.count == 1)
        #expect(video.preset == .tiktok)
        #expect(video.quality == .bitrate(4_000_000))
        #expect(video.captions.count == 1)
    }

    @Test("A hand-built document survives a JSON round trip")
    func handBuiltDocumentRoundTrips() throws {
        let style = TextStyleData(
            fontName: "Menlo",
            fontSize: 32,
            color: ColorData(red: 1, green: 0.5, blue: 0, alpha: 1),
            alignment: "center",
            weight: "bold",
            stroke: TextStrokeData(width: 2, color: ColorData(red: 0, green: 0, blue: 0, alpha: 1)),
            shadow: TextShadowData(offset: SizeOffsetData(width: 1, height: 2), blur: 3)
        )
        let document = KadrDocument(video: VideoData(
            clips: [.title(TitleSequenceData(
                text: "Built by hand",
                style: style,
                backgroundColor: ColorData(red: 0, green: 0, blue: 0, alpha: 1),
                duration: TimeData(CMTime(seconds: 2, preferredTimescale: 600)),
                clipID: "t", startTime: nil, transform: nil,
                transformAnimation: nil, opacity: nil, opacityAnimation: nil
            ))],
            audioTracks: [], preset: PresetData(kind: "auto", width: nil, height: nil, frameRate: nil, codec: nil),
            overlays: [], crop: nil,
            quality: QualityData(kind: "automatic", bitrate: nil, fileSizeBytes: nil),
            captions: []
        ))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        let restored = try JSONDecoder().decode(KadrDocument.self, from: data)
        #expect(restored == document)
    }
}
