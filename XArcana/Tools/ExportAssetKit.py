#!/usr/bin/env python3
"""Create a fresh public source ZIP with hashes, without importing previous archives."""
import hashlib
import json
from pathlib import Path
import re
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / 'XArcana'
OUTPUT = ROOT / 'dist/X-Arcana-source.zip'
PREFIX = 'X-Arcana-Source/'
EXCLUDED = {'.git', '.build', '.DS_Store', '__pycache__', 'bin', 'build', 'dist',
            'DerivedData', 'xcuserdata', 'Verification', 'Previews'}


def verify_placeholders():
    manifest = json.loads((APP / 'Resources/PublicAssets.json').read_text())
    for name, expected in manifest['generated'].items():
        path = APP / name
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError(f'Public placeholder hash mismatch: {name}')


def source_files():
    for name in ['README.md', 'CONTRIBUTING.md', 'AGENTS.md', '.gitignore', '.swift-format',
                 'Start X Arcana.command', 'X Arcana Build Guide.md']:
        yield ROOT / name
    for directory in ['XArcana', 'Tools', 'docs', '.github']:
        for path in sorted((ROOT / directory).rglob('*')):
            if not path.is_file() or path.is_symlink():
                continue
            relative = path.relative_to(ROOT)
            if EXCLUDED.intersection(relative.parts) or path.suffix in {'.pyc', '.blend1', '.blend2', '.lock'}:
                continue
            if path.suffix in {'.mobileprovision', '.p12', '.p8', '.ipa', '.dmg'}:
                raise ValueError(f'Local signing or build artifact in source tree: {relative}')
            yield path


def main():
    verify_placeholders()
    payload = {}
    modes = {}
    for path in source_files():
        name = str(path.relative_to(ROOT))
        data = path.read_bytes()
        if path.name == 'project.pbxproj':
            data = re.sub(rb'("?DEVELOPMENT_TEAM"?\s*=\s*)[^;]*;', rb'\g<1>"";', data)
        payload[name] = data
        modes[name] = 0o100755 if path.suffix in {'.sh', '.command'} else 0o100644
    manifest = {name: hashlib.sha256(data).hexdigest() for name, data in sorted(payload.items())}
    payload['SHA256.json'] = (json.dumps(manifest, indent=2) + '\n').encode()
    OUTPUT.parent.mkdir(exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix='xarcana-source-', suffix='.zip', dir=OUTPUT.parent, delete=False) as handle:
        temporary = Path(handle.name)
    with zipfile.ZipFile(temporary, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for name, data in sorted(payload.items()):
            entry = zipfile.ZipInfo(PREFIX + name)
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = modes.get(name, 0o100644) << 16
            archive.writestr(entry, data)
    with zipfile.ZipFile(temporary) as archive:
        assert archive.testzip() is None
        for name, digest in manifest.items():
            assert hashlib.sha256(archive.read(PREFIX + name)).hexdigest() == digest, name
    temporary.replace(OUTPUT)
    digest = hashlib.sha256(OUTPUT.read_bytes()).hexdigest()
    OUTPUT.with_suffix('.zip.sha256').write_text(f'{digest}  {OUTPUT.name}\n')
    print(json.dumps(dict(archive=str(OUTPUT), files=len(payload), bytes=OUTPUT.stat().st_size, sha256=digest)))


if __name__ == '__main__':
    main()
