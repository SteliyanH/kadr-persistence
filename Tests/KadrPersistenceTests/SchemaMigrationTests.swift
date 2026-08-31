import Testing
import Foundation
import Kadr
@testable import KadrPersistence

/// Tests for `SchemaMigrator`.
///
/// There are no registered migrations yet — every format change so far has been
/// an added optional field, which needs none. So these drive the runner with
/// **synthetic** steps. That is the only way to know the mechanism works before
/// the day it has to, and the day it has to is the worst day to find out it
/// doesn't.
struct SchemaMigrationTests {

    private func document(schema: Int, extra: [String: Any] = [:]) -> [String: Any] {
        var object: [String: Any] = ["schema": schema, "video": ["clips": []]]
        for (key, value) in extra { object[key] = value }
        return object
    }

    /// A step that records that it ran, by adding a breadcrumb.
    private func step(_ from: Int) -> SchemaMigration {
        SchemaMigration(from: from, to: from + 1) { object in
            var out = object
            var trail = out["trail"] as? [Int] ?? []
            trail.append(from)
            out["trail"] = trail
            return out
        }
    }

    // MARK: - The chain

    @Test("A document already current is returned untouched")
    func currentDocumentIsUntouched() throws {
        let input = document(schema: 3)
        let output = try SchemaMigrator.migrate(input, to: 3, using: [step(1), step(2)])
        #expect(output["schema"] as? Int == 3)
        #expect(output["trail"] == nil)
    }

    @Test("Steps run in order, one hop at a time")
    func stepsRunInOrder() throws {
        let output = try SchemaMigrator.migrate(
            document(schema: 1), to: 4, using: [step(3), step(1), step(2)]   // deliberately unordered
        )
        #expect(output["trail"] as? [Int] == [1, 2, 3])
        #expect(output["schema"] as? Int == 4)
    }

    @Test("The runner updates the schema field, so a step doesn't have to")
    func schemaIsStampedByTheRunner() throws {
        let output = try SchemaMigrator.migrate(document(schema: 1), to: 2, using: [step(1)])
        #expect(output["schema"] as? Int == 2)
    }

    @Test("A step's edits are carried into the next step")
    func editsCompose() throws {
        let add = SchemaMigration(from: 1, to: 2) { object in
            var out = object; out["added"] = "by-step-1"; return out
        }
        let read = SchemaMigration(from: 2, to: 3) { object in
            var out = object
            out["saw"] = (object["added"] as? String) ?? "nothing"
            return out
        }
        let output = try SchemaMigrator.migrate(document(schema: 1), to: 3, using: [add, read])
        #expect(output["saw"] as? String == "by-step-1")
    }

    // MARK: - Refusals

    @Test("A gap in the chain is refused, not silently skipped")
    func aGapIsRefused() {
        // The dangerous failure: treat a missing step as a no-op and you hand
        // back a document nobody migrated, which then gets saved over the
        // original.
        #expect(throws: PersistenceError.self) {
            _ = try SchemaMigrator.migrate(document(schema: 1), to: 3, using: [step(1)])
        }
    }

    @Test("The gap names the versions it could not bridge")
    func theGapIsLegible() {
        do {
            _ = try SchemaMigrator.migrate(document(schema: 1), to: 3, using: [step(1)])
            Issue.record("expected a refusal")
        } catch let error as PersistenceError {
            guard case let .migrationUnavailable(from, to) = error else {
                Issue.record("expected migrationUnavailable, got \(error)")
                return
            }
            #expect(from == 2)
            #expect(to == 3)
            #expect(error.errorDescription?.isEmpty == false)
            #expect(error.recoverySuggestion?.isEmpty == false)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test("A document from the future is refused rather than migrated backwards")
    func futureDocumentIsRefused() {
        #expect(throws: PersistenceError.self) {
            _ = try SchemaMigrator.migrate(document(schema: 9), to: 2, using: [])
        }
    }

    @Test("A step that throws stops the chain instead of half-migrating")
    func aThrowingStepStopsTheChain() {
        let boom = SchemaMigration(from: 1, to: 2) { _ in
            throw PersistenceError.malformed("bad shape")
        }
        #expect(throws: PersistenceError.self) {
            _ = try SchemaMigrator.migrate(document(schema: 1), to: 3, using: [boom, step(2)])
        }
    }

    // MARK: - Raw JSON

    @Test("Raw bytes migrate, and come back with sorted keys")
    func rawBytesMigrate() throws {
        let input = try JSONSerialization.data(withJSONObject: document(schema: 1))
        let output = try SchemaMigrator.migrate(data: input, to: 2, using: [step(1)])
        let text = try #require(String(data: output, encoding: .utf8))
        #expect(text.hasPrefix("{\"schema\":2"))   // sorted keys put `schema` first
    }

    @Test("Bytes that aren't a JSON object are refused as malformed")
    func nonObjectBytesAreRefused() {
        #expect(throws: PersistenceError.self) {
            _ = try SchemaMigrator.migrate(data: Data("[1,2,3]".utf8), to: 1, using: [])
        }
    }

    // MARK: - The current state of the registry

    @Test("No migrations are registered, because none has been needed")
    func nothingIsRegisteredYet() {
        // Not a placeholder: this asserts the format's actual history. Every
        // change so far has been an added optional field, which older readers
        // decode as nil. If a step is ever registered, this fails and whoever
        // added it has to say so here.
        #expect(SchemaMigrator.registered.isEmpty)
        #expect(KadrDocument.currentSchema == 1)
    }

    @Test("A real schema-1 document passes through the empty chain unchanged")
    func realDocumentPassesThrough() throws {
        let video = Video { VideoClip(url: URL(fileURLWithPath: "/tmp/a.mov")).trimmed(to: 0...3) }
        let original = try KadrCoding.data(for: video)
        let migrated = try SchemaMigrator.migrate(data: original)
        #expect(migrated == original)
    }
}
