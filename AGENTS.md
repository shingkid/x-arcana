# Working on X Arcana

Read `README.md` and `docs/architecture.md` before changing the game.
Follow `docs/adding-spells.md` for spells and `docs/environments.md` for environments.

- Keep the Mac authoritative for combat and resources.
- Keep the iPhone a controller without scene assets or rendering work.
- Use simulation time for damage, cooldowns, regeneration, and status effects.
- Declare invocation, gameplay effect, animation, sound, mana, and feedback for every spell.
- Add new source files through `python3 XArcana/Tools/SyncProject.py`.
- Format Swift with `xcrun swift-format format --in-place --recursive XArcana/Sources XArcana/Tests XArcana/UITests`.
- Run `Tools/build.sh test` and the affected phone UI tests before delivery.
- Keep gameplay balance and wire command values stable unless the request changes them.
- Preserve the compatibility identifiers described in `docs/architecture.md`.
- Keep original licenses and attribution beside third-party assets.
- Never add real portraits, private character models, signing profiles, credentials, or local build products to this public repository.
- Regenerate placeholder assets through their exporter instead of editing generated models or manifests by hand.
- Keep generated ZIPs in `dist/`, outside Git.
- Update the relevant developer guide with each new extension point.

Use four-space indentation and short comments that explain constraints.
Avoid redundant wrappers, speculative extension points, and silent error handling.
Tests should exercise public behavior and failure paths rather than copy the implementation.
