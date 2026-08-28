import Foundation
import CoreMedia
import CoreGraphics
import Kadr

/// Turning a composition into a document, and back.
///
/// ```swift
/// let data = try KadrCoding.data(for: video)
/// let restored = try KadrCoding.video(from: data)
/// ```
///
/// **The two things to know.**
///
/// Encoding *refuses* by default when the composition holds something a file
/// cannot represent — a compositor, a custom timing closure, a text animation, or
/// an image with no ``ImageStore`` to name it. Pass `allowingLoss: true` to save
/// anyway and receive a list of what was left behind, or call
/// ``lossyContent(in:images:)`` to ask before committing.
///
/// A hand-written mirror usually drops those silently, which produces a project
/// that saves without complaint and reopens subtly wrong. That has already
/// happened in this ecosystem more than once.
public enum KadrCoding {

    // MARK: - Contexts

    /// What encoding needs beyond the composition itself.
    struct EncodeContext {
        let images: (any ImageStore)?
        var lost: [Lossy] = []

        mutating func note(_ kind: Lossy.Kind, at location: String) {
            lost.append(Lossy(kind: kind, location: location))
        }

        /// A token for `image`, or `nil` having recorded the loss.
        mutating func token(for image: PlatformImage, at location: String) throws -> String? {
            guard let images else {
                note(.image, at: location)
                return nil
            }
            return try images.token(for: image)
        }
    }

    /// What decoding needs beyond the document.
    struct DecodeContext {
        let images: (any ImageStore)?

        func image(for token: String) throws -> PlatformImage {
            guard let images else {
                throw PersistenceError.missingImageStore(token: token)
            }
            return try images.image(for: token)
        }
    }

    /// Identity map, for the animations whose value type is already `Double`.
    static func identity<T>(_ value: T) -> T { value }

    // MARK: - Public surface

    /// The document for `video`.
    ///
    /// - Parameters:
    ///   - allowingLoss: when `true`, encode what can be encoded and drop the rest
    ///     rather than throwing. Ask ``lossyContent(in:images:)`` what that means
    ///     before setting it.
    ///   - images: how to name the composition's images. Without one, every image
    ///     is reported as ``Lossy/Kind/image``.
    /// - Throws: ``PersistenceError/lossyContent(_:)`` when the composition holds
    ///   content no document can represent and `allowingLoss` is `false`.
    public static func encode(
        _ video: Video,
        allowingLoss: Bool = false,
        images: (any ImageStore)? = nil
    ) throws -> KadrDocument {
        var context = EncodeContext(images: images)
        let data = try videoData(video, &context)
        if !context.lost.isEmpty && !allowingLoss {
            throw PersistenceError.lossyContent(context.lost)
        }
        return KadrDocument(video: data)
    }

    /// What would be lost by saving `video`, without saving it.
    ///
    /// For a host that wants to warn before the user commits, rather than after.
    /// Returns an empty array when the composition round-trips whole.
    public static func lossyContent(in video: Video, images: (any ImageStore)? = nil) -> [Lossy] {
        var context = EncodeContext(images: images)
        _ = try? videoData(video, &context)
        return context.lost
    }

    /// The composition a document describes.
    public static func decode(_ document: KadrDocument, images: (any ImageStore)? = nil) throws -> Video {
        guard document.schema <= KadrDocument.currentSchema else {
            throw PersistenceError.unsupportedSchema(
                found: document.schema, supported: KadrDocument.currentSchema
            )
        }
        return try video(from: document.video, DecodeContext(images: images))
    }

    /// JSON for `video`.
    public static func data(
        for video: Video,
        allowingLoss: Bool = false,
        images: (any ImageStore)? = nil
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]   // stable bytes, so diffs are readable
        return try encoder.encode(encode(video, allowingLoss: allowingLoss, images: images))
    }

    /// The composition in `data`.
    public static func video(from data: Data, images: (any ImageStore)? = nil) throws -> Video {
        let document: KadrDocument
        do { document = try JSONDecoder().decode(KadrDocument.self, from: data) }
        catch { throw PersistenceError.malformed(String(describing: error)) }
        return try decode(document, images: images)
    }

    // MARK: - Composition

    static func videoData(_ video: Video, _ context: inout EncodeContext) throws -> VideoData {
        if video.multiInputCompositor != nil {
            context.note(.multiInputCompositor, at: "the composition")
        }
        return VideoData(
            clips: try video.clips.map { try clipData($0, &context) },
            audioTracks: video.audioTracks.map(audioTrackData),
            preset: presetData(video.preset),
            overlays: try video.overlays.enumerated().compactMap { index, overlay in
                try overlayData(overlay, at: index, &context)
            },
            crop: video.crop.map(cropData),
            quality: qualityData(video.quality),
            captions: video.captions.map { CaptionData(text: $0.text, timeRange: TimeRangeData($0.timeRange)) }
        )
    }

    static func video(from data: VideoData, _ context: DecodeContext) throws -> Video {
        let clips = try data.clips.map { try clip(from: $0, context) }
        var video = Video { for clip in clips { clip } }
        video = video.preset(preset(from: data.preset))
        video = video.quality(quality(from: data.quality))
        if !data.audioTracks.isEmpty {
            let tracks = try data.audioTracks.map(audioTrack(from:))
            video = video.audio { for track in tracks { track } }
        }
        for overlay in data.overlays {
            video = try apply(overlay, to: video, context)
        }
        if let crop = data.crop {
            video = video.crop(at: position(from: crop.position),
                               size: size(from: crop.size),
                               anchor: anchor(named: crop.anchor))
        }
        if !data.captions.isEmpty {
            video = video.captions(data.captions.map { Caption(text: $0.text, timeRange: $0.timeRange.range) })
        }
        return video
    }

    // MARK: - Clips

    static func clipData(_ clip: any Clip, _ context: inout EncodeContext) throws -> ClipData {
        switch clip {
        case let videoClip as VideoClip:
            return .video(videoClipData(videoClip, &context))
        case let imageClip as ImageClip:
            return .image(try imageClipData(imageClip, &context))
        case let title as TitleSequence:
            return .title(titleSequenceData(title, &context))
        case let transition as Transition:
            return .transition(transitionData(transition))
        case let track as Track:
            return .track(TrackData(
                name: track.name,
                startTime: track.startTime.map(TimeData.init),
                opacityFactor: track.opacityFactor,
                clips: try track.clips.map { try clipData($0, &context) }
            ))
        default:
            throw PersistenceError.unsupportedClip(String(describing: type(of: clip)))
        }
    }

    static func clip(from data: ClipData, _ context: DecodeContext) throws -> any Clip {
        switch data {
        case let .video(v):      return try videoClip(from: v)
        case let .image(i):      return try imageClip(from: i, context)
        case let .title(t):      return try titleSequence(from: t)
        case let .transition(t): return transition(from: t)
        case let .track(t):
            let inner = try t.clips.map { try clip(from: $0, context) }
            var track = Track(at: t.startTime?.time ?? .zero, name: t.name) {
                for c in inner { c }
            }
            if t.opacityFactor != 1.0 { track = track.opacity(t.opacityFactor) }
            return track
        }
    }

    // MARK: - Video clips

    /// A description of where a clip is, for a person reading a warning.
    static func describe(_ id: ClipID?, fallback: String) -> String {
        id.map { "clip “\($0.rawValue)”" } ?? fallback
    }

    static func videoClipData(_ clip: VideoClip, _ context: inout EncodeContext) -> VideoClipData {
        let at = describe(clip.clipID, fallback: "a clip in \(clip.url.lastPathComponent)")
        if !clip.compositors.isEmpty { context.note(.compositor, at: at) }
        return VideoClipData(
            url: clip.url.absoluteString,
            trimRange: clip.trimRange.map(TimeRangeData.init),
            isReversed: clip.isReversed,
            isMuted: clip.isMuted,
            volumeLevel: clip.volumeLevel,
            replacementAudioURL: clip.replacementAudioURL?.absoluteString,
            speedRate: clip.speedRate,
            speedCurve: clip.speedCurve.map { animationData($0, at: at, &context, identity) },
            filters: clip.filters.map(filterData),
            filterIDs: clip.filterIDs.map(\.rawValue),
            filterAnimations: clip.filterAnimations.map { anim in
                anim.map { animationData($0, at: at, &context, identity) }
            },
            clipID: clip.clipID?.rawValue,
            startTime: clip.startTime.map(TimeData.init),
            transform: clip.transform.map(transformData),
            transformAnimation: clip.transformAnimation.map {
                animationData($0, at: at, &context, transformData)
            },
            opacity: clip.opacity,
            opacityAnimation: clip.opacityAnimation.map { animationData($0, at: at, &context, identity) }
        )
    }

    static func videoClip(from data: VideoClipData) throws -> VideoClip {
        guard let url = URL(string: data.url) else {
            throw PersistenceError.malformed("A clip has an unreadable file location.")
        }
        var clip = VideoClip(url: url)
        if let trim = data.trimRange { clip = clip.trimmed(to: trim.range) }
        if data.isReversed { clip = clip.reversed() }
        if let replacement = data.replacementAudioURL, let audioURL = URL(string: replacement) {
            clip = clip.withAudio(audioURL)
        } else if data.isMuted {
            clip = clip.muted()
        }
        if data.volumeLevel != 1.0 { clip = clip.volume(data.volumeLevel) }
        if let curve = data.speedCurve {
            clip = clip.speed(.curved(animation(from: curve, identity)))
        } else if data.speedRate != 1.0 {
            clip = clip.speed(.flat(data.speedRate))
        }
        // Each filter is re-applied under the identity it was saved with, via
        // `filter(_:id:animation:)` (kadr 0.21). The plain `.filter(_:)` modifier
        // generates a fresh id, which would orphan any animation bound with
        // `filterAnimation(for:)` and drop any UI selection keyed to it.
        for (index, filter) in data.filters.enumerated() {
            let animation = index < data.filterAnimations.count ? data.filterAnimations[index] : nil
            let id = index < data.filterIDs.count ? FilterID(data.filterIDs[index]) : FilterID.generate()
            clip = clip.filter(
                try self.filter(from: filter),
                id: id,
                animation: animation.map { self.animation(from: $0, identity) }
            )
        }
        if let id = data.clipID { clip = clip.id(ClipID(id)) }
        if let start = data.startTime { clip = clip.at(time: start.time) }
        if let animation = data.transformAnimation {
            clip = clip.transform(
                data.transform.map(transform(from:)) ?? Transform(),
                animation: self.animation(from: animation, transform(from:))
            )
        } else if let t = data.transform {
            clip = clip.transform(transform(from: t))
        }
        if let animation = data.opacityAnimation {
            clip = clip.opacity(data.opacity ?? 1.0, animation: self.animation(from: animation, identity))
        } else if let o = data.opacity {
            clip = clip.opacity(o)
        }
        return clip
    }

    // MARK: - Image clips

    static func imageClipData(_ clip: ImageClip, _ context: inout EncodeContext) throws -> ImageClipData {
        let at = describe(clip.clipID, fallback: "an image clip")
        let token = try context.token(for: clip.image, at: at) ?? ""
        return ImageClipData(
            imageToken: token,
            duration: TimeData(clip.duration),
            backgroundColor: clip.backgroundColor.map(colorData),
            audioURL: clip.audioURL?.absoluteString,
            clipID: clip.clipID?.rawValue,
            startTime: clip.startTime.map(TimeData.init),
            transform: clip.transform.map(transformData),
            transformAnimation: clip.transformAnimation.map {
                animationData($0, at: at, &context, transformData)
            },
            opacity: clip.opacity,
            opacityAnimation: clip.opacityAnimation.map { animationData($0, at: at, &context, identity) }
        )
    }

    static func imageClip(from data: ImageClipData, _ context: DecodeContext) throws -> ImageClip {
        var clip = ImageClip(try context.image(for: data.imageToken), duration: data.duration.time)
        if let background = data.backgroundColor { clip = clip.background(platformColor(from: background)) }
        if let audio = data.audioURL, let url = URL(string: audio) { clip = clip.withAudio(url) }
        if let id = data.clipID { clip = clip.id(ClipID(id)) }
        if let start = data.startTime { clip = clip.at(time: start.time) }
        if let animation = data.transformAnimation {
            clip = clip.transform(
                data.transform.map(transform(from:)) ?? Transform(),
                animation: self.animation(from: animation, transform(from:))
            )
        } else if let t = data.transform {
            clip = clip.transform(transform(from: t))
        }
        if let animation = data.opacityAnimation {
            clip = clip.opacity(data.opacity ?? 1.0, animation: self.animation(from: animation, identity))
        } else if let o = data.opacity {
            clip = clip.opacity(o)
        }
        return clip
    }

    // MARK: - Titles and transitions

    static func titleSequenceData(_ title: TitleSequence, _ context: inout EncodeContext) -> TitleSequenceData {
        let at = describe(title.clipID, fallback: "the title “\(title.text.prefix(24))”")
        return TitleSequenceData(
            text: title.text,
            style: textStyleData(title.style),
            backgroundColor: colorData(title.backgroundColor),
            duration: TimeData(title.duration),
            clipID: title.clipID?.rawValue,
            startTime: title.startTime.map(TimeData.init),
            transform: title.transform.map(transformData),
            transformAnimation: title.transformAnimation.map {
                animationData($0, at: at, &context, transformData)
            },
            opacity: title.opacity,
            opacityAnimation: title.opacityAnimation.map { animationData($0, at: at, &context, identity) }
        )
    }

    static func titleSequence(from data: TitleSequenceData) throws -> TitleSequence {
        var title = TitleSequence(
            data.text,
            duration: data.duration.time,
            style: textStyle(from: data.style),
            background: platformColor(from: data.backgroundColor)
        )
        if let id = data.clipID { title = title.id(ClipID(id)) }
        if let start = data.startTime { title = title.at(time: start.time) }
        if let animation = data.transformAnimation {
            title = title.transform(
                data.transform.map(transform(from:)) ?? Transform(),
                animation: self.animation(from: animation, transform(from:))
            )
        } else if let t = data.transform {
            title = title.transform(transform(from: t))
        }
        if let animation = data.opacityAnimation {
            title = title.opacity(data.opacity ?? 1.0, animation: self.animation(from: animation, identity))
        } else if let o = data.opacity {
            title = title.opacity(o)
        }
        return title
    }

    static func transitionData(_ transition: Transition) -> TransitionData {
        switch transition {
        case let .fade(duration):
            return TransitionData(kind: "fade", duration: TimeData(duration), direction: nil)
        case let .dissolve(duration):
            return TransitionData(kind: "dissolve", duration: TimeData(duration), direction: nil)
        case let .slide(direction, duration):
            return TransitionData(kind: "slide", duration: TimeData(duration),
                                  direction: slideDirectionName(direction))
        }
    }

    static func transition(from data: TransitionData) -> Transition {
        switch data.kind {
        case "dissolve": return .dissolve(duration: data.duration.time)
        case "slide":
            return .slide(direction: slideDirection(named: data.direction ?? "fromLeft"),
                          duration: data.duration.time)
        default: return .fade(duration: data.duration.time)
        }
    }
}
