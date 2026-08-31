# kadr-persistence

Save a [kadr](https://github.com/SteliyanH/kadr) composition to a file, and open it again.

[![Swift versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FSteliyanH%2Fkadr-persistence%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/SteliyanH/kadr-persistence)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FSteliyanH%2Fkadr-persistence%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/SteliyanH/kadr-persistence)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-support-yellow.svg)](https://buymeacoffee.com/steliyanh)

```swift
let data = try KadrCoding.data(for: video)      // save
let video = try KadrCoding.video(from: data)    // open
```

That is the whole API for the common case. The rest of this README is about the
uncommon ones, because those are where a persistence layer earns its keep.

## Why this is a package and not thirty lines in your app

kadr's `Video` cannot be `Codable`. It holds `[any Compositor]` and
`TimingFunction.custom` — closures — and a `PlatformImage`, which is pixels with
no record of where they came from. So every app that saves a kadr project ends up
hand-writing a mirror of the DSL.

A hand-written mirror has one failure mode, and it is a bad one: you add a field
to a clip, forget to add it to the mirror, and **nothing fails**. Not the
compiler, not the round-trip test — a field missing from both sides of a
comparison compares equal. The project saves without complaint and reopens subtly
wrong, and you find out weeks later when a user asks why their titles lost their
colour.

That has already happened in this ecosystem more than once. This package exists so
it happens no more times.

## What it will not do

**It will not drop something silently.** Encoding *refuses* when the composition
holds content a file cannot represent:

```swift
do {
    let data = try KadrCoding.data(for: video)
} catch let error as PersistenceError {
    print(error.localizedDescription)
    // "A custom compositor on clip “hero” can't be saved — it's code, not data."
}
```

Ask before committing, so you can warn rather than apologise:

```swift
let losses = KadrCoding.lossyContent(in: video)
if losses.isEmpty {
    try save()
} else {
    show(losses.map(\.describedForUser))   // save anyway, or go back and change it
}
```

And save anyway when the user says so:

```swift
let data = try KadrCoding.data(for: video, allowingLoss: true)
```

Five things cannot be represented, and all five are reported rather than dropped:

| What | Why |
|---|---|
| `Compositor` on a clip | per-frame Core Image code |
| `MultiInputCompositor` on the composition | the same |
| `TimingFunction.custom` | an easing closure |
| `TextAnimation` on an overlay | an existential with open-ended conformers |
| A `PlatformImage` with no `ImageStore` | pixels with no identity to write down |

## Images

An `ImageClip` holds a decoded image, not a reference to one. A document can't
write that: embedding the bytes turns a ten-photo slideshow into a hundred
megabytes of base64, and every editor worth the name references its media rather
than swallowing it.

So the identity comes from you — the only layer that knows it:

```swift
struct PhotoLibraryStore: ImageStore {
    func token(for image: PlatformImage) throws -> String { /* the asset's local id */ }
    func image(for token: String) throws -> PlatformImage { /* fetch it back */ }
}

let data = try KadrCoding.data(for: video, images: PhotoLibraryStore())
let restored = try KadrCoding.video(from: data, images: PhotoLibraryStore())
```

Tokens are opaque here: any stable string works, as long as the same store
resolves it later. Without a store, images are reported as lossy — never written
with a placeholder that fails on open.

## The format

Plain JSON with sorted keys, so two saves of an unchanged project are byte-identical
and a diff is readable.

```json
{"schema":1,"video":{"audioTracks":[],"captions":[],"clips":[{"video":{...}}],...}}
```

Times are stored as `value`/`timescale`, not as seconds. `CMTime(value: 1, timescale: 30)`
written as `0.0333…` and read back is no longer frame 1 of a 30 fps timeline, and an
editor that snaps to frames will place the clip a frame short.

`schema` is refused when it is newer than this version understands. Reading a
future document on a best-effort basis means dropping the fields you don't know
about and erasing them on the next save — a refusal is the only behaviour that
cannot destroy a project.

## What is stored

Everything else. Clips (video, image, title, transition, and nested tracks), trims,
speed and speed curves, filters **with their identities**, transforms, opacity and
its animations, audio tracks with ramps and pitch algorithm, overlays, crop,
captions, preset, and export quality.

That list is enforced, not asserted: `CompletenessTests` reflects over each kadr
type and fails when it grows a stored property this package hasn't been taught to
handle. It is the reason a kadr upgrade cannot quietly start losing your data —
and it caught six missing fields on its first run.

## Installation

```swift
.package(url: "https://github.com/SteliyanH/kadr-persistence.git", .upToNextMinor(from: "0.1.0"))
```

`.upToNextMinor` rather than `from:` — this is pre-1.0, where `from:` would accept
breaking changes.

## Requirements

Swift 6 · iOS 17 · macOS 14 · tvOS 17 · visionOS 1 · kadr 1.0+

## Support

If this saved you an afternoon: [buy me a coffee](https://buymeacoffee.com/steliyanh).

## The kadr ecosystem

| Package | Purpose |
|---|---|
| [`kadr`](https://github.com/SteliyanH/kadr) | The engine. Declarative video composition and export — clips, tracks, transitions, filters, overlays, keyframe animation. |
| [`kadr-ui`](https://github.com/SteliyanH/kadr-ui) | SwiftUI components — preview, timeline, inspector, overlay host, keyframe editor. |
| [`kadr-persistence`](https://github.com/SteliyanH/kadr-persistence) | Save a composition to a file and open it again. |
| [`kadr-audio`](https://github.com/SteliyanH/kadr-audio) | Music library, voiceover recording, LUFS loudness. |
| [`kadr-captions`](https://github.com/SteliyanH/kadr-captions) | SRT, VTT, iTT, ASS and SSA parsing and authoring. |
| [`kadr-photos`](https://github.com/SteliyanH/kadr-photos) | Photos library integration. |

And a reference application: [**Kadr Studio**](https://github.com/SteliyanH/kadr-reels-studio), a short-form vertical video editor built on all six.

## License

MIT. See [LICENSE](LICENSE).
