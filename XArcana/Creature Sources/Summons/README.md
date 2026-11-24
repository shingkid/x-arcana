# Summoned creatures

These assets replace the old runtime sphere-and-cone characters with artist-authored anatomical meshes.
The demon has a skull face, horns, and clawed hands.
It does not have wings.
The Patronus uses a detailed stag mesh with a translucent silver-blue SceneKit material.
Its bright edges, drifting particles, and animated wisps are applied in `Sources/RuneEffects.swift`.
The Blender stag preview shows the underlying mesh and maps, not the final spirit effect.
Use `Stag-SceneKit.png` to review the actual spirit shader.

## Sources and licenses

- Demon: [Grefuntor / Atmostatic, 2013](https://opengameart.org/content/demon), [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/).
- Stag: [CDmir and TinyWorlds, 2015](https://opengameart.org/content/old-deer-male), [CC0](https://creativecommons.org/publicdomain/zero/1.0/).

The runtime `Resources/Creatures/Summons-LICENSES.txt` contains attribution and modification notices.
Keep this notice when redistributing the demon model.
The original artist files are retained in `downloads/Demon - Blend/` and `downloads/CDmir-Stag.blend`.

## Rebuild

Run Blender 5.2 with file scripts disabled:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --disable-autoexec --python build_summons.py
```

The script writes `Demon.usdz` and `Stag.usdz` to `Resources/Creatures`.
It also writes packed editable `Demon.blend` and `Stag.blend` files, 1024-pixel textures, `Demon.rig.json`, `Stag.rig.json`, and `asset-report.json`.
It normalizes the models to floor level and exports Y-up coordinates.
The demon is 2.15 m tall.
The stag is 2.10 m tall including its antlers.

Both models retain weighted skeletons and detailed surfaces.
The demon has 58 bones and authored idle, walk, two-claw, ground-slam, and fire-breath clips.
The stag has 31 bones and reuses the source Run action for its charge.
The runtime applies the source Idle action while the stag waits.
The exporter samples joint transforms at 24 frames per second and stores named clips beside each USDZ.
`CharacterAnimation` interpolates these cached poses and changes bones only.
Combat controls movement through the room and damage.
Each actor has an independent skeleton, while immutable surface and texture data remain shared.

SceneKit imports the demon and stag skinning directly from USDZ.
The rig files also contain weighted mesh buffers for importers that omit skeletons.
The exporter normalizes the complete hierarchy and preserves bind transforms.
It does not overwrite the original artist files.
The detailed anatomy and normal maps improve the previous geometry; these are not photogrammetric or film-resolution assets.

## Verification

- Demon: 47,999 triangles, with embedded diffuse and normal maps.
- Stag: 54,351 triangles, with embedded head, body, and antler diffuse and normal maps.
- Both USDZ archives were inspected for their embedded textures.
- The actual SceneKit models were rendered and visually inspected in `Demon-SceneKit.png` and `Stag-SceneKit.png`.
- `Verification/Animation/native-rig-check.txt` records native skins, normalized bounds, and measured joint motion.
- `Verification/Animation/independent-rigs.txt` records independent skeleton checks for all three character types.
- `Verification/Animation/articulated-poses.png` is a SceneKit render of sampled attack and idle poses.
- `Tests/CharacterAnimationTests.swift` checks limb motion, independent actors, pause behavior, and Alan's racket attachment.

## Share package

Include the two final `.blend` files, `build_summons.py`, `animation_export.py`, the generated rig files, `textures/`, `asset-report.json`, this README, and the source originals listed above.
The source originals allow a later rebuild without a network download.
The rejected Innerscene model, duplicate source ZIP, inspection `.blend` files, `.blend1` backups, and preliminary source previews are working studies.
They do not need to be included in the share package.
Do not treat the rejected Innerscene model as the shipped stag.
