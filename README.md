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
Wave without touching the screen to strike a nearby zombie for 1 damage.
Draw Z for lightning, O for fire, V for ice, or a star for the demon.
Hold still for the shield and release after the readiness vibration.
The shield absorbs 20 damage and stays until depleted.
It costs 20 MP, has a ten-second cooldown, and does not refill when a new stage begins.
Say **nyan nyan** to invoke Nyan Cat.
Nyan, demon, Alan, and Albert are omitted from the in-game spell guide.
Say **cast** or **shoot** to switch weapons.
Tap to fire the bow.
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
The bow reloads in 0.4 seconds.
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
