import Foundation

/// One step from one schema version to the next.
///
/// Migrations work on the raw JSON object, not on ``KadrDocument`` — because by
/// definition an old document does not decode into today's types. That is the
/// whole reason a migration is needed, so a mechanism that requires decoding
/// first can only handle the changes that did not need it.
///
/// Added in v0.5.
public struct SchemaMigration: Sendable {

    /// The version this step reads.
    public let from: Int

    /// The version it produces. Always `from + 1`: steps are single hops, and
    /// the chain composes them, so a document from any older version reaches
    /// the present by the same route every other one took.
    public let to: Int

    /// Transform the document body. Receives the decoded JSON object and
    /// returns the migrated one; the `schema` field is updated by the runner,
    /// not by the step.
    public let apply: @Sendable ([String: Any]) throws -> [String: Any]

    public init(
        from: Int,
        to: Int,
        apply: @escaping @Sendable ([String: Any]) throws -> [String: Any]
    ) {
        self.from = from
        self.to = to
        self.apply = apply
    }
}

/// Brings an older document up to the current schema.
///
/// ## There are no migrations yet, and that is the point
///
/// ``registered`` is empty. Every change to the format so far has been an
/// *added optional field*, which needs no migration: an older document decodes
/// it as `nil`, and that is by design rather than by luck.
///
/// The mechanism exists ahead of its first use because the alternative is
/// writing it under pressure, against a format that is already in the field,
/// with someone's projects as the test data. It is exercised today by
/// `SchemaMigrationTests` against synthetic steps, and by the committed fixture
/// corpus, which proves a real document still opens.
///
/// ## Adding one
///
/// 1. Bump ``KadrDocument/currentSchema``.
/// 2. Append a step to ``registered``.
/// 3. Add a fixture for the *old* version to the corpus, so the step keeps
///    being exercised after everyone has forgotten it.
///
/// Added in v0.5.
public enum SchemaMigrator {

    /// The steps this version knows, in order. Empty until a change needs one.
    public static let registered: [SchemaMigration] = []

    /// Migrate `object` up to `target`, applying each step in turn.
    ///
    /// - Returns: the migrated object, with its `schema` field updated.
    /// - Throws: ``PersistenceError/unsupportedSchema(found:supported:)`` when
    ///   the document is newer than `target`, and
    ///   ``PersistenceError/migrationUnavailable(from:to:)`` when the chain has
    ///   a gap — a missing step is a bug, and inventing a passthrough would
    ///   silently produce a document nobody migrated.
    public static func migrate(
        _ object: [String: Any],
        to target: Int = KadrDocument.currentSchema,
        using migrations: [SchemaMigration] = SchemaMigrator.registered
    ) throws -> [String: Any] {
        var version = object["schema"] as? Int ?? 0
        guard version <= target else {
            throw PersistenceError.unsupportedSchema(found: version, supported: target)
        }
        var current = object
        let byOrigin = Dictionary(migrations.map { ($0.from, $0) }, uniquingKeysWith: { first, _ in first })

        while version < target {
            guard let step = byOrigin[version] else {
                throw PersistenceError.migrationUnavailable(from: version, to: version + 1)
            }
            current = try step.apply(current)
            version = step.to
            current["schema"] = version
        }
        return current
    }

    /// Migrate raw JSON, returning raw JSON.
    ///
    /// Sorted keys on the way out, matching what ``KadrCoding`` writes, so a
    /// migrated document is byte-comparable with a freshly encoded one.
    public static func migrate(
        data: Data,
        to target: Int = KadrDocument.currentSchema,
        using migrations: [SchemaMigration] = SchemaMigrator.registered
    ) throws -> Data {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PersistenceError.malformed("The project file is not a JSON object.")
        }
        let migrated = try migrate(object, to: target, using: migrations)
        return try JSONSerialization.data(withJSONObject: migrated, options: [.sortedKeys])
    }
}
