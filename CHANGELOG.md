# Changelog

All notable changes to KadrPersistence will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

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
