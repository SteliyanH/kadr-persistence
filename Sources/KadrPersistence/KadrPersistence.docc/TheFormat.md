# The document format

What's on disk, and why it's shaped that way.

## Overview

Plain JSON with sorted keys:

```json
{"schema":1,"video":{"audioTracks":[],"captions":[],"clips":[...],"crop":null,
 "overlays":[],"preset":{"kind":"auto"},"quality":{"kind":"automatic"}}}
```

Sorted keys mean two saves of an unchanged project are byte-identical. That makes
the file diffable, makes "is this project dirty?" a comparison rather than a
guess, and makes a round-trip test able to assert on bytes.

## Time is rational, not decimal

```json
"trimRange": {"start": {"value": 1, "timescale": 30}, ...}
```

Not `0.0333…`. A `CMTime` is a rational number, and 1/30 has no exact binary
floating-point representation. Store it as seconds and frame 1 of a 30 fps
timeline comes back as *almost* frame 1 — an editor that snaps to frames places
the clip a frame short, and the error compounds across a timeline.

Storing `value` and `timescale` makes the round trip exact by construction rather
than by tolerance.

## Discriminated unions, flat payloads

A clip is tagged by kind:

```json
{"video": {"url": "...", "trimRange": null, ...}}
```

The payload is a flat pile of optionals rather than a nested hierarchy, because a
flat pile survives a field being added: a reader that doesn't know a key ignores
it, and a mirror decodes a missing optional as `nil`. Adding an optional field is
therefore *not* a schema break.

## Schema

`schema` is bumped only for changes an older reader cannot survive.

Reading is asymmetric on purpose:

- **Older document** — read it. Missing optionals decode as `nil`.
- **Newer document** — refuse it.

The refusal is the interesting half. A best-effort read of a future document means
silently discarding the fields this version doesn't understand — and then erasing
them permanently on the next save. Refusing is the only behaviour that cannot
destroy a project that a newer version of the app created.

## What the format does not hold

- **App metadata.** No project name, no thumbnail, no modified date. Reasonable
  things to want; none of them kadr's. A document format that grows app-specific
  fields becomes an app format. Wrap ``KadrDocument`` in your own `Codable` type.
- **Media.** Video and audio are URLs; images are ``ImageStore`` tokens. A project
  file that swallows its media is one nobody can sync.
- **Code.** Compositors and custom easing closures are reported via ``Lossy``, not
  serialised. No format encodes a closure honestly.
