# ``KadrPersistence``

Save a kadr composition to a file, and open it again.

## Overview

```swift
let data = try KadrCoding.data(for: video)      // save
let video = try KadrCoding.video(from: data)    // open
```

That is the whole API for the common case. Everything else in this package exists
for one uncommon case: what happens when the composition holds something a file
cannot hold.

### Why a package, and not a mirror in your app

kadr's `Video` cannot be `Codable`. It holds `[any Compositor]` and
`TimingFunction.custom` — closures — and `PlatformImage`, which is pixels with no
record of where they came from. So every app that saves a kadr project hand-writes
a mirror of the DSL.

A hand-written mirror has one failure mode and it is a bad one: you add a field
upstream, forget to add it to the mirror, and *nothing fails*. Not the compiler,
not the round-trip test — a field missing from both sides of a comparison compares
equal. The project saves without complaint and reopens subtly wrong.

This package's answer is <doc:Completeness>: a test that reflects over kadr's types
and fails when they grow a field it hasn't been taught to handle.

### The rule

**Never drop something silently.** Encoding refuses by default, reports on
request, and never stays quiet:

```swift
let losses = KadrCoding.lossyContent(in: video)
if losses.isEmpty {
    try save()
} else {
    warn(losses.map(\.describedForUser))
}
```

## Topics

### Essentials

- ``KadrCoding``
- ``KadrDocument``

### When something can't be saved

- ``Lossy``
- ``PersistenceError``

### Images

- <doc:StoringImages>
- ``ImageStore``
- ``FileImageStore``
- ``PrefetchedImageStore``

### Articles

- <doc:Completeness>
- <doc:TheFormat>
- <doc:StoringImages>

### The document format

- ``VideoData``
- ``ClipData``
- ``VideoClipData``
- ``ImageClipData``
- ``TitleSequenceData``
- ``TransitionData``
- ``TrackData``
- ``AudioTrackData``
- ``OverlayData``
- ``TimeData``
