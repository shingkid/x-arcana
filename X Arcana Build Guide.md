# Build and play X Arcana

## Connect and build

1. Open `XArcana/XArcana.xcodeproj` in Xcode.
2. Select `XArcana` and **My Mac (Mac Catalyst)**, then run.
3. Select the connected iPhone and your own signing team, then run the controller.
4. Allow Local Network, Microphone, Speech Recognition, and Motion access when requested.
5. Enable Developer Mode if Xcode requests it.
6. Keep the Mac and iPhone on the same local network.
7. Build the head tracker with `XArcana/Mac Head Tracking/build.sh`.
8. Install the Mac app in Applications and run `Start X Arcana.command`.
9. Connect the Air 2 directly to the Mac through USB-C video.
10. Keep the glasses still while the sensor filter starts.

Check for **iPhone connected** and **Head tracking on** on the Mac.
Use **Center view** while looking forward if the view drifts.
Do not use iPhone screen mirroring for this route.

The project has no personal signing team.
Its app identifier remains stable for existing installations and records.
For a separately owned distribution, use an identifier registered to your developer account.
See [distribution](docs/distribution.md) for signing and packaging.

## Start and restart

Point the phone at a world option in the glasses.
Tap to select and preview it, then double-tap to confirm.
Repeat for Wand or Bow.
The game starts after the three-second countdown.
Restart returns to these options at level 1 and keeps saved best records.
Reset scores returns to setup and clears current and saved scores only after confirmation.
Both actions cancel held gestures before resetting the run.

## Optical AR

Fantasy mode draws the magical room.
See-through AR renders transparency around zombies, spells, and the HUD.
The Mac presents transparent pixels over black because black emits no image light through the Air 2.
You see the physical room directly through the lenses.
This is not a camera feed.
Remove the clip-on light shield and use a well-lit room.
If the lenses remain dark when unplugged, the game cannot change that physical darkness.
The first zombie appears after the countdown.

This setup tracks head rotation only.
It does not map furniture, track physical movement, or hide enemies behind real objects.

## Spells

Say **cast** to select the wand.
Hold the phone screen, move its top edge to draw, then release.
Loose shapes and uneven strokes are accepted.
The wand tip shows recognition feedback before release.

| Input | Result | MP |
| --- | --- | ---: |
| Z or zigzag | Single-target lightning, 1 damage | 5 |
| O, oval, or open circle | Fireball, 1 area damage | 15 |
| V | Ice cone, 1 damage and a six-second slow | 15 |
| Still hold for about one second, then release | Five-second shield, ten-second cooldown | 20 |
| Star or **Demon** | Demon ally | 40 |
| W or **Nyan** | 27-second rainbow curse that clears the current wave | 80 |
| **Albert** | Large ally with a body slam | 30 |
| **Alan** | Ally with a badminton racket | 25 |
| **Patronus** or **Expecto Patronum** | Running charge with a fifteen-second slow | 30 |
| **Lumos** | Room lighting | 0 |
| **Revelio** | Hidden writing | 0 |

Say **shoot** to select the bow, then tap to fire a free arrow.
Weapon commands change mode without attacking.
Alan and Albert can fight together.
The demon and Patronus each require the other physical allies to leave.
Active duplicate summons cost no mana.
The Nyan curse can coexist with physical allies.

## Survival

Start with 100 HP and 100 MP.
Zombies have 3 HP and use melee attacks only: swipes deal 1 damage and bites deal 3.
One zombie arrives every eight seconds, up to eight per wave.
The next wave begins twenty seconds after the previous one is cleared.
Nyan immediately transforms the current wave's remaining slots into harmless cats.
Each cat wanders independently in random directions across the view, with a pixel-art body and rainbow trail.
They disappear when the curse ends.

Mana recovers at 8 MP per simulation second after a one-second delay from spending.
A level-up adds 10 maximum HP and MP, restores 20 HP, and fully refills mana.
This refill can make mana rise sharply after a kill.
Accepted casting feedback shows the spell cost.
A disconnected controller pauses combat, regeneration, and status timers.

## Troubleshoot

- No controller connection: open both apps and check Local Network permission and the shared network.
- No head tracking: check the direct USB-C cable, helper process, and sensor status.
- Dark AR: remove the light shield and distinguish the Mac output from the optical view through the lenses.
- Unexpected mana refill: check for a level-up announcement.
- Difficult W: use two loose downward valleys or say **Nyan**.
- Missing asset: check the game's error message, environment configuration, and asset manifest.

Use [architecture](docs/architecture.md), [adding spells](docs/adding-spells.md), and [environments](docs/environments.md) for development.
