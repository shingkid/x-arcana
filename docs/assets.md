# Assets and permissions

The public repository uses generated robot portraits and geometric companions instead of privately supplied photographs and models.
The original private files are not required to build the public edition.
The application keeps the same rig and attachment contracts so replacement artwork can be added later.

## Rebuild placeholders

```sh
python3 XArcana/Tools/PreparePublicAssets.py --blender /Applications/Blender.app/Contents/MacOS/Blender
```

The generator starts Blender from an empty scene and writes models, rigs, portraits, coordinates, and hash manifests.
Use `--portraits-only` when changing only the generated portrait artwork.
`XArcana/Resources/PublicAssets.json` records output hashes and provenance.
`PublicAssetsTests` checks placeholder images and articulated model contracts.

## Included artwork

| Asset | Source and terms |
| --- | --- |
| Public portrait icons and companion placeholders | Original procedural artwork, CC0 |
| Dungeon base and room textures | Kenney and Poly Haven, CC0, see Fantasy Sources/Attribution.md |
| Zombie bodies | See Creature Sources/Zombie/README.md |
| Demon | CC BY attribution retained in Resources/Creatures/Summons-LICENSES.txt |
| Stag | CC0, original source records retained |
| Spell animation frames | CC0 sources and licenses retained in Fantasy Sources/Spell FX |
| Generated spell sounds | Reproducible through Tools/GenerateAudio.py |
| Nyan Cat character | Procedural fan-art model after Chris Torres’s [original design](https://www.nyan.cat/), not a supplied or licensed original model |
| Nyan Cat recording | daniwell, vocal Momone Momo, non-commercial derivative-game permission |
| Head-tracker dependencies | Separate licenses in Mac Head Tracking/Licenses |

Read each source record before redistributing an asset.
The repository is public, but its bundled media does not share one blanket license.
No blanket software license has been selected for the project's own code.

Nyan Cat music: **Nyan Cat** by **daniwell**, vocal **Momone Momo (桃音モモ)**.
The [official catalog](https://aidn.jp/sound/) and [creator's terms](https://daniwell.com/about/) are recorded with the source audio.
The character and recording are not CC0.
The character mesh is rebuilt from the pixel pattern in `RainbowCat.swift`, without a downloaded image or model.
Keep its credits and permission record when sharing this non-commercial project.

## Replace artwork

Keep private replacements outside public Git history.
Use a separate private asset pack or private repository if you need real portraits.
Export replacement companion bodies with the documented twenty-bone rig and attachment names.
See [the character exporter guide](../XArcana/Fantasy%20Sources/README.md).
Do not edit generated rig JSON by hand.

Environment replacement has a separate [scene and bounds contract](environments.md).
Run native animation, portrait, and environment tests after an asset change.
