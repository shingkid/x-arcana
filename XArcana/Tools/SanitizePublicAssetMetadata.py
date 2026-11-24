#!/usr/bin/env python3
"""Remove local author paths from selected public Blender sources and PNG metadata.

This tool changes only files inside this checkout's XArcana directory.
Blender verifies geometry, rigs, animation, materials, text, and packed image bytes
before a sanitized source replaces its input.
PNG image and color chunks remain byte-identical.
"""
from pathlib import Path
import argparse
import hashlib
import json
import struct
import subprocess
import sys
import tempfile
import zlib

APP = Path(__file__).resolve().parents[1]
DEFAULTS = [
    'Creature Sources/Skeleton/Skeleton.blend',
    'Creature Sources/Skeleton/skeleton-studio-preview.png',
    'Creature Sources/Summons/Demon.blend',
    'Creature Sources/Summons/Stag.blend',
    'Creature Sources/Summons/Demon-preview.png',
    'Creature Sources/Summons/Stag-preview.png',
    'Creature Sources/Zombie/zombie-studio-preview.png',
    'Fantasy Sources/FantasyRoom.blend',
    'Fantasy Sources/FantasyRoom-preview.png',
]
REMOVED_PNG_CHUNKS = {b'tEXt', b'zTXt', b'iTXt', b'eXIf', b'tIME'}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def png_chunks(data):
    assert data[:8] == b'\x89PNG\r\n\x1a\n', 'Invalid PNG header'
    chunks = []
    offset = 8
    while offset < len(data):
        length = struct.unpack_from('>I', data, offset)[0]
        kind = data[offset + 4:offset + 8]
        chunk = data[offset:offset + length + 12]
        assert len(chunk) == length + 12, 'Incomplete PNG chunk'
        assert zlib.crc32(chunk[4:-4]) == struct.unpack('>I', chunk[-4:])[0], 'Invalid PNG CRC'
        chunks.append((kind, chunk))
        offset += length + 12
    assert chunks[-1][0] == b'IEND', 'Missing PNG end chunk'
    return chunks


def sanitize_png(path):
    before = path.read_bytes()
    chunks = png_chunks(before)
    image_chunks = [(kind, chunk) for kind, chunk in chunks if kind not in REMOVED_PNG_CHUNKS]
    after = before[:8] + b''.join(chunk for _, chunk in image_chunks)
    assert png_chunks(after) == image_chunks
    scanlines = zlib.decompress(b''.join(chunk[8:-4] for kind, chunk in image_chunks if kind == b'IDAT'))
    assert b'/Users/' not in after, 'An author path remains outside PNG text metadata'
    path.write_bytes(after)
    return dict(file=str(path.relative_to(APP)), format='PNG', removedChunks=[kind.decode() for kind, _ in chunks if kind in REMOVED_PNG_CHUNKS], imageAndColorChunksPreserved=True, scanlineSHA256=sha(scanlines), beforeSHA256=sha(before), afterSHA256=sha(after))


def blend_snapshot():
    import bpy
    from array import array
    digest = hashlib.sha256()

    def record(value):
        digest.update(json.dumps(value, sort_keys=True, separators=(',', ':')).encode())

    def values(collection, attribute, count, code='f'):
        data = array(code, [0]) * count
        collection.foreach_get(attribute, data)
        digest.update(data.tobytes())

    counts = dict(meshes=len(bpy.data.meshes), objects=len(bpy.data.objects), materials=len(bpy.data.materials), armatures=len(bpy.data.armatures), actions=len(bpy.data.actions))
    for mesh in sorted(bpy.data.meshes, key=lambda item: item.name):
        record([mesh.name, len(mesh.vertices), len(mesh.polygons), len(mesh.loops)])
        values(mesh.vertices, 'co', len(mesh.vertices) * 3)
        values(mesh.edges, 'vertices', len(mesh.edges) * 2, 'i')
        values(mesh.loops, 'vertex_index', len(mesh.loops), 'i')
        values(mesh.polygons, 'material_index', len(mesh.polygons), 'i')
        for layer in mesh.uv_layers:
            record(layer.name)
            values(layer.data, 'uv', len(layer.data) * 2)
        if mesh.shape_keys:
            for key in mesh.shape_keys.key_blocks:
                record(key.name)
                values(key.data, 'co', len(key.data) * 3)
    for obj in sorted(bpy.data.objects, key=lambda item: item.name):
        record([obj.name, obj.type, obj.parent.name if obj.parent else None, list(tuple(row) for row in obj.matrix_world), [m.name if m else None for m in obj.data.materials] if obj.type == 'MESH' else None])
        if obj.type == 'MESH':
            record([[[(g.group, g.weight) for g in vertex.groups] for vertex in obj.data.vertices], [g.name for g in obj.vertex_groups]])
    for armature in sorted(bpy.data.armatures, key=lambda item: item.name):
        record([armature.name, [[bone.name, bone.parent.name if bone.parent else None, [tuple(row) for row in bone.matrix_local]] for bone in armature.bones]])
    for action in sorted(bpy.data.actions, key=lambda item: item.name):
        record([action.name, list(action.frame_range)])
        for layer in action.layers:
            for strip in layer.strips:
                for channelbag in strip.channelbags:
                    for curve in channelbag.fcurves:
                        record([curve.data_path, curve.array_index, [[*key.co, *key.handle_left, *key.handle_right, key.interpolation] for key in curve.keyframe_points]])
    for material in sorted(bpy.data.materials, key=lambda item: item.name):
        record([material.name, list(material.diffuse_color), material.use_nodes])
        if material.node_tree:
            record([[node.name, node.type, [(socket.name, list(socket.default_value) if hasattr(socket.default_value, '__len__') and not isinstance(socket.default_value, str) else socket.default_value) for socket in node.inputs if hasattr(socket, 'default_value') and isinstance(socket.default_value, (int, float, str, bool)) or hasattr(socket, 'default_value') and type(socket.default_value).__name__ in ('bpy_prop_array', 'Color', 'Vector')]] for node in material.node_tree.nodes])
            record([[link.from_node.name, link.from_socket.identifier, link.to_node.name, link.to_socket.identifier] for link in material.node_tree.links])
    images = {}
    for image in bpy.data.images:
        if image.packed_files:
            images[image.name] = [sha(bytes(item.packed_file.data)) for item in image.packed_files]
    record(images)
    record({text.name: text.as_string() for text in bpy.data.texts})
    return dict(contentSHA256=digest.hexdigest(), counts=counts, packedImageSHA256=images)


def sanitize_blend(source, temporary):
    import bpy
    bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False)
    assert not bpy.data.libraries, 'Linked libraries need a separate path-preservation review'
    before = blend_snapshot()
    # Preserve orphan authoring data instead of letting Blender drop it on save.
    for collection in [bpy.data.images, bpy.data.texts, bpy.data.materials, bpy.data.meshes, bpy.data.armatures, bpy.data.actions]:
        for item in collection:
            item.use_fake_user = True
    for image in bpy.data.images:
        if not image.filepath or not Path(image.filepath).is_absolute():
            continue
        assert image.packed_file, 'An external image must be packed before path cleanup'
        basename = Path(image.filepath).name
        candidates = [source.parent / folder / basename for folder in ['textures', 'Textures', 'downloads', '']]
        matching = next((path for path in candidates if path.is_file()), None)
        image.filepath = '//' + str(matching.relative_to(source.parent)) if matching else '//packed/' + basename
    for image in bpy.data.images:
        for packed in image.packed_files:
            if Path(packed.filepath).is_absolute():
                packed.filepath = image.filepath or '//packed/' + Path(packed.filepath).name
    for scene in bpy.data.scenes:
        scene.render.filepath = '//renders/'
    for text in bpy.data.texts:
        if text.filepath:
            text.filepath = '//' + Path(text.filepath).name
    for screen in bpy.data.screens:
        for area in screen.areas:
            for space in area.spaces:
                params = getattr(space, 'params', None)
                if params is not None and hasattr(params, 'directory'):
                    params.directory = b'//'
    # Saving outside the author directory also removes the FileGlobal author path.
    # Do not remap the already valid relative texture references to the temp folder.
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(temporary), check_existing=False, compress=False, relative_remap=False)
    data = temporary.read_bytes()
    assert b'/Users/' not in data, 'A local author path remains in Blender source data'
    bpy.ops.wm.open_mainfile(filepath=str(temporary), use_scripts=False)
    after = blend_snapshot()
    if before != after:
        Path('/tmp/x-arcana-metadata-mismatch.json').write_text(json.dumps(dict(before=before, after=after), indent=2))
        raise AssertionError('The sanitized file changed content; see /tmp/x-arcana-metadata-mismatch.json')
    original = source.read_bytes()
    source.write_bytes(data)
    return dict(file=str(source.relative_to(APP)), format='BLEND', beforeSHA256=sha(original), afterSHA256=sha(data), contentPreserved=True, **after)


def worker():
    arguments = sys.argv[sys.argv.index('--blender-worker') + 1:]
    config = json.loads(Path(arguments[0]).read_text())
    report = []
    for item in config['files']:
        source = APP / item
        report.append(sanitize_blend(source, Path(config['temporary']) / source.name))
    Path(config['report']).write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('paths', nargs='*', help='Paths relative to XArcana; defaults to the reviewed public assets')
    parser.add_argument('--blender', default='/Applications/Blender.app/Contents/MacOS/Blender')
    parser.add_argument('--report', default='/tmp/x-arcana-public-metadata-report.json')
    args = parser.parse_args()
    files = args.paths or DEFAULTS
    for item in files:
        path = (APP / item).resolve()
        assert APP in path.parents and path.suffix in {'.blend', '.png'} and path.is_file(), item
    blends = [item for item in files if Path(item).suffix == '.blend']
    report = []
    if blends:
        with tempfile.TemporaryDirectory(prefix='x-arcana-public-metadata-', dir='/tmp') as directory:
            temporary = Path(directory)
            config = temporary / 'config.json'
            result = temporary / 'report.json'
            config.write_text(json.dumps(dict(files=blends, temporary=str(temporary), report=str(result))))
            subprocess.run([args.blender, '--background', '--factory-startup', '--disable-autoexec', '--python-exit-code', '1', '--python', str(Path(__file__).resolve()), '--', '--blender-worker', str(config)], check=True)
            report.extend(json.loads(result.read_text()))
    report.extend(sanitize_png(APP / item) for item in files if Path(item).suffix == '.png')
    Path(args.report).write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    print('Sanitized', len(report), 'public assets; preserved content verified. Report:', args.report)


if __name__ == '__main__':
    if '--blender-worker' in sys.argv:
        worker()
    else:
        main()
