# Natural office-zombie appearance

`convert.py` derives all runtime bodies from the retained CC0 `office-zombie-original.glb`.
The source GLB is never overwritten.
The script recreates the fitted portrait surface before it changes body proportions.
The head and portrait surface stay identical across all three bodies.

`ZombieMale.usdz` has broader shoulders and a straighter torso.
`ZombieFemale.usdz` has narrower shoulders, a shaped waist, and wider hips.
These are local mesh changes, not whole-model scaling.
`Zombie.usdz` is the neutral fallback for an identity without an explicit assignment.
All bodies retain 52,013 triangles and five meshes.

The derived textures use pale, desaturated skin, dirty off-white shirts, charcoal trousers, and dark ties.
The existing tears and sunken eye treatment remain restrained.
The runtime permits small changes within a muted office-clothing palette.
It does not use color-coded skin variants.
The original portrait files and their landmark metadata remain unchanged.
The face shader preserves the photo's colour and contrast.
A pixel-space similarity mapping preserves its proportions.
The surrounding exposed skin receives a lightly paled cheek colour to soften the transition.
Face geometry remains a shared stylized head, not a reconstruction of each person.

`Resources/NPCPortraits/body-styles.json` records explicit body assignments by stable identity ID.
The public roster uses neutral bodies and generated portrait placeholders.
A private local build can supply the user's confirmed assignments and original portraits.
New identities receive the neutral body until this editable file is updated.
Unknown IDs, stale entries, unsupported schemas, and invalid values produce validation errors or diagnostic messages.
Names and photographs are not used to infer a body assignment.

Each body has a 17-joint weighted rig.
The lurching walk alternates hip, knee, foot and arm poses, with unequal left and right movement.
The swipe rotates the arm and torso separately.
The bite bends the spine, neck and head toward the target.
Combat supplies simulation time and keeps the existing damage contact at 0.34 seconds.
Animation cannot move the combat root or decide damage.
The source mesh, triangle count and five-mesh layout remain unchanged.
Small geometric cloth folds add surface variation without new triangles.
The runtime binds muted off-white, blue, tan and sage shirt variants to each skinned instance.
All body materials use matte, non-metal surfaces.

Run the exporter from the `XArcana` directory:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --disable-autoexec --python 'Creature Sources/Zombie/convert.py'
```

The exporter writes the three USDZ files and their editable derived Blender files.
It also writes `metrics.json`, including triangle counts, silhouette factors, source hash, and head-preservation checks.
The original source and generated-file hashes are recorded in `SHA256SUMS`.
Do not treat manual edits to generated Blender files as durable changes.
Make durable appearance changes in the generator.

Run the native SceneKit review with:

```sh
python3 'Creature Sources/Zombie/verify_native.py'
```

This compiles the actual appearance code with macOS image/color aliases in a temporary directory.
It checks all 42 mappings, independent joints and mapped face skin bindings before saving native renders in a temporary folder.
Pass `--output /private/tmp/xarcana-zombie-review` for a stable local output path.
Private portrait review outputs must stay outside this public repository.
The review is an asset-level check, not a gameplay or connected-controller test.
The older preview images describe the previous appearance.
Use the images with `office` in their filenames for this version.
