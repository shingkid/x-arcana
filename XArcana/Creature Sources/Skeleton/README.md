# Detailed skeleton asset

The game uses [Walking Skeleton v1 by tevy](https://tevy.dev/models/skeleton), published under CC0 1.0.
The original download, publisher metadata, and license are preserved in this directory.
The downloaded GLB matches the publisher's SHA-256: `87f9f88bca06061afdea90922e8ec73da0e4ce677b74842e7dd98cae6e7e1788`.

The native asset contains 26,826 triangles, one mesh, 55 joints, and the original walk cycle.
Its material retains a 2048 × 2048 color map, 1024 × 1024 normal map, and 256 × 256 roughness map.
The output uses metres, Y up, and Z forward.
`Combat` loads one prototype and clones its rig for each enemy while sharing geometry and textures.
The green eye lights are added by the game.

## Rebuild

`Skeleton.blend` is the editable, packed Blender source.
`convert.py` imports `skeleton-uncompressed.glb`, selects the walk cycle, and exports `../../Resources/Creatures/Skeleton.usdz`.
It also writes `metrics.json` and a studio preview.
The preview is an authoring render, not a gameplay or device capture.

Run this command from the `XArcana` directory with Blender 5.2.1:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
    --python 'Creature Sources/Skeleton/convert.py'
```

The original GLB uses meshopt and KTX2 compression, which Blender's importer does not support directly.
`decompress.mjs` preserves its geometry and animation while converting the textures to PNG.
For that optional conversion step, install `@gltf-transform/core`, `@gltf-transform/extensions`, and `meshoptimizer` in a tools directory.
Set `GLTF_TOOL_PACKAGE` to that directory's `package.json` and `KTX_TOOL` to the Khronos KTX-Software 4.4.2 `ktx` executable.
Then run `node 'Creature Sources/Skeleton/decompress.mjs'`.

## Verification

Native macOS SceneKit imported the USDZ with one mesh, 26,826 triangles, 55 skin joints, and a walk animation.
Two snapshots at different animation times showed different walking poses.
A cloned model had its own bone nodes.
`CombatTests` also checks the bundled asset, shared geometry, independent rigs, animation, normal map, and triangle budget.
Those application tests must run after the USDZ is included in the app's resource build phase.
