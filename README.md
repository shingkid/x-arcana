# X Arcana

A fantasy survival game for XREAL Air 2, a Mac, and an iPhone.
The Mac renders the game and owns combat state.
The iPhone sends motion, touch, and spoken commands over the local network.
Connect the glasses directly to the Mac through USB-C video.

This public edition uses generated portrait and companion placeholders.
Private photographs and privately supplied character models are excluded.
Third-party assets retain their own licenses.

## Get started

1. Open `XArcana/XArcana.xcodeproj` in Xcode.
2. Select the `XArcana` scheme and **My Mac (Mac Catalyst)**, then run.
3. Select your connected iPhone and your signing team, then run the controller.
4. Keep both devices on the same local network.
5. Build the head tracker with `XArcana/Mac Head Tracking/build.sh`.
6. Connect the Air 2 to the Mac and use `Start X Arcana.command` after installing the Mac app in Applications.

See the [build and play guide](X%20Arcana%20Build%20Guide.md) for permissions and troubleshooting.

## Play

Point the phone at a world or weapon option, tap to select, and double-tap to confirm.
The first zombie arrives after the three-second countdown.
In wand mode, hold the screen, draw, and release.
Wave without touching the screen to strike a nearby zombie for 0.5 damage.
Draw Z for lightning, O for fire, V for ice, or a star for the demon.
Hold still for the shield and release after the readiness vibration.
The shield absorbs 20 damage and stays until depleted.
It costs 20 MP, has a ten-second cooldown, and does not refill when a new stage begins.
Say **nyan nyan** to invoke Nyan Cat.
Nyan, demon, Alan, and Albert are omitted from the in-game spell guide.
Say **cast** or **shoot** to switch weapons.
Tap to fire the bow.
Each arrow deals 1 damage, so two hits defeat a full-health 2 HP zombie.
Say **Albert**, **Alan**, **Patronus**, **Lumos**, or **Revelio** for the other spells.

Without head tracking, use **WASD** to move and the **arrow keys** to look around during play.
The iPhone still controls spells and the bow.
For experimental physical movement, enable **Phone walking** on the Mac and allow the iPhone camera.
Hold the phone near your torso with the rear camera facing forward.
Walking pauses during drawing and briefly after release.
This tracks the phone's position, not the glasses, and can also be previewed on the Mac display.

Start with 100 HP and 100 MP.
Each level is one stage of eight zombies with 2 HP each.
Spawns start eight seconds apart and become 10% faster each level, down to two seconds apart.
Zombie hits start at 1 damage and increase by 0.5 each level.
The bow reloads in 0.5 seconds and uses tighter hitboxes and less aim assistance.
The demon requires a star, drains 20 MP per second, and vanishes after five seconds or when mana runs out.
Nyan requires 20 defeats before each use, including the first.
It transforms only zombies on the field; queued zombies wait until the curse ends.
Each kill earns 100 score, and clearing the stage earns another 250.
After a twenty-second break, the next stage begins and adds 10 maximum HP and MP, then fully refills both.
Kills do not grant XP or increase the level.
Restart returns to setup at level 1 and keeps best records.
Reset scores clears current and saved scorekeeping after confirmation.

## Develop

| Task | Guide |
| --- | --- |
| Understand ownership and runtime flow | [Architecture](docs/architecture.md) |
| Add a spell with Codex or by hand | [Adding spells](docs/adding-spells.md) |
| Replace the scene and combat layout | [Environments](docs/environments.md) |
| Build, test, and regenerate files | [Contributing](CONTRIBUTING.md) |
| Package the Mac and iPhone apps | [Distribution](docs/distribution.md) |
| Review asset permissions | [Assets and licenses](docs/assets.md) |

The game uses UIKit, SceneKit, Core Motion, Speech, and Network frameworks.
The head tracker uses pinned community XREAL sensor code.
The Air 2 helper provides head rotation only.
Optional ARKit tracking estimates phone translation; neither mode maps furniture for game collisions or real-world occlusion.

```sh
python3 XArcana/Tools/SyncProject.py --check
Tools/build.sh test
Tools/build.sh mac
Tools/build.sh iphone
```

The phone bundle excludes the Mac's scene assets and game audio.
Use `SIMULATOR_ID=<uuid> Tools/build.sh ui` for controller interface tests.

Zombie health bars sit below their names and face the player.
The two sections each represent 1 HP and one bow hit.
Spell and ally damage also update the bars, including partial sections.
Bars disappear on death and during Nyan transfiguration.

## Demon King and later levels

Levels 1 to 9 contain zombie stages.
Level 10 replaces the horde with one winged demon boss with 30 HP.
Entering level 10 grants 20 maximum HP and MP instead of 10.
Both resources refill to 200 for the boss fight.
He flies slowly around the arena and signals attacks before contact.
Each claw deals 4 damage, the ground slam deals 8, and fire breath deals 6.
The boss has a continuous health bar and numeric HP above him.
Arrows always deal 1 damage, including against the boss (30 hits from full health).
Nyan transforms zombies only; kings remain hostile during the curse.
The first king defeated permanently unlocks the star summon.
Each king awards 1,000 score; clearing all live and queued enemies awards another 250.
The run continues after level 10.
Dying, reaching level 10, and drawing a star do not unlock it.
Restart and Reset scores retain this unlock.
After unlocking, the friendly demon keeps its 20 MP per second drain and five-second lifetime.

| Level | Demon Kings | Zombies |
| --- | ---: | ---: |
| 10 | 1 | 0 |
| 11 | 1 | 2 |
| 12 | 1 | 4 |
| 13 | 1 | 6 |
| 14 | 1 | 8 |
| 15 to 19 | 2 | 8 |
| 20 to 24 | 3 | 8 |
| 25 to 29 | 4 | 8 |

Add one king every five levels after level 10.
Up to three kings are active together; further kings wait in the spawn queue.
King arrivals are at least four seconds apart, and the existing zombie spawn interval still applies.
A level clears only after every live and queued enemy is defeated.
The twenty-second break and full resource refill then lead into the next level.
Each resource maximum increases by 10 again after level 10: level 11 starts at 210 HP and MP.
