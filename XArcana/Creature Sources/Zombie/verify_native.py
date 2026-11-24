"""Compile the actual appearance source for a native macOS SceneKit asset review."""
import pathlib
import plistlib
import subprocess
import tempfile
import argparse

parser = argparse.ArgumentParser()
parser.add_argument("--portraits", type=pathlib.Path)
parser.add_argument("--output", type=pathlib.Path)
args = parser.parse_args()

source = pathlib.Path(__file__).resolve().parent
root = source.parents[1]
output = args.output or pathlib.Path(tempfile.gettempdir()) / "xarcana-zombie-previews"
output.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix="xarcana-zombie-review-") as directory:
    temporary = pathlib.Path(directory)
    bundle = temporary / "Review.bundle"
    resources = bundle / "Contents" / "Resources"
    resources.mkdir(parents=True)
    (bundle / "Contents" / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "local.xarcana.zombie-review", "CFBundleName": "ZombieReview",
        "CFBundlePackageType": "BNDL", "CFBundleVersion": "1"}))
    for folder in ["Creatures", "NPCFaces", "NPCPortraits"]:
        folder_source = args.portraits / folder if args.portraits and folder != "Creatures" else root / "Resources" / folder
        (resources / folder).symlink_to(folder_source, target_is_directory=True)
    appearance = (root / "Sources" / "ZombieAppearance.swift").read_text()
    appearance = appearance.replace("import UIKit", "import AppKit").replace("Bundle.main", "assetBundle")
    (temporary / "ZombieAppearance.swift").write_text(appearance)
    (temporary / "ScenePerformance.swift").write_text((root / "Sources" / "ScenePerformance.swift").read_text())
    (temporary / "CharacterAnimation.swift").write_text((root / "Sources" / "CharacterAnimation.swift").read_text().replace("Bundle.main", "assetBundle"))
    binary = temporary / "review"
    cache = pathlib.Path(tempfile.gettempdir()) / "xarcana-zombie-swift-modules"
    subprocess.run(["xcrun", "swiftc", "-module-cache-path", str(cache),
        "-parse-as-library", "-o", str(binary),
        str(temporary / "ZombieAppearance.swift"), str(temporary / "ScenePerformance.swift"),
        str(temporary / "CharacterAnimation.swift"),
        str(source / "NativeReview.swift")], check=True)
    subprocess.run([str(binary), str(bundle), str(output)], check=True)
