#!/usr/bin/env python3
"""Generate public placeholders without reading photographs or prototype models.

Run with Python 3 on macOS. Use --portraits-only to skip Blender.
Blender 5.2 and macOS sips are the only external tools used.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import struct
import subprocess
import tempfile
import zlib

APP = Path(__file__).resolve().parents[1]
PORTRAITS = APP / 'Resources/NPCPortraits'
FACES = APP / 'Resources/NPCFaces'


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def png(identifier):
    """Return a deterministic flat robot portrait, not a likeness."""
    seed = hashlib.sha256(identifier.encode()).digest()
    background = tuple(24 + v % 42 for v in seed[:3])
    shell = tuple(100 + v % 110 for v in seed[3:6])
    ink = (20, 27, 40)
    rows = bytearray()
    for y in range(256):
        rows.append(0)
        for x in range(256):
            color = background
            if ((x - 128) / 86) ** 2 + ((y - 128) / 100) ** 2 < 1:
                color = shell
            if 70 <= x <= 186 and 85 <= y <= 122:
                color = ink
            if (82 <= x <= 108 or 148 <= x <= 174) and 96 <= y <= 109:
                color = (225, 250, 255)
            if 94 <= x <= 162 and 164 <= y <= 176:
                color = ink
            if 122 <= x <= 134 and 131 <= y <= 148:
                color = ink
            rows.extend(color)
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 256, 256, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(bytes(rows), 9)) + chunk(b'IEND', b'')


def generate_portraits():
    roster = json.loads((PORTRAITS / 'roster.json').read_text())
    regions = []
    for row in roster:
        target = PORTRAITS / row['image']
        data = png(row['id'])
        if target.suffix.lower() == '.jpg':
            with tempfile.TemporaryDirectory(prefix='x-arcana-public-') as directory:
                source = Path(directory) / 'portrait.png'
                source.write_bytes(data)
                subprocess.run(['/usr/bin/sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', '90', str(source), '--out', str(target)], check=True, stdout=subprocess.DEVNULL)
        else:
            target.write_bytes(data)
        rect = dict(x=42 / 256, y=28 / 256, width=172 / 256, height=200 / 256)
        regions.append(dict(**row, sourceWidth=256, sourceHeight=256,
                            coordinateOrigin='bottom-left', imageSubdirectory='NPCPortraits',
                            provenance='procedural-public-placeholder-v1', faceDetected=False,
                            faceRect=rect, rawFaceRect=rect, textureRect=rect,
                            leftEye=dict(x=95 / 256, y=153 / 256),
                            rightEye=dict(x=161 / 256, y=153 / 256),
                            nose=dict(x=.5, y=116 / 256), mouth=dict(x=.5, y=86 / 256)))
    write_json(FACES / 'regions.json', regions)
    for name, identifier in [('alan.jpg', 'alan'), ('albert.png', 'albert')]:
        (APP / 'Resources/Fantasy' / name).write_bytes((PORTRAITS / next(r['image'] for r in roster if r['id'] == identifier)).read_bytes())
    # These are fictional display choices, not retained personal metadata.
    write_json(PORTRAITS / 'body-styles.json', dict(schemaVersion=1, assignments={r['id']: 'neutral' for r in roster}))


def update_manifests():
    paths = []
    for folder in [PORTRAITS, FACES, APP / 'Resources/Fantasy']:
        paths.extend(p for p in folder.iterdir() if p.is_file() and p.suffix in {'.png', '.jpg', '.json', '.usdz'} and p.name != 'PublicAssets.json' and p.name != 'FantasyRoom.usdz')
    generated = {str(p.relative_to(APP)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}
    manifest = dict(schemaVersion=1, generator='Tools/PreparePublicAssets.py', license='CC0-1.0', provenance='Original procedural robot icons and geometric bodies; no photographs or imported prototype geometry.', generated=generated,
                    retainedThirdParty=[
                        dict(paths=['Resources/Fantasy/FantasyRoom.usdz', 'Fantasy Sources/FantasyRoom.blend', 'Fantasy Sources/Kenney-Room-Large.glb', 'Fantasy Sources/Textures'], license='CC0-1.0', attribution='Fantasy Sources/Attribution.md'),
                        dict(paths=['Resources/Creatures/Skeleton.usdz', 'Creature Sources/Skeleton'], license='CC0-1.0', attribution='Creature Sources/Skeleton/README.md'),
                        dict(paths=['Resources/Creatures/Zombie.usdz', 'Resources/Creatures/ZombieMale.usdz', 'Resources/Creatures/ZombieFemale.usdz', 'Creature Sources/Zombie'], license='CC0-1.0', attribution='Creature Sources/Zombie/README.md'),
                        dict(paths=['Resources/Creatures/Demon.usdz', 'Creature Sources/Summons/Demon.blend'], license='CC-BY-3.0', attribution='Resources/Creatures/Summons-LICENSES.txt'),
                        dict(paths=['Resources/Creatures/Stag.usdz', 'Creature Sources/Summons/Stag.blend'], license='CC0-1.0', attribution='Resources/Creatures/Summons-LICENSES.txt')])
    write_json(APP / 'Resources/PublicAssets.json', manifest)
    for folder in ['NPC Portraits', 'NPC Faces']:
        write_json(APP / 'Creature Sources' / folder / 'manifest.json', dict(schemaVersion=1, generator='Tools/PreparePublicAssets.py', license='CC0-1.0', count=42, runtimeManifest='Resources/PublicAssets.json', provenance=manifest['provenance']))
    hashfile = APP / 'Fantasy Sources/sha256.json'
    previous = json.loads(hashfile.read_text())
    current = {}
    for relative in previous:
        path = APP / relative
        if path.is_file():
            current[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
    write_json(hashfile, current)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--portraits-only', action='store_true')
    parser.add_argument('--blender', default='/Applications/Blender.app/Contents/MacOS/Blender')
    arguments = parser.parse_args()
    generate_portraits()
    if not arguments.portraits_only:
        environment = dict(os.environ, PYTHONHASHSEED='0')
        subprocess.run([arguments.blender, '--background', '--factory-startup', '--disable-autoexec', '--python', str(APP / 'Fantasy Sources/build_portrait_character.py')], check=True, env=environment)
    update_manifests()
    print('Generated public placeholders and Resources/PublicAssets.json')


if __name__ == '__main__':
    main()
