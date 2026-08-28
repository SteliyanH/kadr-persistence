import Foundation
import CoreMedia
import CoreGraphics
import Kadr

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// The leaf value types. These are the ones a hand-written bridge gets wrong,
// because each is a small pile of fields with no compiler check that the pile is
// complete — the reference app lost `TextStyle.color` and two `Transform` fields
// exactly this way.
extension KadrCoding {

    // MARK: - Colour

    /// Components including alpha.
    ///
    /// kadr's own `ColorComponents` drops alpha — it exists for chroma keying,
    /// where alpha has no meaning. A document cannot afford that: a translucent
    /// title background reopening opaque is a visible regression.
    static func colorData(_ color: PlatformColor) -> ColorData {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(UIKit)
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #elseif canImport(AppKit)
        // NSColor must be converted to a component-addressable space first;
        // getRed on a pattern or catalog colour traps otherwise.
        let normalized = color.usingColorSpace(.sRGB) ?? color
        normalized.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        return ColorData(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
    }

    static func platformColor(from data: ColorData) -> PlatformColor {
        PlatformColor(red: CGFloat(data.red), green: CGFloat(data.green),
                      blue: CGFloat(data.blue), alpha: CGFloat(data.alpha))
    }

    // MARK: - Position, size, anchor, transform

    static func positionData(_ position: Position) -> PositionData {
        switch position {
        case let .normalized(x, y): return PositionData(kind: "normalized", x: x, y: y)
        case let .pixels(x, y):     return PositionData(kind: "pixels", x: x, y: y)
        case let .percent(x, y):    return PositionData(kind: "percent", x: x, y: y)
        }
    }

    static func position(from data: PositionData) -> Position {
        switch data.kind {
        case "pixels":  return .pixels(x: data.x, y: data.y)
        case "percent": return .percent(x: data.x, y: data.y)
        default:        return .normalized(x: data.x, y: data.y)
        }
    }

    static func sizeData(_ size: Size) -> SizeData {
        switch size {
        case let .normalized(w, h): return .normalized(width: w, height: h)
        case let .pixels(w, h):     return .pixels(width: w, height: h)
        case let .percent(w, h):    return .percent(width: w, height: h)
        case let .aspectFit(within, aspect):
            return .aspectFit(within: sizeData(within), sourceAspect: Double(aspect))
        case let .aspectFill(covering, aspect):
            return .aspectFill(covering: sizeData(covering), sourceAspect: Double(aspect))
        }
    }

    static func size(from data: SizeData) -> Size {
        switch data {
        case let .normalized(w, h): return .normalized(width: w, height: h)
        case let .pixels(w, h):     return .pixels(width: w, height: h)
        case let .percent(w, h):    return .percent(width: w, height: h)
        case let .aspectFit(within, aspect):
            return .aspectFit(within: size(from: within), sourceAspect: CGFloat(aspect))
        case let .aspectFill(covering, aspect):
            return .aspectFill(covering: size(from: covering), sourceAspect: CGFloat(aspect))
        }
    }

    static func anchorName(_ anchor: Anchor) -> String {
        switch anchor {
        case .topLeft: return "topLeft";       case .top: return "top"
        case .topRight: return "topRight";     case .left: return "left"
        case .center: return "center";         case .right: return "right"
        case .bottomLeft: return "bottomLeft"; case .bottom: return "bottom"
        case .bottomRight: return "bottomRight"
        }
    }

    static func anchor(named name: String) -> Anchor {
        switch name {
        case "topLeft": return .topLeft;       case "top": return .top
        case "topRight": return .topRight;     case "left": return .left
        case "right": return .right;           case "bottomLeft": return .bottomLeft
        case "bottom": return .bottom;         case "bottomRight": return .bottomRight
        default: return .center
        }
    }

    static func transformData(_ transform: Transform) -> TransformData {
        TransformData(
            center: positionData(transform.center),
            rotation: transform.rotation,
            scale: transform.scale,
            anchor: anchorName(transform.anchor)
        )
    }

    static func transform(from data: TransformData) -> Transform {
        Transform(
            center: position(from: data.center),
            rotation: data.rotation,
            scale: data.scale,
            anchor: anchor(named: data.anchor)
        )
    }

    static func offsetData(_ size: CGSize) -> SizeOffsetData {
        SizeOffsetData(width: Double(size.width), height: Double(size.height))
    }

    static func offset(from data: SizeOffsetData) -> CGSize {
        CGSize(width: data.width, height: data.height)
    }

    // MARK: - Timing and animation

    /// A timing function, reporting a `Lossy` when the original was a closure.
    static func timingData(_ timing: TimingFunction, at location: String,
                           _ context: inout EncodeContext) -> TimingData {
        switch timing {
        case .linear:    return TimingData(kind: "linear", p1x: nil, p1y: nil, p2x: nil, p2y: nil)
        case .easeIn:    return TimingData(kind: "easeIn", p1x: nil, p1y: nil, p2x: nil, p2y: nil)
        case .easeOut:   return TimingData(kind: "easeOut", p1x: nil, p1y: nil, p2x: nil, p2y: nil)
        case .easeInOut: return TimingData(kind: "easeInOut", p1x: nil, p1y: nil, p2x: nil, p2y: nil)
        case let .cubicBezier(p1, p2):
            return TimingData(kind: "cubicBezier", p1x: p1.x, p1y: p1.y, p2x: p2.x, p2y: p2.y)
        case .custom:
            // A closure. Recorded as linear and reported — never guessed at.
            context.note(.customTimingFunction, at: location)
            return TimingData(kind: "linear", p1x: nil, p1y: nil, p2x: nil, p2y: nil)
        }
    }

    static func timing(from data: TimingData) -> TimingFunction {
        switch data.kind {
        case "easeIn":    return .easeIn
        case "easeOut":   return .easeOut
        case "easeInOut": return .easeInOut
        case "cubicBezier":
            return .cubicBezier(
                CGPoint(x: data.p1x ?? 0, y: data.p1y ?? 0),
                CGPoint(x: data.p2x ?? 1, y: data.p2y ?? 1)
            )
        default: return .linear
        }
    }

    static func animationData<Value, Encoded>(
        _ animation: Animation<Value>,
        at location: String,
        _ context: inout EncodeContext,
        _ map: (Value) -> Encoded
    ) -> AnimationData<Encoded> {
        AnimationData(
            keyframes: animation.keyframes.map { KeyframeData(time: TimeData($0.time), value: map($0.value)) },
            timing: timingData(animation.timing, at: location, &context)
        )
    }

    static func animation<Value, Encoded>(
        from data: AnimationData<Encoded>,
        _ map: (Encoded) -> Value
    ) -> Animation<Value> {
        Animation.keyframes(
            data.keyframes.map { .at($0.time.time, value: map($0.value)) },
            timing: timing(from: data.timing)
        )
    }

    // MARK: - Filters

    static func filterData(_ filter: Filter) -> FilterData {
        func scalar(_ kind: String, _ value: Double) -> FilterData {
            FilterData(kind: kind, scalar: value, url: nil, red: nil, green: nil, blue: nil, threshold: nil)
        }
        switch filter {
        case let .brightness(v):   return scalar("brightness", v)
        case let .contrast(v):     return scalar("contrast", v)
        case let .saturation(v):   return scalar("saturation", v)
        case let .exposure(v):     return scalar("exposure", v)
        case let .sepia(v):        return scalar("sepia", v)
        case .mono:                return scalar("mono", 0)
        case let .gaussianBlur(v): return scalar("gaussianBlur", v)
        case let .vignette(v):     return scalar("vignette", v)
        case let .sharpen(v):      return scalar("sharpen", v)
        case let .zoomBlur(v):     return scalar("zoomBlur", v)
        case let .glow(v):         return scalar("glow", v)
        case let .lut(lut):
            return FilterData(kind: "lut", scalar: nil, url: lut.url.absoluteString,
                              red: nil, green: nil, blue: nil, threshold: nil)
        case let .chromaKey(key):
            return FilterData(kind: "chromaKey", scalar: nil, url: nil,
                              red: key.color.r, green: key.color.g, blue: key.color.b,
                              threshold: key.threshold)
        @unknown default:
            // A filter kind added upstream after this version was built. Naming it
            // "unknown" preserves its slot — so the parallel `filterIDs` and
            // `filterAnimations` arrays stay aligned — and decoding rejects it
            // loudly rather than substituting something that merely looks fine.
            return FilterData(kind: "unknown", scalar: nil, url: nil,
                              red: nil, green: nil, blue: nil, threshold: nil)
        }
    }

    static func filter(from data: FilterData) throws -> Filter {
        let v = data.scalar ?? 0
        switch data.kind {
        case "brightness":   return .brightness(v)
        case "contrast":     return .contrast(v)
        case "saturation":   return .saturation(v)
        case "exposure":     return .exposure(v)
        case "sepia":        return .sepia(intensity: v)
        case "mono":         return .mono
        case "gaussianBlur": return .gaussianBlur(radius: v)
        case "vignette":     return .vignette(intensity: v)
        case "sharpen":      return .sharpen(amount: v)
        case "zoomBlur":     return .zoomBlur(amount: v)
        case "glow":         return .glow(intensity: v)
        case "lut":
            guard let raw = data.url, let url = URL(string: raw) else {
                throw PersistenceError.malformed("A colour LUT has an unreadable file location.")
            }
            return .lut(try LUT(url: url))
        case "chromaKey":
            // Round-tripped through PlatformColor because `ChromaKey` cannot be
            // rebuilt from its own public properties: it exposes `color` as
            // `ColorComponents` but only initialises from a `PlatformColor`.
            // Worth an additive `ChromaKey(color: ColorComponents, threshold:)`
            // upstream; until then this is lossless anyway, since ColorComponents
            // carries no alpha.
            let colour = PlatformColor(
                red: CGFloat(data.red ?? 0), green: CGFloat(data.green ?? 1),
                blue: CGFloat(data.blue ?? 0), alpha: 1
            )
            return .chromaKey(ChromaKey(color: colour, threshold: data.threshold ?? 0.3))
        default:
            throw PersistenceError.malformed("Unknown filter “\(data.kind)”.")
        }
    }

    // MARK: - Text

    static func textStyleData(_ style: TextStyle) -> TextStyleData {
        TextStyleData(
            fontName: style.fontName,
            fontSize: style.fontSize,
            color: colorData(style.color),
            alignment: {
                switch style.alignment {
                case .leading: return "leading"
                case .center: return "center"
                case .trailing: return "trailing"
                }
            }(),
            weight: {
                switch style.weight {
                case .regular: return "regular"
                case .medium: return "medium"
                case .bold: return "bold"
                }
            }(),
            stroke: style.stroke.map { TextStrokeData(width: $0.width, color: colorData($0.color)) },
            shadow: style.shadow.map { TextShadowData(offset: offsetData($0.offset), blur: $0.blur) }
        )
    }

    static func textStyle(from data: TextStyleData) -> TextStyle {
        TextStyle(
            fontName: data.fontName,
            fontSize: data.fontSize,
            color: platformColor(from: data.color),
            alignment: {
                switch data.alignment {
                case "center": return .center
                case "trailing": return .trailing
                default: return .leading
                }
            }(),
            weight: {
                switch data.weight {
                case "medium": return .medium
                case "bold": return .bold
                default: return .regular
                }
            }(),
            stroke: data.stroke.map { TextStroke(width: $0.width, color: platformColor(from: $0.color)) },
            shadow: data.shadow.map { TextShadow(offset: offset(from: $0.offset), blur: $0.blur) }
        )
    }

    // MARK: - Overlays

    static func overlayData(_ overlay: any Overlay, at index: Int,
                            _ context: inout EncodeContext) throws -> OverlayData? {
        switch overlay {
        case let text as TextOverlay:
            let at = text.layerID.map { "overlay “\($0.rawValue)”" } ?? "the text “\(text.text.prefix(24))”"
            if text.textAnimation != nil { context.note(.textAnimation, at: at) }
            return .text(TextOverlayData(
                text: text.text,
                style: textStyleData(text.style),
                position: positionData(text.position),
                size: text.size.map(sizeData),
                anchor: anchorName(text.anchor),
                opacity: text.opacity,
                layerID: text.layerID?.rawValue,
                visibilityRange: text.visibilityRange.map(TimeRangeData.init)
            ))
        case let image as ImageOverlay:
            let at = image.layerID.map { "overlay “\($0.rawValue)”" } ?? "image overlay \(index + 1)"
            guard let token = try context.token(for: image.image, at: at) else { return nil }
            return .image(ImageOverlayData(
                imageToken: token,
                position: positionData(image.position),
                size: image.size.map(sizeData),
                anchor: anchorName(image.anchor),
                opacity: image.opacity,
                layerID: image.layerID?.rawValue,
                visibilityRange: image.visibilityRange.map(TimeRangeData.init),
                positionAnimation: image.positionAnimation.map {
                    animationData($0, at: at, &context, positionData)
                },
                sizeAnimation: image.sizeAnimation.map { animationData($0, at: at, &context, sizeData) }
            ))
        case let sticker as StickerOverlay:
            let at = sticker.layerID.map { "overlay “\($0.rawValue)”" } ?? "sticker \(index + 1)"
            guard let token = try context.token(for: sticker.image, at: at) else { return nil }
            return .sticker(StickerOverlayData(
                imageToken: token,
                position: positionData(sticker.position),
                size: sticker.size.map(sizeData),
                anchor: anchorName(sticker.anchor),
                opacity: sticker.opacity,
                layerID: sticker.layerID?.rawValue,
                rotation: sticker.rotation,
                shadow: sticker.shadow.map {
                    ShadowData(color: colorData($0.color), radius: $0.radius,
                               offset: offsetData($0.offset), opacity: $0.opacity)
                },
                visibilityRange: sticker.visibilityRange.map(TimeRangeData.init),
                positionAnimation: sticker.positionAnimation.map {
                    animationData($0, at: at, &context, positionData)
                },
                sizeAnimation: sticker.sizeAnimation.map { animationData($0, at: at, &context, sizeData) }
            ))
        default:
            throw PersistenceError.unsupportedOverlay(String(describing: type(of: overlay)))
        }
    }

    static func apply(_ data: OverlayData, to video: Video, _ context: DecodeContext) throws -> Video {
        switch data {
        case let .text(t):
            var overlay = TextOverlay(t.text, style: textStyle(from: t.style))
                .position(position(from: t.position))
                .anchor(anchor(named: t.anchor))
                .opacity(t.opacity)
            if let size = t.size { overlay = overlay.size(self.size(from: size)) }
            if let id = t.layerID { overlay = overlay.id(LayerID(id)) }
            if let range = t.visibilityRange { overlay = overlay.visible(during: range.range) }
            return video.overlay(overlay)
        case let .image(i):
            var overlay = ImageOverlay(try context.image(for: i.imageToken))
                .anchor(anchor(named: i.anchor))
                .opacity(i.opacity)
            if let animation = i.positionAnimation {
                overlay = overlay.position(position(from: i.position),
                                           animation: self.animation(from: animation, position(from:)))
            } else {
                overlay = overlay.position(position(from: i.position))
            }
            if let size = i.size {
                if let animation = i.sizeAnimation {
                    overlay = overlay.size(self.size(from: size),
                                           animation: self.animation(from: animation, self.size(from:)))
                } else {
                    overlay = overlay.size(self.size(from: size))
                }
            }
            if let id = i.layerID { overlay = overlay.id(LayerID(id)) }
            if let range = i.visibilityRange { overlay = overlay.visible(during: range.range) }
            return video.overlay(overlay)
        case let .sticker(s):
            var overlay = StickerOverlay(try context.image(for: s.imageToken))
                .anchor(anchor(named: s.anchor))
                .opacity(s.opacity)
                .rotation(s.rotation)
            if let animation = s.positionAnimation {
                overlay = overlay.position(position(from: s.position),
                                           animation: self.animation(from: animation, position(from:)))
            } else {
                overlay = overlay.position(position(from: s.position))
            }
            if let size = s.size {
                if let animation = s.sizeAnimation {
                    overlay = overlay.size(self.size(from: size),
                                           animation: self.animation(from: animation, self.size(from:)))
                } else {
                    overlay = overlay.size(self.size(from: size))
                }
            }
            if let shadow = s.shadow {
                overlay = overlay.shadow(StickerOverlay.Shadow(color: platformColor(from: shadow.color),
                                                radius: shadow.radius,
                                                offset: offset(from: shadow.offset),
                                                opacity: shadow.opacity))
            }
            if let id = s.layerID { overlay = overlay.id(LayerID(id)) }
            if let range = s.visibilityRange { overlay = overlay.visible(during: range.range) }
            return video.overlay(overlay)
        }
    }

    // MARK: - Audio

    static func pitchAlgorithmName(_ algorithm: AudioTimePitchAlgorithm) -> String {
        switch algorithm {
        case .spectral:   return "spectral"
        case .timeDomain: return "timeDomain"
        case .varispeed:  return "varispeed"
        }
    }

    static func pitchAlgorithm(named name: String) -> AudioTimePitchAlgorithm {
        switch name {
        case "timeDomain": return .timeDomain
        case "varispeed":  return .varispeed
        default:           return .spectral
        }
    }

    static func audioTrackData(_ track: AudioTrack) -> AudioTrackData {
        AudioTrackData(
            url: track.url.absoluteString,
            volumeLevel: track.volumeLevel,
            fadeInDuration: TimeData(track.fadeInDuration),
            fadeOutDuration: TimeData(track.fadeOutDuration),
            duckingLevel: track.duckingLevel,
            startTime: track.startTime.map(TimeData.init),
            explicitDuration: track.explicitDuration.map(TimeData.init),
            crossfadeDuration: track.crossfadeDuration.map(TimeData.init),
            volumeRamps: track.volumeRamps.map {
                VolumeRampData(startVolume: $0.startVolume, endVolume: $0.endVolume,
                               range: TimeRangeData($0.range))
            },
            speedRate: track.speedRate,
            pitchAlgorithm: pitchAlgorithmName(track.pitchAlgorithm)
        )
    }

    static func audioTrack(from data: AudioTrackData) throws -> AudioTrack {
        guard let url = URL(string: data.url) else {
            throw PersistenceError.malformed("An audio track has an unreadable file location.")
        }
        var track = AudioTrack(url: url)
            .volume(data.volumeLevel)
            .fadeIn(data.fadeInDuration.time)
            .fadeOut(data.fadeOutDuration.time)
        if let ducking = data.duckingLevel { track = track.ducking(ducking) }
        if let start = data.startTime { track = track.at(time: start.time) }
        if let duration = data.explicitDuration { track = track.duration(duration.time) }
        if let crossfade = data.crossfadeDuration { track = track.crossfade(crossfade.time) }
        for ramp in data.volumeRamps {
            track = track.volumeRamp(start: ramp.startVolume, end: ramp.endVolume, during: ramp.range.range)
        }
        // Applied unconditionally: the algorithm is meaningful even at 1x, and
        // `.speed(_:algorithm:)` is the only public door to it.
        track = track.speed(data.speedRate, algorithm: pitchAlgorithm(named: data.pitchAlgorithm))
        return track
    }

    // MARK: - Preset, quality, crop, transitions

    static func presetData(_ preset: Preset) -> PresetData {
        switch preset {
        case .auto:            return PresetData(kind: "auto", width: nil, height: nil, frameRate: nil, codec: nil)
        case .reelsAndShorts:  return PresetData(kind: "reelsAndShorts", width: nil, height: nil, frameRate: nil, codec: nil)
        case .tiktok:          return PresetData(kind: "tiktok", width: nil, height: nil, frameRate: nil, codec: nil)
        case .square:          return PresetData(kind: "square", width: nil, height: nil, frameRate: nil, codec: nil)
        case .cinema:          return PresetData(kind: "cinema", width: nil, height: nil, frameRate: nil, codec: nil)
        case let .custom(w, h, fps, codec):
            return PresetData(kind: "custom", width: w, height: h, frameRate: fps,
                              codec: codec == .hevc ? "hevc" : "h264")
        @unknown default:
            return PresetData(kind: "auto", width: nil, height: nil, frameRate: nil, codec: nil)
        }
    }

    static func preset(from data: PresetData) -> Preset {
        switch data.kind {
        case "reelsAndShorts": return .reelsAndShorts
        case "tiktok":         return .tiktok
        case "square":         return .square
        case "cinema":         return .cinema
        case "custom":
            return .custom(
                width: data.width ?? 1080, height: data.height ?? 1920,
                frameRate: data.frameRate ?? 30,
                codec: data.codec == "hevc" ? .hevc : .h264
            )
        default: return .auto
        }
    }

    static func qualityData(_ quality: ExportQuality) -> QualityData {
        switch quality {
        case .automatic:
            return QualityData(kind: "automatic", bitrate: nil, fileSizeBytes: nil)
        case let .bitrate(bps):
            return QualityData(kind: "bitrate", bitrate: bps, fileSizeBytes: nil)
        case let .fileSize(bytes):
            return QualityData(kind: "fileSize", bitrate: nil, fileSizeBytes: bytes)
        @unknown default:
            return QualityData(kind: "automatic", bitrate: nil, fileSizeBytes: nil)
        }
    }

    static func quality(from data: QualityData) -> ExportQuality {
        switch data.kind {
        case "bitrate":  return .bitrate(data.bitrate ?? 0)
        case "fileSize": return .fileSize(bytes: data.fileSizeBytes ?? 0)
        default:         return .automatic
        }
    }

    static func cropData(_ crop: CropRegion) -> CropData {
        CropData(position: positionData(crop.position),
                 size: sizeData(crop.size),
                 anchor: anchorName(crop.anchor))
    }

    static func slideDirectionName(_ direction: SlideDirection) -> String {
        switch direction {
        case .fromLeft: return "fromLeft"
        case .fromRight: return "fromRight"
        case .fromTop: return "fromTop"
        case .fromBottom: return "fromBottom"
        }
    }

    static func slideDirection(named name: String) -> SlideDirection {
        switch name {
        case "fromRight": return .fromRight
        case "fromTop": return .fromTop
        case "fromBottom": return .fromBottom
        default: return .fromLeft
        }
    }
}
