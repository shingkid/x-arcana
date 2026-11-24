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
Draw Z for lightning, O for fire, V for ice, a star for the demon, or W for Nyan Cat.
Hold still for the shield and release after the readiness vibration.
Say **Nyan** if drawing W is inconvenient.
Say **cast** or **shoot** to switch weapons.
Tap to fire the bow.
Say **Albert**, **Alan**, **Demon**, **Patronus**, **Lumos**, or **Revelio** for the other spells.

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
It provides head rotation, not room mapping, positional tracking, or real-world occlusion.

```sh
python3 XArcana/Tools/SyncProject.py --check
Tools/build.sh test
Tools/build.sh mac
Tools/build.sh iphone
```

The phone bundle excludes the Mac's scene assets and game audio.
Use `SIMULATOR_ID=<uuid> Tools/build.sh ui` for controller interface tests.
