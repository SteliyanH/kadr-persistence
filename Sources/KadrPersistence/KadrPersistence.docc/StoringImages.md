# Storing images

Where a composition's pictures live, and why the answer is never "in the project file".

## Overview

An ``Kadr/ImageClip`` holds a decoded `PlatformImage` — pixels, with no record
of where they came from. A document cannot write that down, so this package asks
you for an ``ImageStore``: something that can name an image, and find it again.

Two are supplied. Which you want depends on one question: **can the image be
fetched synchronously?**

| | Use |
|---|---|
| The image is, or can be, a file | ``FileImageStore`` |
| The image comes from somewhere asynchronous — a photo library, a network | ``PrefetchedImageStore`` |

## Files

``FileImageStore`` keeps images in a directory you nominate and the project
references them:

```swift
let images = try FileImageStore(directory: mediaDirectory)
let data = try KadrCoding.data(for: video, images: images)
let restored = try KadrCoding.video(from: data, images: images)
```

### Where the directory goes

Beside your projects, one directory for the whole library rather than one per
project. The store is content-addressed, so two projects using the same photo
store it once — a per-project directory would store it twice and prune it twice.

### Why the token is relative

A token is `file:<name>.png`, resolved against ``FileImageStore/directory``. It
is never an absolute path, and that is the single most important thing on this
page.

An iOS app's container is `/var/mobile/Containers/Data/Application/<UUID>/`, and
**that UUID changes** — on reinstall, on restore from backup, sometimes across
an OS update. An absolute path written into a project on Monday can point
nowhere on Friday, with the project itself perfectly intact: a project that
opens, looks right, and has lost its pictures.

Storing the name and resolving it against a directory the app locates at runtime
is what makes the reference durable. Absolute tokens written by earlier,
hand-rolled stores still resolve, so nothing that already exists stops opening.

### Housekeeping

```swift
let document = try KadrCoding.encode(video, images: images)
try images.prune(keeping: PrefetchedImageStore.tokens(in: document))
```

Without it the directory accumulates the bytes of every image ever removed from
the project.

## Asynchronous sources

``ImageStore`` is synchronous. That fits files and fits bytes; it does not fit a
photo library, where resolving a `PHAsset` means `PHImageManager` and a
callback.

The obvious fix — an async `ImageStore`, and async `encode`/`decode` to match —
was considered and rejected. It makes the encode path async for *every*
consumer, including the many with no images at all, to serve the one case that
needs it.

``PrefetchedImageStore`` is the other answer: **resolve first, then encode.**
The `await` stays in the layer that already had one.

```swift
// 1. Read the document on its own, and ask what it needs.
let document = try JSONDecoder().decode(KadrDocument.self, from: data)
let needed = PrefetchedImageStore.tokens(in: document)

// 2. Resolve, asynchronously, however your source works.
var images: [String: PlatformImage] = [:]
for token in needed {
    images[token] = try await photoLibrary.image(forLocalIdentifier: identifier(from: token))
}

// 3. Build the composition, synchronously.
let video = try KadrCoding.decode(document, images: PrefetchedImageStore(images))
```

The step that makes this work is the second line: a document is readable on its
own, so the tokens are knowable *before* the composition is built. There is no
chicken-and-egg problem, only the appearance of one.

### Encoding from an asynchronous source

Easier, because you already hold the images: seed the store with the tokens you
intend, and ``PrefetchedImageStore`` will reproduce them.

An image it was not given is **refused**, never given an invented token. A
made-up token encodes cleanly and resolves to nothing on the next open, which is
exactly the silent loss this package exists to prevent.

## Writing your own

The protocol is two methods. The only rule that is not obvious:

> **A token must be stable across saves.** A store that mints a fresh token per
> encode rewrites every byte of the project file every time it is saved, which
> defeats the format's sorted-key determinism and makes "is this project dirty?"
> unanswerable.

Content-addressing gets you that for free, which is why both supplied stores use
it.

## Topics

### Stores

- ``ImageStore``
- ``FileImageStore``
- ``PrefetchedImageStore``

### Errors

- ``PersistenceError/imageNotEncodable``
- ``PersistenceError/imageUnresolvable(token:)``
- ``PersistenceError/missingImageStore(token:)``
