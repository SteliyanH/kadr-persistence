import Foundation
import CoreMedia
import CoreGraphics

// The document format.
//
// These are mirrors of kadr's DSL types, not the types themselves. kadr's types
// hold existentials and closures and cannot be `Codable`; a mirror can be, and
// keeping it separate means the file format is a thing that can be versioned
// independently of the API that produces it.
//
// Every mirror is a flat pile of optionals rather than a nested enum where it
// could be either, because a flat pile survives a field being added: an older
// reader ignores what it doesn't know instead of failing to match a case.

// MARK: - Time

/// A time, stored as the rational it is.
///
/// Stored as `value`/`timescale` rather than seconds so a frame boundary survives
/// the round trip exactly. `CMTime(seconds: 1.0/30.0)` written as `0.03333…` and
/// read back is no longer frame 1 of a 30 fps timeline, and an editor that snaps
/// to frames will show the clip a frame short.
public struct TimeData: Codable, Sendable, Equatable {
    public let value: Int64
    public let timescale: Int32

    public init(_ time: CMTime) {
        self.value = time.value
        self.timescale = time.timescale
    }

    public var time: CMTime { CMTime(value: value, timescale: timescale) }
}

public struct TimeRangeData: Codable, Sendable, Equatable {
    public let start: TimeData
    public let duration: TimeData

    public init(_ range: CMTimeRange) {
        self.start = TimeData(range.start)
        self.duration = TimeData(range.duration)
    }

    public var range: CMTimeRange { CMTimeRange(start: start.time, duration: duration.time) }
}

// MARK: - Geometry and colour

public struct PositionData: Codable, Sendable, Equatable {
    public let kind: String     // normalized | pixels | percent
    public let x: Double
    public let y: Double
}

/// `Size` is a recursive enum — `aspectFit` and `aspectFill` nest another size —
/// so its mirror is recursive too.
public indirect enum SizeData: Codable, Sendable, Equatable {
    case normalized(width: Double, height: Double)
    case pixels(width: Double, height: Double)
    case percent(width: Double, height: Double)
    case aspectFit(within: SizeData, sourceAspect: Double)
    case aspectFill(covering: SizeData, sourceAspect: Double)
}

/// Colour with alpha.
///
/// kadr's own `ColorComponents` drops alpha — it exists for chroma keying, where
/// alpha is meaningless. A document cannot: a translucent title background is a
/// design decision, and reopening it opaque is a visible regression.
public struct ColorData: Codable, Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double
}

public struct SizeOffsetData: Codable, Sendable, Equatable {
    public let width: Double
    public let height: Double
}

public struct TransformData: Codable, Sendable, Equatable {
    public let center: PositionData
    public let rotation: Double
    public let scale: Double
    public let anchor: String
}

// MARK: - Animation

public struct KeyframeData<Value: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    public let time: TimeData
    public let value: Value
}

public struct AnimationData<Value: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    public let keyframes: [KeyframeData<Value>]
    public let timing: TimingData
}

/// An easing curve.
///
/// `kind` is a string rather than an enum with associated values so that an
/// unknown future curve decodes as a readable name instead of failing the whole
/// document.
public struct TimingData: Codable, Sendable, Equatable {
    public let kind: String     // linear | easeIn | easeOut | easeInOut | cubicBezier
    public let p1x: Double?
    public let p1y: Double?
    public let p2x: Double?
    public let p2y: Double?
}

// MARK: - Filters

public struct FilterData: Codable, Sendable, Equatable {
    public let kind: String
    public let scalar: Double?
    /// LUT file location.
    public let url: String?
    public let red: Double?
    public let green: Double?
    public let blue: Double?
    public let threshold: Double?
}

// MARK: - Text

public struct TextStrokeData: Codable, Sendable, Equatable {
    public let width: Double
    public let color: ColorData
}

public struct TextShadowData: Codable, Sendable, Equatable {
    public let offset: SizeOffsetData
    public let blur: Double
}

public struct ShadowData: Codable, Sendable, Equatable {
    public let color: ColorData
    public let radius: Double
    public let offset: SizeOffsetData
    public let opacity: Double
}

public struct TextStyleData: Codable, Sendable, Equatable {
    public let fontName: String?
    public let fontSize: Double
    public let color: ColorData
    public let alignment: String
    public let weight: String
    public let stroke: TextStrokeData?
    public let shadow: TextShadowData?
}

// MARK: - Overlays

public struct TextOverlayData: Codable, Sendable, Equatable {
    public let text: String
    public let style: TextStyleData
    public let position: PositionData
    public let size: SizeData?
    public let anchor: String
    public let opacity: Double
    public let layerID: String?
    public let visibilityRange: TimeRangeData?
}

public struct ImageOverlayData: Codable, Sendable, Equatable {
    /// An ``ImageStore`` token, not the pixels.
    public let imageToken: String
    public let position: PositionData
    public let size: SizeData?
    public let anchor: String
    public let opacity: Double
    public let layerID: String?
    public let visibilityRange: TimeRangeData?
    public let positionAnimation: AnimationData<PositionData>?
    public let sizeAnimation: AnimationData<SizeData>?
}

public struct StickerOverlayData: Codable, Sendable, Equatable {
    public let imageToken: String
    public let position: PositionData
    public let size: SizeData?
    public let anchor: String
    public let opacity: Double
    public let layerID: String?
    public let rotation: Double
    public let shadow: ShadowData?
    public let visibilityRange: TimeRangeData?
    public let positionAnimation: AnimationData<PositionData>?
    public let sizeAnimation: AnimationData<SizeData>?
}

public enum OverlayData: Codable, Sendable, Equatable {
    case text(TextOverlayData)
    case image(ImageOverlayData)
    case sticker(StickerOverlayData)
}

// MARK: - Clips

public struct VideoClipData: Codable, Sendable, Equatable {
    public let url: String
    public let trimRange: TimeRangeData?
    public let isReversed: Bool
    public let isMuted: Bool
    public let volumeLevel: Double
    public let replacementAudioURL: String?
    public let speedRate: Double
    public let speedCurve: AnimationData<Double>?
    public let filters: [FilterData]
    /// Parallel to `filters`. Stable across reorder and trim, so a timeline UI's
    /// per-filter selection survives a save.
    public let filterIDs: [String]
    public let filterAnimations: [AnimationData<Double>?]
    public let clipID: String?
    public let startTime: TimeData?
    public let transform: TransformData?
    public let transformAnimation: AnimationData<TransformData>?
    public let opacity: Double?
    public let opacityAnimation: AnimationData<Double>?
}

public struct ImageClipData: Codable, Sendable, Equatable {
    /// An ``ImageStore`` token, not the pixels.
    public let imageToken: String
    public let duration: TimeData
    public let backgroundColor: ColorData?
    public let audioURL: String?
    public let clipID: String?
    public let startTime: TimeData?
    public let transform: TransformData?
    public let transformAnimation: AnimationData<TransformData>?
    public let opacity: Double?
    public let opacityAnimation: AnimationData<Double>?
}

public struct TitleSequenceData: Codable, Sendable, Equatable {
    public let text: String
    public let style: TextStyleData
    public let backgroundColor: ColorData
    public let duration: TimeData
    public let clipID: String?
    public let startTime: TimeData?
    public let transform: TransformData?
    public let transformAnimation: AnimationData<TransformData>?
    public let opacity: Double?
    public let opacityAnimation: AnimationData<Double>?
}

public struct TransitionData: Codable, Sendable, Equatable {
    public let kind: String         // fade | slide | dissolve
    public let duration: TimeData
    public let direction: String?   // slide only
}

public struct TrackData: Codable, Sendable, Equatable {
    public let name: String?
    public let startTime: TimeData?
    public let opacityFactor: Double
    public let clips: [ClipData]
}

/// A clip, tagged by kind.
///
/// Synthesised `Codable` writes this as `{"video": {...}}`. A discriminator naming
/// a case that does not exist surfaces as ``PersistenceError/malformed(_:)`` rather
/// than a silently empty timeline.
public indirect enum ClipData: Codable, Sendable, Equatable {
    case video(VideoClipData)
    case image(ImageClipData)
    case title(TitleSequenceData)
    case transition(TransitionData)
    case track(TrackData)
}

// MARK: - Audio

public struct VolumeRampData: Codable, Sendable, Equatable {
    public let startVolume: Double
    public let endVolume: Double
    public let range: TimeRangeData
}

public struct AudioTrackData: Codable, Sendable, Equatable {
    public let url: String
    public let volumeLevel: Double
    public let fadeInDuration: TimeData
    public let fadeOutDuration: TimeData
    public let duckingLevel: Double?
    public let startTime: TimeData?
    public let explicitDuration: TimeData?
    public let crossfadeDuration: TimeData?
    public let volumeRamps: [VolumeRampData]
    public let speedRate: Double
    public let pitchAlgorithm: String   // spectral | timeDomain | varispeed
}

// MARK: - Composition

public struct PresetData: Codable, Sendable, Equatable {
    public let kind: String
    public let width: Int?
    public let height: Int?
    public let frameRate: Int?
    public let codec: String?
}

public struct QualityData: Codable, Sendable, Equatable {
    public let kind: String     // automatic | bitrate | fileSize
    public let bitrate: Int?
    public let fileSizeBytes: Int?
}

public struct CropData: Codable, Sendable, Equatable {
    public let position: PositionData
    public let size: SizeData
    public let anchor: String
}

public struct CaptionData: Codable, Sendable, Equatable {
    public let text: String
    public let timeRange: TimeRangeData
}

public struct VideoData: Codable, Sendable, Equatable {
    public let clips: [ClipData]
    public let audioTracks: [AudioTrackData]
    public let preset: PresetData
    public let overlays: [OverlayData]
    public let crop: CropData?
    public let quality: QualityData
    public let captions: [CaptionData]
}

/// A saved composition.
///
/// The top level is deliberately thin: a schema number and the composition. Room
/// for host metadata (a project name, a thumbnail) belongs to the host's own
/// wrapper — a document format that grows app-specific fields becomes an app
/// format, and stops being reusable by the next app.
public struct KadrDocument: Codable, Sendable, Equatable {

    /// The format this version writes.
    ///
    /// Bumped only for changes an older reader cannot survive. Adding an optional
    /// field is not one: older readers ignore unknown keys, and this package's
    /// mirrors decode a missing optional as `nil`.
    public static let currentSchema = 1

    public let schema: Int
    public let video: VideoData

    public init(schema: Int = KadrDocument.currentSchema, video: VideoData) {
        self.schema = schema
        self.video = video
    }
}
