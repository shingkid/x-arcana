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
Optional Phone walking adds experimental translation from the iPhone camera.
It does not map furniture for game collisions or hide enemies behind real objects.

## Move around

Without Air 2 head tracking, use **WASD** to walk and the **arrow keys** to look during a run.
The game window must be active.
Movement stops during setup, countdown, disconnection, and game over.
Release held keys after switching windows or restarting, then press them again.
Restart returns the player to the starting position.

To use physical movement, enable **Phone walking: off** in the Mac toolbar.
Allow Camera access on the iPhone when requested.
Keep the rear camera uncovered and point it forward while holding the phone near your torso.
Start the run, then walk to move within the game's floor boundaries.
The mode also works on the Mac display for testing without glasses.
When Phone walking is on, it replaces WASD translation; arrow-key looking remains available without head tracking.

Drawing pauses translation, including a short delay after release so you can lower the wand again.
Tracking loss, reconnects, and sudden position jumps pause or rebase movement instead of teleporting the player.
Use **Center view** while looking and pointing forward to recalibrate.
Toggle Phone walking off and on if camera tracking fails.

This is experimental phone-position tracking, not measured head position.
Arm movements outside a held gesture can still move the player.
Use a clear, well-lit area and stay within the glasses cable's reach.
The game cannot detect real obstacles or make simultaneous walking and wand gestures reliable with one handheld tracker.
Camera images stay on the phone; only position, heading, and tracking status are sent to the Mac.

## Spells

Say **cast** to select the wand.
Hold the phone screen, move its top edge to draw, then release.
Loose shapes and uneven strokes are accepted.
A broad, open circle is enough for fire.
Wave the wand without touching the screen for a free, short-range melee strike.
Melee deals 0.5 damage and has a half-second recovery.
The wand tip shows recognition feedback before release.
Holding starts the drawing where the phone currently aims, without moving the wand to the centre.

| Input | Result | MP |
| --- | --- | ---: |
| Z or zigzag | Single-target lightning, 2 damage | 5 |
| O, oval, or open circle | Fireball, 5 total damage shared across a 3-metre blast; nearer zombies take more | 15 |
| V | Ice cone, 2 damage and a six-second slow | 15 |
| Still hold for about one second, then release | 20 shield HP, lasting until absorbed; ten-second cooldown | 20 |
| Star only | Winged devil for up to five seconds; disappears when mana runs out | 20 per second |
| Say **nyan nyan** | 27-second curse on current zombies; requires 20 defeats per use | 80 |
| **Albert** | Large ally with a body slam | 30 |
| **Alan** | Ally with a badminton racket | 25 |
| **Patronus** or **Expecto Patronum** | Curved run from the lower-right foreground, fifteen-second slow, then vanish | 30 |
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
Zombies have 2 HP and use melee attacks only.
Swipes and bites each deal 1 damage at level 1, increasing by 0.5 each level.
Wand strikes deal 0.5 damage; physical ally attacks deal 1 damage.
Each arrow deals 1 damage, so a full-health 2 HP zombie needs two arrows.
Lightning, ice, and the devil's fire breath deal 2 damage.
Fireball shares 5 damage across the blast with more damage near its centre.
Fractional zombie health is retained after a blast.
Shield HP absorbs incoming damage before player HP and does not expire with time.
Casting an active shield again costs no mana and does not refill it.
Spawns start eight seconds apart, up to eight per stage.
Each level makes the interval 10% shorter, with a two-second minimum.
Each kill earns 100 score.
Clearing a stage earns 250 score and starts a twenty-second break.
The next level begins when that break ends.
Nyan transforms only the living zombies on the field into harmless cats.
Each cat wanders independently in random directions across the view, with a pixel-art body and rainbow trail.
They disappear when the curse ends.

Mana recovers at 4 MP per simulation second after a two-second delay from spending.
A 15 MP cast reduces 100 MP to 85 immediately and takes 5.75 seconds to recover fully without another cast or stage transition.
The level counts stages, starting at level 1.
Kills do not award XP or increase the level.
When the next stage begins, maximum HP and MP each increase by 10, and both resources refill completely.
Clearing a stage does not immediately refill them.
The stage transition does not refill an active shield.
Accepted casting feedback shows the spell cost.
A disconnected controller pauses combat, regeneration, and status timers.

## Troubleshoot

- No controller connection: open both apps and check Local Network permission and the shared network.
- No head tracking: check the direct USB-C cable, helper process, and sensor status.
- Dark AR: remove the light shield and distinguish the Mac output from the optical view through the lenses.
- Unexpected mana refill: check whether a new stage has begun.
- Nyan: say **nyan nyan**; drawing W does not invoke it.
- Missing asset: check the game's error message, environment configuration, and asset manifest.

Use [architecture](docs/architecture.md), [adding spells](docs/adding-spells.md), and [environments](docs/environments.md) for development.

## Revised summon and bow balance

The demon is invoked only by drawing a star.
It needs at least 20 MP to appear, has no upfront charge, and drains 20 MP per simulation second.
Mana regeneration pauses while it is active.
It disappears after five simulation seconds or when mana runs out.
Nyan needs 20 zombie defeats before every cast, including the first, and still costs 80 MP.
One living zombie becomes one cat; queued zombies do not produce extra cats.
Spawning pauses during the 27-second curse, then resumes after the current level's spawn interval.
Only transformed zombies disappear at the song boundary.
The glasses show Nyan progress out of 20.
The bow has a 0.5-second reload and uses tighter hitboxes and less aim assistance.

Zombie health bars sit below their names and face the player.
The two sections each represent 1 HP and one bow hit.
Spell and ally damage also update the bars, including partial sections.
Bars disappear on death and during Nyan transfiguration.

## Level 10 final boss

Levels 1 to 9 contain zombie stages.
Level 10 replaces the horde with one winged demon boss with 30 HP.
Entering level 10 grants 20 maximum HP and MP instead of 10.
Both resources refill to 200 for the boss fight.
He flies slowly around the arena and signals attacks before contact.
Each claw deals 4 damage, the ground slam deals 8, and fire breath deals 6.
The boss has a continuous health bar and numeric HP above him.
Arrows always deal 1 damage, including against the boss (30 hits from full health).
Nyan cannot transform the boss.
Defeating him ends the run in victory, awards 1,250 total boss and stage score, and permanently unlocks the star summon.
Dying, reaching level 10, and drawing a star do not unlock it.
Restart and Reset scores retain this unlock.
After unlocking, the friendly demon keeps its 20 MP per second drain and five-second lifetime.
