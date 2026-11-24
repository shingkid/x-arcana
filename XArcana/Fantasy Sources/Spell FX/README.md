# Open spell animation accents

The game combines these short CC0 animations with its three-dimensional spell geometry.
The source frames remain at their original resolution.
They add animated light and smoke accents rather than replacing the large 3D silhouettes.

## Sources and reception

- [2D Spell Effects](https://opengameart.org/content/2d-spell-effects) by Mikodrak, credited inside the archive as Martin Jelinek for Nyrthos.
  The page lists CC0 and 90 favorites, observed on 25 November 2026.
  Comments describe use in released games and praise the lightning effects.
- [25 special effects rendered with blender](https://opengameart.org/content/25-special-effects-rendered-with-blender) by rubberduck.
  The page lists CC0 and 127 favorites, observed on 25 November 2026.
  The archive includes the Blender particle and compositing sources.

Favorites are community appreciation counts, not star ratings or a formal quality certification.
Both complete original ZIP files remain in this folder.
Their hashes and the selected original frame hashes are recorded in `source-frame-hashes.json`.
The original archives are not changed.
The retained source licenses and attribution are summarized in `Resources/Effects/LICENSES.txt`.

## Selected sequences

| Runtime name | Source sequence | Source frame size | Frames |
| --- | --- | --- | ---: |
| `lightning` | Nyrthos `fx1_blue_topEffect` | 98 × 203 | 22 |
| `fire` | rubberduck `explosion/fire` | 128 × 128 | 30 |
| `ice` | rubberduck `explosion/blueish_smoke` | 128 × 128 | 30 |
| `shield` | rubberduck `ring/blueish_smoke` | 128 × 128 | 40 |
| `summon` | rubberduck `ring/magic` | 128 × 128 | 40 |

The export packs each sequence into one atlas no larger than 1024 × 1024 pixels.
Two transparent pixels separate neighboring frames.
The runtime caches five atlas images and small transform tables.
It updates only the texture coordinates during playback.
Each card has two triangles, no light, no shadow, and automatic removal after one cycle.
Its parent effect controls the total number of simultaneous effects.

## Rebuild and verify

On a Mac with the Xcode command-line tools, run:

```sh
python3 "XArcana/Fantasy Sources/Spell FX/build_atlases.py"
```

The exporter verifies the original ZIP hashes before extracting selected PNG frames to a temporary folder.
`pack_atlases.swift` uses the system AppKit and ImageIO frameworks to produce the atlases.
No Python image library or new runtime dependency is required.
The exporter writes the atlases and `atlases.json` to `Resources/Effects`.
Do not edit generated atlases by hand.

Run `SpellVFXTests` in the Mac Catalyst test target.
These tests check shared textures, independent materials, animation changes, and timed removal.
Inspect the effect in the actual room at its final size because the original frames are small.
The test image checks texture animation, not the complete spell or connected Air 2 presentation.
