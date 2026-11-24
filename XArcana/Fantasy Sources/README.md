# Editable fantasy assets

Open `FantasyRoom.blend` in Blender to edit the full archive.
The scene includes individual furniture objects, packed PBR textures, preview lights, and the start camera.
The runtime export batches objects by material and omits the preview lights and camera.

Run `Blender --background --python upgrade_room.py` to apply the supplied PBR materials and export `../Resources/Fantasy/FantasyRoom.usdz`.
This step also regenerates `FantasyRoom-preview.png`.
The script uses only the adjacent source files and does not download dependencies.
The preview is a Blender render.
The game uses SceneKit and its own lighting.
`Kenney-Room-Large.glb` and `Textures/colormap.png` preserve the imported CC0 architecture source.
See `Attribution.md` for the room and material licenses.

## Public companion placeholders

Alan and Albert use fresh geometric robot bodies, not imported prototype geometry or photo textures.
The generated artwork is dedicated to the public domain under CC0 1.0 Universal.
The public checkout excludes the private model, packed textures, photos, photo experiments, and derived Blender files.
The generator is the editable character source.
It starts an empty Blender scene and creates all geometry, materials, and bones procedurally.
It never opens an existing `.blend` file.

From the repository root, run `python3 XArcana/Tools/PreparePublicAssets.py` with Blender 5.2 installed.
The command also rebuilds the non-photographic NPC robot icons and their authored texture coordinates.
No additional Python package or network download is required.
The optional `--blender` argument selects a different Blender executable.
`Resources/PublicAssets.json` records the generated asset hashes and intentional retained third-party assets.
Hashes are reproducible with the same Blender and macOS image encoders.

The companion exporter retains the existing `PortraitCharacter` and `AlanCharacter` runtime names for compatibility.
Both bodies are 1.72 metres tall before runtime scaling.
Albert's existing 1.2 scale makes him approximately 2.06 metres tall.
Each body has a 20-bone weighted skeleton with separate limb joints.
The clips are `idle`, `walk`, `slap`, and `slam`.
The `slap` clip is the internal name for Alan's racket swing.
Its contact pose remains at 0.35 seconds.
Combat controls movement through the room.
The clips do not translate the combat root.

Keep each generated `.rig.json` beside its USDZ.
The attachment names are `rightHand`, `leftHand`, `mouth`, `chest`, and `hips`.
Alan's racket attaches to `rightHand`.
Names and floor halos remain separate from the skeleton.
`CharacterAnimationTests` checks moving limbs, independent actors, and racket attachment.
`PublicAssetsTests` checks public placeholders and generated provenance.

## Replace a placeholder

Use a source model with an explicit redistribution license.
Keep weighted limbs and independent skin bones.
Use metres, Y-up coordinates, feet on the ground, and the existing attachment and clip names.
Rebuild both runtime files and update the public manifest.
Verify the clips and attachments in SceneKit before shipping the replacement.
