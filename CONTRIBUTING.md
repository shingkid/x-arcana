# Contributing

Use Xcode with the iOS and Mac Catalyst SDKs.
The command-line tools use Python 3 and the formatter bundled with Xcode.
Open `XArcana/XArcana.xcodeproj`.
The scheme and Swift module are `XArcana`.

## Make a change

1. Create a short-lived branch from `main`.
2. Read the guide for the module you will change.
3. Add a regression test for the requested behavior or failure.
4. Implement the change without changing unrelated gameplay rules.
5. Run the project synchronizer and formatter.
6. Run the affected native and phone tests.
7. Build both app variants before submitting a change to shared code.

```sh
python3 XArcana/Tools/SyncProject.py
xcrun swift-format format --in-place --recursive XArcana/Sources XArcana/Tests XArcana/UITests
Tools/build.sh test
Tools/build.sh mac
Tools/build.sh iphone
```

Set `DEVELOPER_DIR` if Xcode is installed in another location.
Build products stay in the ignored `build/` directory.
Do not commit provisioning profiles, certificates, test-result bundles, derived data, or generated ZIPs.

## Phone tests

List available simulators with `xcrun simctl list devices available`.
Use an iPhone simulator UUID:

```sh
SIMULATOR_ID=<uuid> Tools/build.sh ui
```

These tests exercise the phone interface and production transport against a test host.
They do not erase a player's saved records.

## Performance

Run `Tools/build.sh performance` alone with its test window visible.
The benchmark uses 1080p rendering, a warmup period, and timed samples with eight enemies and overlapping spell effects.
Inspect measured scenarios and skips before describing performance as verified.
To rerun only a changed workload, set `XARCANA_BENCHMARK_SCENARIO` to `alan-albert`, `demon-breath`, `transfiguration`, or `mixed-stage`.
The mixed-stage scenario measures the actual three-king and eight-zombie simulation with overlapping player effects.
The old-asset comparison is optional and needs a separate baseline app bundle.
It does not compare the complete previous runtime.
Investigate sustained frame rates below 55 FPS in the 60-FPS mode.

## Assets and review

Use the exporters to update generated assets and manifests together.
Keep third-party licenses and attribution with every copy.
Read [asset policy](docs/assets.md) before adding a model, image, or sound.

Prefer small interfaces with clear ownership and explicit failure behavior.
Remove unreachable code only after checking its callers and tests.
Keep wire values and persistent identifiers stable.
Avoid silent fallbacks that make a missing asset look like a successful cast.
Explain any check that could not be completed.
