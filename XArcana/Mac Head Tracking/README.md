# Air 2 head tracking for X Arcana

This Mac utility reads the Air 2's real motion sensors and sends orientation to the Mac game through a local connection.
It uses the community [xrealair-sdk-macos](https://github.com/adidoes/xrealair-sdk-macos), [hidapi](https://github.com/libusb/hidapi), [Fusion](https://github.com/xioTechnologies/Fusion), and [json-c](https://github.com/json-c/json-c).
It provides three degrees of freedom: head rotation, without position tracking.

## Start head tracking

1. Connect the Air 2 directly to the Mac with USB-C.
2. Double-click **Start Head Tracking.command** in this folder.
3. Keep the glasses still for five seconds while the sensor filter starts.
4. Open the Mac version of X Arcana, then open the iPhone controller.
   Keep the Mac and iPhone on the same local network.
5. Keep the terminal window open while playing.

The built executable is `bin/XArcanaHeadBridge`.
It uses macOS frameworks and statically linked dependencies, so it does not depend on temporary build folders.
Only one instance can run from this folder.
Close the terminal window to stop it.
The game captures your forward heading when tracking connects.
The helper reports gravity-referenced pitch and roll.
The Mac game keeps the horizon level while you look around.
The tracker waits when the glasses are absent and reconnects after you plug them in.
The Mac game receives head tracking locally.
The iPhone sends controller input only and does not render the game.
The game status distinguishes a tracker connection from live Air 2 motion data.

The bridge does not capture a camera or screen.
It does not change the glasses' display mode, firmware, or stored calibration.
The SDK briefly stops sensor streaming, reads factory calibration, and starts sensor streaming.
The game uses the Air 2 as a directly connected Mac display.
AirPlay is not required.

## Build

The build needs Xcode command-line tools, Python 3, and an internet connection for the first dependency download.
From this folder, run `./build.sh`.
The script downloads pinned source archives, checks their SHA-256 hashes, and builds only the sensor components.
If CMake is unavailable, the script installs it inside `.build/tools` without changing system software.
The script does not install anything with administrator privileges.

Run `./bin/XArcanaHeadBridge --probe` for an eight-second local sensor check without a network listener.
The last three seconds print real relative orientation samples after filter warmup.

## Transport

The Mac advertises Bonjour service `_ember-head._tcp` with the name `X Arcana Head Tracking`.
It accepts TCP connections and sends one JSON object per line at approximately 90 Hz.
Each orientation object contains `yaw`, `pitch`, and `roll` in radians.
It also includes `heading`, `gravityPitch`, and `gravityRoll` from the sensor's gravity-referenced orientation.
The game uses these fields to center heading while retaining the gravity reference.
The Mac view removes roll to keep the horizon level.
The original fields remain available for older clients.
Once per second, the bridge also sends a status object with `state` set to `waitingForGlasses`, `calibrating`, or `streaming`.
Status objects keep the Mac connection available while the glasses are unplugged.
Only valid orientation objects activate head tracking in the Mac game.
Yaw is positive looking left, pitch is positive looking up, and roll is positive with the left ear down.
The reference orientation is captured after the five-second startup period.
The Mac game captures its heading reference when it connects.
The listener sends orientation only and does not accept commands from clients.
It uses the local network without encryption or authentication.

If no fresh sensor samples arrive for two seconds, the bridge closes the sensor session and retries.
It also retries after device errors and reports the missing sensor to the Mac game.
The five-second calibration period runs again after reconnection.

## Dependencies and limitations

This is a community driver, without official XREAL support.
The official [XREAL PC SDK beta](https://github.com/dengxian-xreal/xreal.github.io/blob/main/docs/14_PC%20SDK%20%28Beta%29.md) uses Unity.
Its documented PC workflow does not provide a direct native SceneKit integration.
The [ar-drivers-rs](https://github.com/badicsalex/ar-drivers-rs) project also supports Air 2, but requires a Rust toolchain.
The C SDK was selected because it integrates with the installed native Mac toolchain and existing sensor-fusion code.

The source revisions and archive hashes are recorded in `build.sh`.
The included license texts cover the four linked dependencies.
Keep the `Licenses` folder when sharing the executable.

The tracked `sdk.patch` fixes observed SDK startup issues:

- Match command responses by message ID, with a bounded read timeout, when pending reports arrive during reconnection.
- Identify stream acknowledgements by their command byte instead of a checksum byte.
- Bound the first sample interval so device uptime cannot destabilize the initial orientation estimate.
- Return the declared result from the in-memory calibration initializer.

Yaw uses the gyroscope without a magnetic heading reference and can drift over time.
Reopening the app captures a new heading reference.
X Arcana renders on the Mac and sends video directly to the Air 2 over USB-C.
Physical movement is needed to verify the direction of each axis and the complete display path.

## Verification

On November 24, 2026, macOS detected the connected Air 2 with vendor ID `0x3318` and product ID `0x0428`.
A live probe received 7,900 real sensor samples in eight seconds after the SDK fixes.
The initial large roll drift was absent in the corrected probe.
This verifies sensor access and orientation output, but does not by itself verify the user's physical left, up, and roll directions.
