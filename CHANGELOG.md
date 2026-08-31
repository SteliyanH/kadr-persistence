# Changelog

All notable changes to KadrPersistence will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.5.0] - 2026-08-31

The storage layer finished: the three pre-1.0 roadmap items, shipped.

### Added

- **`FileImageStore`** — the store most apps would otherwise write themselves.
  Images live as files in a directory you nominate; the project references them.

  Tokens are **relative** — `file:<name>.png`, resolved against the store's
  directory — and that is the substantive detail, not tidiness. An iOS app's
  container is `/var/mobile/Containers/Data/Application/<UUID>/`, and **that
  UUID changes**: on reinstall, on restore from backup, sometimes across an OS
  update. An absolute path written into a project on Monday can point nowhere on
  Friday with the project itself perfectly intact. Absolute tokens from
  hand-rolled stores still resolve, so existing projects keep opening.

  Names are content hashes, so the same image is stored once and a token is
  stable across saves. `prune(keeping:)` deletes what a composition no longer
  refers to.

- **`SchemaMigrator`** — the migration mechanism, ahead of its first use.
  Steps operate on the raw JSON object rather than on `KadrDocument`, because an
  old document by definition does not decode into today's types — a mechanism
  that requires decoding first can only handle the changes that did not need it.

  A gap in the chain is **refused**, not skipped: treating a missing step as a
  no-op hands back a document nobody migrated, which then gets saved over the
  original.

  `registered` is empty and a test asserts that, because it is a statement about
  the format's history rather than a placeholder — every change so far has been
  an added optional field.

- **A committed fixture corpus.** A broad schema-1 document — every clip kind, a
  nested track, filters with identities, animations, audio ramps, all three
  overlay kinds, crop, captions — decoded on every run, including a
  **byte-for-byte re-encode**. Every other test here encodes and decodes with
  today's code, so both sides move together and neither can see a change that
  breaks *yesterday's* files. This one can.

  The generator that writes the corpus is disabled on purpose: a suite that can
  rewrite its own evidence proves nothing.

### Notes

- `PersistenceError` gains `imageNotEncodable`, `imageUnresolvable(token:)` and
  `migrationUnavailable(from:to:)`, all with recovery suggestions where there is
  one to give.

## [0.4.0] - 2026-08-31

### Fixed

- **Text animations are saved instead of refused.** Every `TextAnimation` was
  reported as ``Lossy``, on the reasoning that the protocol has an open set of
  conformers. But the three kadr ships — `FadeIn`, `SlideIn`, `ScaleUp` — are
  plain data, and reporting them meant a composition built with kadr's own
  animation picker **could not be saved at all** under the default strict
  encoding.

  The reference app hit exactly that: adding a fade to a text overlay made
  autosave throw, so the project silently stopped saving from that point on.
  Found by asking whether the app could author any of the five lossy things —
  the answer had been assumed rather than checked.

  A conformer this version does not recognise is still reported rather than
  guessed at.

- The animation's duration is stored as a rational, like every other time in the
  format, so a 1/30 s fade is still one frame after a round trip.

### Notes

- **Not a schema bump.** `textAnimation` is optional and appended, so a document
  written by 0.1–0.3 decodes with `nil` — the property the format was designed
  around, now exercised by a test that strips the field and reads the document
  back.

## [0.3.0] - 2026-08-28

### Added

- **Public initialisers on every document type.** Swift synthesises a memberwise
  initialiser for a `public struct`, but that initialiser is `internal` — so all
  27 mirror types here were readable from outside the module and impossible to
  construct. A document format whose types only this package can build is half a
  format: a migration tool, a fixture, a test in the host app, or anything that
  writes a project without going through a `Video` all hit the same wall.

  ```swift
  let document = KadrDocument(video: VideoData(
      clips: [.transition(TransitionData(kind: "fade", duration: .init(half), direction: nil))],
      audioTracks: [], preset: PresetData(kind: "tiktok", ...), overlays: [],
      crop: nil, quality: QualityData(kind: "automatic", ...), captions: []
  ))
  ```

  Found the same way as everything else in this package's short history: by
  consuming it from another module, where the internal doors are not there.

## [0.2.0] - 2026-08-28

Adopts kadr 1.0.

### Changed

- **kadr floor raised to `1.0.0`, pinned with `from:`.** No API change: kadr 1.0
  is a stability commitment with no code in it. The pin style matters more than
  the number — pre-1.0 this package accepted exactly one kadr minor, which meant
  an app using both had to match it exactly.

- **`ChromaKey` now round-trips through its own properties.** kadr 1.0 added
  `ChromaKey(color:threshold:)` taking `ColorComponents` — the gap this package
  reported in its own ROADMAP. Decoding no longer detours through
  `PlatformColor`, which was lossy on macOS for anything outside sRGB.

## [0.1.0] - 2026-08-28

First release. A document format for kadr compositions, and the encoder that
refuses to lie about what it saved.

### Added

- **`KadrCoding`** — `data(for:)` / `video(from:)` for JSON, `encode(_:)` /
  `decode(_:)` for the document itself.

- **`KadrDocument`** — the format. Plain JSON, sorted keys, schema-versioned.
  Times are stored as `value`/`timescale` rather than seconds, so a frame boundary
  survives the round trip exactly.

- **`Lossy` and refusal-by-default.** Encoding throws rather than dropping content
  a file cannot hold — compositors, custom timing closures, text animations, and
  images with no `ImageStore`. `lossyContent(in:)` asks without saving;
  `allowingLoss: true` saves anyway and reports what was left behind.

- **`ImageStore`** — how the host names its images, so image clips and image
  overlays can round-trip by reference rather than by embedding megabytes of
  base64.

- **`PersistenceError`** — `LocalizedError` throughout, with a
  `recoverySuggestion` where there is one to give.

### Covered

Video clips, image clips, title sequences, transitions, and nested tracks. Trims,
reversal, muting, replacement audio, volume, speed and speed curves. Filters with
their `FilterID`s intact. Transforms, opacity, and their animations. Audio tracks
with volume ramps and pitch algorithm. Text, image, and sticker overlays. Crop,
captions, preset, and export quality.

### Notes

- **The completeness guard.** `CompletenessTests` reflects over each kadr type and
  asserts its stored properties are exactly the set this package handles. It is
  the only test here that can catch the bug this package exists to prevent: a
  field missing from *both* sides of a round-trip comparison compares equal, so no
  value-based test can see it. It caught six missing `Video` fields — including
  `quality`, an entire kadr release — on its first run, in this package's own
  first draft.

- **Four kadr gaps were found by building this**, and fixed upstream in kadr
  0.21.0: `AudioBuilder` had no `buildArray`, so audio tracks could not be
  restored from an array; `FilterID`s could be read but never written back;
  `Video { }` did not compile; and `Preset` was not `Equatable`. Each was
  invisible from inside kadr, where the internal initialisers are in reach.
