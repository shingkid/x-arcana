"""Pack selected CC0 source frames without resizing; macOS AppKit is the only image dependency."""
from pathlib import Path
import hashlib
import json
import re
import struct
import subprocess
import tempfile
import zipfile

BASE = Path(__file__).resolve().parent
OUTPUT = BASE.parents[1] / 'Resources/Effects'
OUTPUT.mkdir(parents=True, exist_ok=True)
ARCHIVES = {
    'nyrthos': ('FX-original.zip', '8d0c09487ab0337867e90333e9c26e455760b31414bf503bedcde94b0cddbc30'),
    'rubberduck': ('blender-volumetric-particles-effects-original.zip', '52fc2d3dca5621d1e2968365226021ded3de2ace43c7f09339405197066b0594'),
}
SELECTIONS = [
    ('lightning', 'nyrthos', 'fx1_blue_topEffect'),
    ('fire', 'rubberduck', 'effect-images/explosion/fire'),
    ('ice', 'rubberduck', 'effect-images/explosion/blueish_smoke'),
    ('shield', 'rubberduck', 'effect-images/ring/blueish_smoke'),
    ('summon', 'rubberduck', 'effect-images/ring/magic'),
]

def sha(data): return hashlib.sha256(data).hexdigest()
def power_two(n): return 1 << (n - 1).bit_length()

manifest = {'version': 1, 'effects': {}}
provenance = {'archives': {}, 'frames': {}}
with tempfile.TemporaryDirectory(prefix='xarcana-fx-') as temporary:
    temporary = Path(temporary)
    jobs = []
    for key, (filename, expected) in ARCHIVES.items():
        data = (BASE / filename).read_bytes()
        assert sha(data) == expected, filename
        provenance['archives'][filename] = expected
    for effect, archive_key, prefix in SELECTIONS:
        filename, _ = ARCHIVES[archive_key]
        with zipfile.ZipFile(BASE / filename) as source:
            names = sorted([n for n in source.namelist() if n.startswith(prefix + '/') and n.endswith('.png')],
                           key=lambda n: int(re.findall(r'\d+', Path(n).stem)[-1]))
            assert names, effect
            frames = []
            dimensions = None
            provenance['frames'][effect] = []
            for index, name in enumerate(names):
                data = source.read(name)
                assert data.startswith(b'\x89PNG\r\n\x1a\n')
                size = struct.unpack('>II', data[16:24])
                assert dimensions is None or dimensions == size
                dimensions = size
                path = temporary / f'{effect}-{index:03}.png'
                path.write_bytes(data)
                frames.append(str(path))
                provenance['frames'][effect].append({'archivePath': name, 'sha256': sha(data)})
            width, height = dimensions
            columns = min(len(frames), 1024 // (width + 4))
            rows = (len(frames) + columns - 1) // columns
            atlas_width, atlas_height = power_two(columns * (width + 4)), power_two(rows * (height + 4))
            assert max(atlas_width, atlas_height) <= 1024
            atlas = f'{effect}-atlas.png'
            jobs.append({'name': effect, 'frames': frames, 'width': width, 'height': height, 'output': str(OUTPUT / atlas)})
            manifest['effects'][effect] = {'atlas': atlas, 'frameCount': len(frames), 'frameWidth': width, 'frameHeight': height,
                'atlasWidth': atlas_width, 'atlasHeight': atlas_height, 'columns': columns, 'padding': 2}
    job_file = temporary / 'jobs.json'
    job_file.write_text(json.dumps(jobs))
    subprocess.run(['swift', '-module-cache-path', str(temporary / 'swift-cache'), str(BASE / 'pack_atlases.swift'), str(job_file)], check=True)
for effect, item in manifest['effects'].items():
    item['sha256'] = sha((OUTPUT / item['atlas']).read_bytes())
(OUTPUT / 'atlases.json').write_text(json.dumps(manifest, indent=2) + '\n')
(BASE / 'source-frame-hashes.json').write_text(json.dumps(provenance, indent=2) + '\n')
print('Total atlas PNG bytes:', sum((OUTPUT / x['atlas']).stat().st_size for x in manifest['effects'].values()))
