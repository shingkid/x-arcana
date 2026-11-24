#!/bin/bash
# Produce a local development bundle. This does not sign or notarize a release.
set -euo pipefail
cd "$(dirname "$0")/.."
app="${1:-build/mac/Build/Products/Release-maccatalyst/X Arcana.app}"
helper='XArcana/Mac Head Tracking/bin/XArcanaHeadBridge'
[[ -d "$app" && -x "$helper" ]] || {
  printf 'Build the Mac app and head tracker before packaging. See docs/distribution.md.\n' >&2
  exit 1
}
mkdir -p dist
stage="$(mktemp -d "$PWD/dist/xarcana-stage.XXXXXX")"
package="$stage/X Arcana Development"
mkdir -p "$package/Head Tracking"
ditto "$app" "$package/X Arcana.app"
cp "$helper" "$package/Head Tracking/XArcanaHeadBridge"
ditto 'XArcana/Mac Head Tracking/Licenses' "$package/Head Tracking/Licenses"
mkdir -p "$package/Documentation" "$package/Credits/Nyan Music"
cp docs/*.md "$package/Documentation/"
sed 's#](docs/#](Documentation/#g' 'X Arcana Build Guide.md' > "$package/Play Guide.md"
cp 'XArcana/Fantasy Sources/Nyan Music/README.md' 'XArcana/Fantasy Sources/Nyan Music/source.json' \
  'XArcana/Fantasy Sources/Nyan Music/permission-2026-11-25.html' "$package/Credits/Nyan Music/"
cat > "$package/READ-ME.md" <<'README'
# X Arcana development build

Open `Start X Arcana.command` to start the game and head tracker.
Connect the Air 2 directly to the Mac and open the X Arcana controller on your iPhone.
Both devices must use the same local network.
This package requires a separately installed iPhone controller.
Read `Play Guide.md` for the controls.
Read `Documentation/distribution.md` for iPhone installation and public release steps.

This development build is not notarized for public distribution.
The public edition uses generated portrait and companion placeholders.
Asset licenses remain inside the app's Resources folders.
Developer documentation links to source files refer to the separately shared source package.

Nyan Cat character design: **Chris Torres**.
Nyan Cat music: **Nyan Cat** by **daniwell**, vocal **Momone Momo**.
The recording is included for non-commercial derivative-game use with credit.
Its preserved permission record is in `Credits/Nyan Music`.
Read `Documentation/assets.md` before redistributing media.
README
cat > "$package/Start X Arcana.command" <<'LAUNCH'
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
nohup './Head Tracking/XArcanaHeadBridge' >> "${TMPDIR:-/tmp/}xarcana-head-tracker.log" 2>&1 < /dev/null &
open './X Arcana.app'
LAUNCH
chmod +x "$package/Start X Arcana.command"
ditto -c -k --keepParent "$package" dist/X-Arcana-Mac-development.zip
shasum -a 256 dist/X-Arcana-Mac-development.zip > dist/X-Arcana-Mac-development.zip.sha256
printf 'Created dist/X-Arcana-Mac-development.zip. This is not a notarized public release.\n'
printf 'Staging copy retained at %s\n' "$stage"
