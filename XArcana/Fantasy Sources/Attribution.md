# Fantasy room asset sources

The fantasy room was assembled in Blender for X Arcana.
It uses the licensed source geometry and materials below.

## Architecture

- Source: Kenney, Modular Dungeon Kit 2.0, `room-large.glb`.
- Official page: https://kenney.nl/assets/modular-dungeon-kit
- Creator's download mirror: https://opengameart.org/content/modular-dungeon-kit
- Download: https://opengameart.org/sites/default/files/kenney_modular-dungeon-kit_2.0.zip
- License: CC0 1.0 Universal, https://creativecommons.org/publicdomain/zero/1.0/
- A copy of the source package license is `Kenney-License.txt`.

The room was rescaled, cleared of internal pillars and floor debris, and furnished with bookshelves, arches, candles and an arcane portal.

## PBR materials

The 1K diffuse, OpenGL normal and roughness maps come from Poly Haven.
All maps are CC0 under https://polyhaven.com/license.

- Stone Wall 05 by Charlotte Baglioni: https://polyhaven.com/a/stone_wall_05
- Wood Floor Worn by Dimitrios Savva: https://polyhaven.com/a/wood_floor_worn
- Stone Floor by Dimitrios Savva: https://polyhaven.com/a/stone_floor
- Brown Leather by Rob Tuytel: https://polyhaven.com/a/brown_leather

The runtime USDZ embeds these textures.
The editable Blender source also packs the images.
The adjacent source texture folder and `upgrade_room.py` support offline re-export.

## Public companion placeholders

`PortraitCharacter.usdz` and `AlanCharacter.usdz` contain original procedural geometric robot bodies.
`Fantasy Sources/build_portrait_character.py` generates them from a fresh empty Blender scene.
Their 20-bone skeletons and authored clips preserve the runtime attachment contract.
No private prototype mesh, packed photo texture, or supplied portrait is included.
The generated companion artwork and NPC robot icons are dedicated to CC0 1.0 Universal.
See https://creativecommons.org/publicdomain/zero/1.0/ for the legal terms.
This dedication applies only to the generated placeholders.
It does not change the third-party licenses described above.
`Resources/PublicAssets.json` records the generator, output hashes, and retained asset allowlist.

## Coordinate contract

The runtime room uses metres and Y-up.
The floor is Y = 0.
The start position is (0, 1.65, 4.8), looking toward (0, 1.65, -2.6).
The central combat aisle is clear within X = -2.4 to 2.4 and Z = -5.6 to 5.4.
The outer room extends approximately X = -5.2 to 5.2 and Z = -6.8 to 6.8.
Blender preview lights are retained in the editable source, while the app supplies its own runtime lights.
