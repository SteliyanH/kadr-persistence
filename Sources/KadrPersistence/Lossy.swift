import Foundation

/// Something in a composition that a document cannot represent.
///
/// **Why this type exists at all.** Some of what a `Video` holds is not data:
///
/// - ``Kadr/Compositor`` and ``Kadr/MultiInputCompositor`` — per-frame Core Image
///   code, held as existentials on a clip and on the composition.
/// - `TimingFunction.custom` — an easing curve, held as a closure.
/// - ``Kadr/TextAnimation`` — an overlay animation, held as an existential whose
///   conformers are open-ended.
///
/// And one thing is data without an identity: `PlatformImage`. An ``ImageClip``
/// holds decoded pixels with no record of where they came from, so a document has
/// nothing to write down unless the host supplies an ``ImageStore``.
///
/// A persistence layer has three options and only one of them is honest. It can
/// refuse to encode such a composition, it can encode it and say what was left
/// behind, or it can drop it silently. The third is what a hand-written mirror
/// tends to do, and it produces a project that saves without complaint and
/// reopens subtly wrong.
///
/// This package does the first by default and the second on request. It never
/// does the third.
public struct Lossy: Sendable, Equatable, Hashable {

    /// What kind of content could not be represented.
    public enum Kind: String, Sendable, Codable {
        /// A per-clip custom compositor.
        case compositor
        /// The composition's multi-input compositor.
        case multiInputCompositor
        /// A `TimingFunction.custom` easing closure.
        case customTimingFunction
        /// An overlay text animation.
        case textAnimation
        /// An image with no identity the document could record — no ``ImageStore``
        /// was supplied, so there is nothing to write but the pixels themselves.
        case image
    }

    public let kind: Kind

    /// Where it was, in terms a person can act on — a clip id where one exists,
    /// or a positional description where it does not.
    public let location: String

    public init(kind: Kind, location: String) {
        self.kind = kind
        self.location = location
    }

    /// A sentence naming what would be lost and where.
    public var describedForUser: String {
        switch kind {
        case .compositor:
            return "A custom compositor on \(location) can't be saved — it's code, not data."
        case .multiInputCompositor:
            return "The custom compositor on \(location) can't be saved — it's code, not data."
        case .customTimingFunction:
            return "A custom timing curve on \(location) can't be saved — it's code, not data."
        case .textAnimation:
            return "A text animation on \(location) can't be saved — it's code, not data."
        case .image:
            return "An image on \(location) can't be saved, because nothing records where it came from."
        }
    }
}
