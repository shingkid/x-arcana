# Package the Mac game and iPhone controller

Ship two binaries from the same source revision.
The Mac package contains the game, assets, and head tracker.
The iPhone package contains the controller and shared protocol code, without the scene assets or game audio.
Do not distribute a raw iPhone `.app` as an installable download.

## Recommended route

| Audience | Mac | iPhone |
| --- | --- | --- |
| Local development | Xcode build and local head tracker | Xcode installation signed by the developer |
| Friends testing the game | Developer ID-signed, notarized download | TestFlight invitation |
| Public release | Notarized app in a signed disk image, or Mac App Store | App Store |

The Personal Team route is suitable for testing on your own devices.
Its provisioning profiles expire after seven days and require rebuilding and reinstalling.
TestFlight and Developer ID distribution require Apple Developer Program membership.
See Apple's [developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account).

## Build a local development package

```sh
Tools/build.sh mac
"XArcana/Mac Head Tracking/build.sh"
Tools/package-mac.sh
```

This creates `dist/X-Arcana-Mac-development.zip` and a SHA256 file.
The ZIP contains the app, helper, dependency licenses, and a launcher.
The helper is built for the current Mac architecture.
This is a development package, not a signed or notarized public release.
The script does not disable Gatekeeper or change system security settings.
Keep source sharing separate from binary distribution:

```sh
python3 XArcana/Tools/ExportAssetKit.py
```

The source ZIP includes project files, developer guides, reproducible exporters, public placeholders, and attribution.
It excludes signing data, build caches, and prior share archives.
Its SHA256 manifest covers every packaged file.

## Release the Mac app

1. Build the game and helper for each supported Mac architecture.
2. Stage the helper and its licenses with the game.
3. Sign the helper and app with your Developer ID Application identity and the hardened runtime.
4. Keep required local-network and device access entitlements compatible with the tested helper.
5. Submit the archive with `xcrun notarytool submit` using a configured Keychain profile.
6. Wait for acceptance and staple the ticket with `xcrun stapler staple`.
7. Verify the signed result with `codesign --verify --deep --strict` and `spctl --assess --type execute`.
8. Package the result in a disk image, notarize that distribution container, and test it on a clean Mac.

Sign nested executables before signing their enclosing app or package.
The current development ZIP uses a launcher beside the app.
It does not implement an embedded helper's automatic lifecycle.
Before claiming a one-app installation, integrate and verify that lifecycle, including shutdown and reconnect behavior.
Do not describe a local development signature as Developer ID notarization.
Apple documents the process in [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Release the iPhone controller

1. Register the app with your developer account and App Store Connect.
2. Choose a team-owned bundle identifier for a separately distributed app.
3. Select a generic iOS device destination in Xcode and archive the `XArcana` scheme.
4. Validate the archive and upload it to App Store Connect.
5. Add the beta description, test instructions, privacy details, and review contact.
6. Submit the first external testing build for beta review.
7. Invite friends through TestFlight after the build is available.

TestFlight handles installation without asking each friend for a device identifier.
See Apple's [TestFlight guide](https://developer.apple.com/testflight/).
The public source project contains no certificate, provisioning profile, or account credential.
Ad hoc distribution is an alternative for registered devices, but is less convenient for a growing tester group.

## Release checks

- Build the Mac and iPhone from the same commit.
- Run native gameplay tests and phone UI tests.
- Verify controller reconnects, head tracking, restart/setup, and saved records.
- Check the phone bundle contains no room, creature, rig, or game-audio resources.
- Test the final package on another Mac and an actual iPhone.
- Verify every bundled asset's attribution and distribution rights.
- Keep private photos and privately supplied models out of public source and binary packages.
- Record version, build number, source commit, architecture, and checksums.

The Nyan Cat recording is supplied under its creator's non-commercial derivative-game permission, not CC0.
Do not assume that permission covers a commercial release.
See [asset notes](assets.md) for the preserved terms and credits.
No App Store submission, Developer ID notarization, or TestFlight upload has been performed by these build scripts.
