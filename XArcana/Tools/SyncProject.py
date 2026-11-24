#!/usr/bin/env python3
"""Synchronize Swift files and Mac-only resources with the checked-in Xcode project."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

APP = Path(__file__).resolve().parents[1]
PROJECT = APP / "XArcana.xcodeproj/project.pbxproj"


def identifier(value):
    return hashlib.sha256(value.encode()).hexdigest()[:24].upper()


def serialize(value, indent=0):
    tab = "\t" * indent
    if isinstance(value, dict):
        lines = [f"{tab}\t{json.dumps(key)} = {serialize(item, indent + 1)};"
                 for key, item in sorted(value.items())]
        return "{\n" + "\n".join(lines) + "\n" + tab + "}"
    if isinstance(value, list):
        return "(\n" + "".join(f"{tab}\t{serialize(item, indent + 1)},\n" for item in value) + tab + ")"
    return json.dumps(str(value))


def synchronize():
    project = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(PROJECT)]))
    objects = project["objects"]
    removed = {key for key, value in objects.items()
               if value.get("isa") == "PBXFileReference" and
               (value.get("path", "").endswith(".swift") or value.get("path") == "../X Arcana Room.usdz")}
    removed |= {key for key, value in objects.items() if value.get("fileRef") in removed}
    for key in removed:
        del objects[key]
    for value in objects.values():
        for field in ("children", "files"):
            if field in value:
                value[field] = [key for key in value[field] if key not in removed]

    sources = {}
    for folder in ("Sources", "Tests", "UITests"):
        group = next(value for value in objects.values()
                     if value.get("isa") == "PBXGroup" and value.get("path") == folder)
        group["children"] = []
        for path in sorted((APP / folder).rglob("*.swift")):
            relative = str(path.relative_to(APP))
            key = identifier("file:" + relative)
            objects[key] = {"isa": "PBXFileReference", "lastKnownFileType": "sourcecode.swift",
                            "path": str(path.relative_to(APP / folder)), "sourceTree": "<group>"}
            sources[relative] = key
            group["children"].append(key)

    for target in list(objects.values()):
        if target.get("isa") != "PBXNativeTarget":
            continue
        name = target["name"]
        folder = {"XArcana": "Sources/", "XArcana Tests": "Tests/", "XArcana UI Tests": "UITests/"}[name]
        selected = [path for path in sources if path.startswith(folder)]
        if name == "XArcana UI Tests":
            selected += ["Sources/ControllerLink.swift", "Sources/SurvivalState.swift", "Sources/RuntimeIdentifiers.swift"]
        phase = next(objects[key] for key in target["buildPhases"] if objects[key]["isa"] == "PBXSourcesBuildPhase")
        phase["files"] = []
        for path in selected:
            key = identifier("build:" + name + ":" + path)
            objects[key] = {"isa": "PBXBuildFile", "fileRef": sources[path]}
            phase["files"].append(key)

    main = objects[objects[project["rootObject"]]["mainGroup"]]
    target = next(value for value in objects.values() if value.get("isa") == "PBXNativeTarget" and value["name"] == "XArcana")
    phase = next(objects[key] for key in target["buildPhases"] if objects[key]["isa"] == "PBXResourcesBuildPhase")
    for path in sorted((APP / "Resources").iterdir()):
        if not path.is_dir():
            continue
        relative = str(path.relative_to(APP))
        ref = next((key for key, value in objects.items() if value.get("isa") == "PBXFileReference" and value.get("path") == relative), None)
        if ref is None:
            ref = identifier("resource:" + relative)
            objects[ref] = {"isa": "PBXFileReference", "lastKnownFileType": "folder", "path": relative, "sourceTree": "<group>"}
            main["children"].append(ref)
            build = identifier("resource-build:" + relative)
            objects[build] = {"isa": "PBXBuildFile", "fileRef": ref}
            phase["files"].append(build)
    for key in phase["files"]:
        objects[key]["platformFilter"] = "maccatalyst"
    return "// !$*UTF8*$!\n// Generated file lists: run python3 XArcana/Tools/SyncProject.py.\n" + serialize(project) + "\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    result = synchronize()
    if args.check:
        if PROJECT.read_text() != result:
            raise SystemExit("Xcode file lists are stale. Run python3 XArcana/Tools/SyncProject.py.")
    else:
        PROJECT.write_text(result)
