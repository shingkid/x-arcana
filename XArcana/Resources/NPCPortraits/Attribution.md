# Public NPC placeholder portraits

All 42 images are original, non-photographic robot icons generated from geometric shapes.
They contain no supplied photographs, face analysis, or likenesses.
The ordinary roster names and runtime filenames remain for compatibility.
The names label fictional game characters in this public edition.
Body styles use neutral placeholder assignments, not retained personal metadata.

The placeholder artwork is dedicated to the public domain under CC0 1.0 Universal.
See https://creativecommons.org/publicdomain/zero/1.0/ for the legal terms.
This dedication applies only to the generated placeholders.
It does not change the licenses of other game assets.

Run `python3 XArcana/Tools/PreparePublicAssets.py` from the repository root to rebuild the public assets.
Use `--portraits-only` to rebuild the icons and metadata without Blender.
The PNG encoder uses Python's standard library.
The JPEG encoder uses macOS `sips` and retains compatible `.jpg` filenames.
`Resources/PublicAssets.json` records the generated hashes and the retained third-party asset allowlist.
Private source photos and their face-analysis records are excluded from this public checkout.
