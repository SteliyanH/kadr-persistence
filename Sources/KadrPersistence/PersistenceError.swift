import Foundation

/// Why a composition could not be saved or loaded.
public enum PersistenceError: Error, Sendable, Equatable {

    /// The document was written by a newer version of this package.
    ///
    /// Rejected rather than parsed on a best-effort basis: a document from the
    /// future may contain fields this version does not know about, and loading it
    /// anyway would silently discard them on the next save. Refusing is the only
    /// behaviour that cannot destroy a project.
    case unsupportedSchema(found: Int, supported: Int)

    /// A document is older than this version, but no migration step covers the
    /// gap between its schema and the next one.
    ///
    /// Refused rather than passed through: a missing step is a bug in the
    /// migration chain, and treating it as a no-op would hand back a document
    /// that nobody actually migrated — which then gets saved over the original.
    case migrationUnavailable(from: Int, to: Int)

    /// The composition contains content no document can represent, and the caller
    /// did not opt in to losing it. See ``Lossy``.
    case lossyContent([Lossy])

    /// A clip kind this version does not encode.
    case unsupportedClip(String)

    /// An overlay kind this version does not encode.
    case unsupportedOverlay(String)

    /// The document refers to an image, but no ``ImageStore`` was supplied to
    /// resolve it. Decoding cannot invent the pixels, and substituting a
    /// placeholder would hand back a composition that silently differs from the
    /// one that was saved.
    case missingImageStore(token: String)

    /// An image could not be turned into bytes, so there was nothing to store.
    case imageNotEncodable

    /// A token names an image that is no longer there — the file was deleted,
    /// or the store was pointed at a different directory.
    case imageUnresolvable(token: String)

    /// The document is structurally invalid — a discriminator naming a case that
    /// does not exist, or a field that does not parse.
    case malformed(String)
}

extension PersistenceError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case let .migrationUnavailable(from, to):
            return "This project uses an older format (\(from)) that this version can't upgrade to \(to)."
        case let .unsupportedSchema(found, supported):
            return "This project was saved by a newer version of the app (format \(found); this version reads \(supported))."
        case let .lossyContent(items):
            guard let first = items.first else { return "Part of this project can't be saved." }
            if items.count == 1 { return first.describedForUser }
            return "\(items.count) parts of this project can't be saved. \(first.describedForUser)"
        case let .unsupportedOverlay(kind):
            return "This project contains an overlay type this version can't save (\(kind))."
        case let .unsupportedClip(kind):
            return "This project contains a clip type this version can't save (\(kind))."
        case .missingImageStore:
            return "This project uses images, but the app didn't say where to find them."
        case .imageNotEncodable:
            return "An image in this project couldn't be saved."
        case .imageUnresolvable:
            return "An image in this project is missing."
        case let .malformed(detail):
            return "This project file is damaged. \(detail)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .unsupportedSchema:
            return "Update the app, then open it again."
        case .migrationUnavailable:
            return "Open it with the version that last saved it, and save it again there."
        case .lossyContent:
            return "Remove the custom effect, or save anyway and accept losing it."
        case .missingImageStore:
            return "Open it with an image store configured."
        case .imageUnresolvable:
            return "It may have been deleted, or moved out of the project's media folder."
        case .imageNotEncodable, .unsupportedClip, .unsupportedOverlay, .malformed:
            return nil
        }
    }
}
