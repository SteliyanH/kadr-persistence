# The completeness guard

Why this package tests shapes instead of values, and what that catches.

## The bug no round-trip test can find

Here is the bug this package exists to prevent, in full:

1. kadr's `Video` grows a field. Say `quality`, in v0.20.
2. The document mirror doesn't know about it.
3. Every test still passes.

Step 3 is the problem. A round-trip test encodes, decodes, and compares — and a
field that is missing from *both* sides of the comparison compares equal. The
value was never written, so it is never read, so nothing disagrees. The test is
green and the data is gone.

It is the same shape as every other green-check failure in this ecosystem: an
`-only-testing:` filter that excluded the failing target, a `@testable` import
that hid a cross-module break, a macOS-only CI job that never compiled the iOS
slice. In each case the check could not observe the failure, which is worse than
not having the check, because it reads as evidence.

## Testing the shape instead

So `CompletenessTests` doesn't compare values. It reflects:

```swift
let actual = Set(Mirror(reflecting: video).children.compactMap(\.label))
let known = encoded.union(deliberatelyNotEncoded)
#expect(actual.subtracting(known).isEmpty)
```

Every kadr type this package mirrors has a test naming its stored properties
exactly. Add a field upstream and the test fails with the field's name in the
message. The fix is to encode it — or to list it as deliberately not encoded, with
a reason, which is a decision someone has to make rather than one that gets made
by omission.

The assertion runs in both directions. A property that *vanishes* upstream fails
too, so the mirror can't keep encoding a field that no longer exists.

## What it caught

Its first run, against this package's own first draft, failed on `Video`: six of
its ten stored properties were missing from the mirror — `overlays`, `crop`,
`quality`, `captions`, and two compositor fields. `quality` was an entire kadr
release, shipped weeks earlier and already silently unsaved by the very package
written to prevent exactly that.

That is the argument for this test in one sentence. The author of a persistence
layer, actively thinking about completeness, writing the doc comment about silent
field loss, still dropped six fields — and no value-based test noticed.

## The three categories

Each type's properties fall into one of three sets, and the distinction is the
useful part:

- **`encoded`** — written to the document and read back.
- **`deliberatelyNotEncoded`** — can't be, and why. `multiInputCompositor` is
  code. `Video.duration` is a cache of `clips.reduce(+)`; encoding it would let a
  document assert a duration its own clips contradict.
- **`computed`** — not independent state.

A field with no category is a bug, and the test says so by name.
