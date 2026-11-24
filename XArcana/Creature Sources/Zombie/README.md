# Office zombie asset

The source is [Zombie figure in torn office clothes by Innerscene](https://www.innerscene.com/tools/library/3d-parts/zombie-figure-in-torn-office-clothes-12ed13ac).
The publisher dedicates the mesh to the public domain under CC0 1.0.
`office-zombie-original.glb` retains the publisher's embedded copyright and license statement.
The license applies to this body asset, not to the separate user-supplied NPC portraits.

The publisher describes the model as stylized.
It includes a shaped face, individual fingers, pale skin, milky eyes, torn office clothes, a belt, and shoes.
The native version has 52,013 triangles across five meshes, with shared geometry and material resources across the zombie instances.
It uses metres, Y up, and Z forward.

The original source is a posed mesh without a walking rig.
The converter adds 17 weighted joints and reproducible walk, idle, swipe, and bite clips.
Combat samples joint poses from simulation time, including movement slowdown and pauses.
The game uses small differences in muted clothing colours and authored body proportions.
Exposed skin uses a softly paled cheek colour sampled from the selected portrait.
The original portrait pixels remain unchanged.
Each zombie has a name-only label above its head.
A small curved mesh follows the original tilted face, with shallow bridges across the eye and mouth recesses.
The renderer samples the original photograph through UV coordinates aligned to the detected eye line.
A similarity transform in image pixels preserves the photograph's proportions instead of stretching the mouth to the shared head.
The fitted surface covers the forehead, cheeks and chin and follows the head joint.
A local opacity mask feathers the face edges independently of the photograph's UV crop.
The source portrait files remain unchanged.
This treatment applies a photograph to the shared model.
It does not reconstruct the person's three-dimensional face.

## Rebuild

`Zombie.blend` is the editable Blender source with packed images.
`convert.py` imports the original GLB, reduces the surface to the mobile triangle budget, and exports `../../Resources/Creatures/Zombie.usdz`.
It also saves all three body variants, their `.rig.json` playback data, editable Blender files, and `metrics.json`.
Run this command from the `XArcana` directory with Blender 5.2.1:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
    --python 'Creature Sources/Zombie/convert.py'
```

Native macOS SceneKit imported all five meshes and their materials.
A native render verified the forward-facing orientation.
The studio preview is an authoring render, not a device gameplay capture.
The retained public studio preview shows an earlier version of the source.
The native review tool saves current captures outside the repository by default.
Pass `--output` to choose another local folder.
Use `--portraits <private Resources directory>` only for a local review with private portraits.
These captures use the actual `ZombieAppearance` code in native macOS SceneKit, outside the gameplay scene.
The fitted mesh uses the separate position, normal, and texture index channels preserved by SceneKit's USD importer.
`ZombieFace.json` records the authored facial landmarks in UV space.
`NPCFaces/regions.json` supplies corresponding landmarks in the original photographs.
