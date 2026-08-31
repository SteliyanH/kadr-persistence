# Roadmap

Where this package is going, and what it is deliberately not doing.

## Before 1.0

All three of the original pre-1.0 items shipped in 0.5.0. What remains:

- **A real schema 2.** The mechanism, the fixture corpus and the refusals are in
  place; there is simply nothing yet that needs a migration, because every
  change so far has been an added optional field. The first genuine break gets
  a step, and a fixture of the version before it.
- **Async image resolution.** ``ImageStore`` is synchronous, which fits files
  and blobs but not a photo library: resolving a `PHAsset` means
  `PHImageManager`, which is callback-based. A host wanting library-backed
  images must pre-resolve them today. An `AsyncImageStore` alongside the
  synchronous one is the likely shape, but it changes the encode path from
  sync to async for everyone, so it wants a real caller before it is designed.
- **Deletion policy for a shared store.** ``FileImageStore/prune(keeping:)``
  takes the tokens of one composition. Two projects sharing a directory would
  each prune the other's images. Documented, not yet solved — the fix is
  probably reference counting across documents, which needs a host that has
  the problem.

## Shipped

- ~~**Schema 2 with a migration path.**~~ ``SchemaMigrator`` in 0.5.0. Steps
  operate on raw JSON, because an old document by definition does not decode
  into today's types. A gap in the chain is refused rather than passed through.
- ~~**A file-backed `ImageStore`.**~~ ``FileImageStore`` in 0.5.0, with
  content-addressed, **relative** tokens.
- ~~**Fixture documents under test.**~~ A committed schema-1 document, decoded
  on every run — including a byte-for-byte re-encode, which is the only test
  here that can catch a change breaking *yesterday's* files.

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

- ~~Whether `TextAnimation` should become encodable upstream.~~ **Answered in
  0.4.0, and it needed no upstream change.** The three conformers are public
  structs with public properties, so this package downcasts to each and encodes
  it; only a conformer it does not recognise stays lossy. Worth remembering as a
  general point: an existential is not automatically unencodable — it is
  unencodable only where its conformers are.
- ~~Whether `ChromaKey` should gain `init(color: ColorComponents, threshold:)`.~~
  **Answered: yes, and it shipped in kadr 1.0.** Decoding no longer detours
  through `PlatformColor`, which was lossy on macOS outside sRGB.
