# Roadmap

Where this package is going, and what it is deliberately not doing.

## Before 1.0

- **Schema 2 with a migration path.** Schema 1 is refused-if-newer and read-if-
  older, which is correct but untested against a real migration. The mechanism
  earns its keep only once there is something to migrate.
- **A file-backed `ImageStore`** shipped as a default, so the common case — a
  slideshow whose photos live in the app's own container — doesn't need every host
  to write the same thirty lines.
- **Fixture documents under test.** A committed `.json` per schema version, decoded
  in CI, so a format change that breaks old files fails a test rather than a user's
  project.

## Not planned

- **App metadata in the document.** A project name, a thumbnail, a modified date:
  all reasonable, none of them kadr's. A document format that grows app-specific
  fields becomes an app format and stops being reusable. Wrap `KadrDocument` in
  your own `Codable` type instead.
- **Embedding media.** Video and audio are referenced by URL and images by token.
  A project file that swallows its media is a project file nobody can sync.
- **Encoding compositors.** They are closures. No format encodes a closure; the
  honest move is to report them, which is what `Lossy` is for.

## Open questions

- Whether `TextAnimation` should become encodable upstream. Its three conformers
  (`FadeIn`, `SlideIn`, `ScaleUp`) are plain data — it is the protocol that makes
  them opaque. A `TextAnimationKind` enum in kadr would let all three round-trip
  and leave only genuinely custom ones lossy.
- Whether `ChromaKey` should gain `init(color: ColorComponents, threshold:)`. It
  exposes `color` as `ColorComponents` but only initialises from `PlatformColor`,
  so it cannot be rebuilt from its own public properties. Lossless here only
  because `ColorComponents` carries no alpha.
