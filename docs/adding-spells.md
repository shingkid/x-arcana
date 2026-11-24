# Add a spell

Each spell has one definition file in `XArcana/Sources/Spells`.
`SpellCatalog.swift` declares the required fields and lists the registered spells.
`Encounter.castSpell(_:at:)` handles accepted and rejected casts for both rune and voice input.

Read [the architecture guide](architecture.md) before changing combat or controller messages.
Use an existing spell with similar behavior as the starting point.
`FireballSpell.swift` shows a combat effect.
`SparksSpell.swift` shows a separate animation callback.
`NyanSpell.swift` shows an effect whose music follows simulation time.

## Declare the required components

Every `SpellDefinition` requires these fields:

| Field | Contract |
| --- | --- |
| `id` | A unique `SpellID` case. |
| `title` | The name used in recognition feedback. |
| `rune` | An existing or new `RuneKind`, or `nil` for a spell without that identity. |
| `invocation` | A gesture guide, a voice command with phrases, both, or the unrecognized-stroke fallback. |
| `manaCost` | The cost used by combat and accepted-cast feedback. |
| `effect` | A required gameplay closure that returns `.accepted` or `.rejected`. |
| `presentation` | An explicit `.effectOwned` policy or an `.onAccepted` animation closure. |
| `sound` | At least one required sound, with either cast playback or simulation timing. |
| `feedback` | The status text shown after a successful cast. |

Give each static declaration an explicit `SpellDefinition` type.
This prevents circular type inference when a deferred closure reads a cost from the catalog.

### Commit gameplay before animation

The effect must validate the run state, target, cooldown, available assets, and mana before committing gameplay.
Return `.rejected` when the action cannot proceed.
Do not spend mana or replace an existing ally when asset creation fails.
The `manaCost` field does not spend mana automatically.
The combat operation must read that cost and spend it exactly once after validation.

Use `.effectOwned` when an existing combat or world operation already creates the spell's visuals after validation.
Use `.onAccepted` for a new scene animation that should run after the gameplay effect succeeds.
The dispatcher runs the shared wand animation for accepted casts.
It also runs the custom animation callback and plays cast audio only after `.accepted`.
A rejection can request the existing fizzle sparks without running the accepted-cast animation.

Accepted feedback appends the cost for spells that spend mana, such as `Fireball cast. · -15 MP`.
Rejected and duplicate casts show their rejection message without a spending label.
Free spells do not show a spending label.

### Select a sound policy

Use `.onCast(firstSound, layers: additionalSounds)` for ordinary spell effects.
The required first sound prevents an empty sound configuration.
Add new sound names to `SpellAudio.Sound` and supply their audio files.
For synthesized sounds, extend `XArcana/Tools/GenerateAudio.py` and regenerate the files with that generator.
Keep source attribution for imported audio.

Use `.simulationTimed(.nyan)` for the existing Nyan music policy.
The remaining simulation time starts, pauses, seeks, and stops that player.
Calling the cast audio method alone does not start another copy.
A new timed music effect also needs explicit lifecycle support in `SpellAudio`.

## Register the spell and its invocation

From the repository root:

1. Add a `SpellID` case in `Spells/SpellCatalog.swift`.
2. Create a definition file named for the spell, such as `Spells/FireballSpell.swift`.
3. Add the definition to `SpellCatalog.all`.
4. Add a `RuneKind` case in `RuneCasting.swift` if the spell needs a new rune identity.
   For a new shape, add recognition in `RuneRecognizer` with tests for confusing shapes.
5. Add a `VoiceCommand` case in `VoiceCommands.swift` if the spell needs a new controller command.
   Declare its primary phrase and aliases in the spell definition.
   Preserve all existing raw command values.
6. Add or extend the combat operation, animation, and audio assets required by the definition.
7. Regenerate the Xcode source lists with `python3 XArcana/Tools/SyncProject.py`.

Voice parsing, speech hints, voice help, rune titles, and sound selection derive from the catalog.
Changing an existing spell's voice aliases requires no parser switch.
Keep normalized aliases unique across spells and weapon commands.
The `cast` and `shoot` commands remain weapon selectors.

The accepted gesture families are loose Z or lightning zigzags, broad open O or oval shapes, uneven V shapes, stars, and W shapes.
W recognition accepts shallow or rounded valleys and uneven arms in either drawing direction.
It still requires two distinct valleys, so a V or extra waves do not become Nyan.
Fire also accepts angular loops, thin ovals, and large gaps.
The star, V, and W families remain separate.
Holding still for about one second charges Shield.
Only release casts the prepared spell.
Touch-down starts the held drawing at the current phone aim, without moving the wand to the centre.
Idle wand swings use a separate melee detector, deal 1 damage, and cannot spend mana or recognize a rune.
Nyan also accepts `Nyan`, `summon nyan`, and `nyan cat` by voice.

## Preserve survival rules

The level identifies the current stage, not XP progression.
Each stage contains eight zombies with 2 HP each, spawning eight seconds apart.
Kills award 100 score each and do not award XP or advance the level.
Clearing a stage awards 250 score and starts a twenty-second break.
When the next stage begins, maximum HP and MP each increase by 10 and both resources refill completely.
The run starts at 100 HP and 100 MP.
Mana regenerates at 4 MP per simulation second after a two-second delay from spending.
Keep internal `wave` and `bestWave` wire and storage keys for compatibility.

Zombie attacks, wand melee, arrows, and physical ally attacks each deal 1 damage.
Lightning, ice, and devil fire breath each deal 2 damage.
Fireball shares 5 total damage across a 3-metre blast, weighted toward victims near the centre.
Preserve fractional zombie HP when distributing that damage.
Shield costs 20 MP, starts with 20 shield HP, has no expiry, and has a ten-second cooldown.
Neither duplicate casting nor a stage transition refills an active shield.
The winged devil flies, and Patronus follows a curved run from the lower-right foreground.
Patronus applies a fifteen-second slow and then vanishes.

## Verify the change

Add tests that cover successful dispatch and the spell's failure conditions.
Check the actual mana change and accepted feedback.
Check that rejection and duplicates preserve mana and do not run the accepted animation.
For a new gesture, test varied sizes, offsets, drawing directions, speeds, tracking loss, and confusing shapes.
For a timed effect, test pause, resume, expiry, defeat, and restart with simulation time.

Format the changed Swift files and regenerate the project lists:

```sh
xcrun swift-format format --in-place --recursive XArcana/Sources/Spells
python3 XArcana/Tools/SyncProject.py
python3 XArcana/Tools/SyncProject.py --check
```

Run the automated checks:

```sh
Tools/build.sh test
```

When controller behavior changes, also run `Tools/build.sh ui` with `SIMULATOR_ID` set to an available iPhone simulator UUID.
Then connect the Mac host and iPhone controller and check the actual spell, feedback, sound, and mana display.
`SpellCatalogTests`, `RuneTests`, and `AudioTests` cover catalog completeness, input behavior, sound assets, and the Nyan audio lifecycle.

## Example Codex request

> Add a new spell to X Arcana using `docs/adding-spells.md`.
> Specify its invocation, gameplay effect, animation, sound, mana cost, cooldown, and feedback before implementation.
> Create one required `SpellDefinition` and register it in the catalog.
> Preserve existing wire commands and gameplay behavior.
> Validate the effect before spending mana or presenting a successful cast.
> Add tests for successful casting, invalid targets, insufficient mana, cooldowns, duplicate effects, and pause timing where applicable.
> Regenerate the project lists, format the changed files, and run the affected tests.
> Report verified results and any remaining physical-device checks.
