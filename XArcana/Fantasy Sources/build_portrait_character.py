"""Build fresh public geometric bodies; never open an imported character file."""
from pathlib import Path
import struct
import math
import json
import sys
import zipfile
import bpy
from mathutils import Vector

BASE = Path(__file__).resolve().parent
sys.path.insert(0, str(BASE.parent / 'Creature Sources/Summons'))
from animation_export import export_rig, humanoid_clips


def material(name, color):
    result = bpy.data.materials.new(name)
    result.diffuse_color = (*color, 1)
    result.use_nodes = True
    result.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value = (*color, 1)
    return result


def build(name):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 24
    armature = bpy.data.armatures.new('PublicPlaceholderSkeleton')
    rig = bpy.data.objects.new('Portrait_Rig', armature)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    # Metres, Blender Z-up, with the face pointing along -Y.
    bones = [
        ('Root', None, (0, 0, 0), (0, 0, .1)),
        ('Hips', 'Root', (0, 0, .86), (0, 0, 1)),
        ('Spine', 'Hips', (0, 0, 1), (0, 0, 1.18)),
        ('Chest', 'Spine', (0, 0, 1.18), (0, 0, 1.36)),
        ('Neck', 'Chest', (0, 0, 1.36), (0, 0, 1.46)),
        ('Head', 'Neck', (0, 0, 1.46), (0, 0, 1.7)),
    ]
    for side, sign in [('Left', 1), ('Right', -1)]:
        bones.extend([
            (side + 'Shoulder', 'Chest', (0, 0, 1.34), (sign * .2, 0, 1.34)),
            (side + 'Arm', side + 'Shoulder', (sign * .2, 0, 1.34), (sign * .42, 0, 1.14)),
            (side + 'ForeArm', side + 'Arm', (sign * .42, 0, 1.14), (sign * .56, 0, .93)),
            (side + 'Hand', side + 'ForeArm', (sign * .56, 0, .93), (sign * .63, -.02, .84)),
            (side + 'UpLeg', 'Hips', (sign * .115, 0, .88), (sign * .115, 0, .48)),
            (side + 'Leg', side + 'UpLeg', (sign * .115, 0, .48), (sign * .115, 0, .1)),
            (side + 'Foot', side + 'Leg', (sign * .115, 0, .1), (sign * .115, -.15, .06)),
        ])
    for bone_name, parent, head, tail in bones:
        bone = armature.edit_bones.new(bone_name)
        bone.head, bone.tail = head, tail
        if parent:
            bone.parent = armature.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    shell = material('PublicPlaceholderShell', (.12, .58, .68) if name == 'AlanCharacter' else (.58, .32, .72))
    dark = material('PublicPlaceholderJoints', (.04, .06, .1))
    glow = material('PublicPlaceholderEyes', (.7, .95, 1))
    vertices, faces, material_ids, influences = [], [], [], []
    surfaces = [shell, dark, glow]

    def ellipsoid(label, center, scale, bone, surface=shell, direction=None):
        # Fixed vertex and face order avoids Blender's nondeterministic join order.
        center = Vector(center)
        rotation = Vector(direction).to_track_quat('Z', 'Y') if direction is not None else None
        first = len(vertices)
        for ring in range(9):
            latitude = math.pi * ring / 8
            for sector in range(12):
                longitude = math.tau * sector / 12
                point = Vector((math.sin(latitude) * math.cos(longitude) * scale[0],
                                math.sin(latitude) * math.sin(longitude) * scale[1],
                                math.cos(latitude) * scale[2]))
                if rotation is not None:
                    point = rotation @ point
                vertices.append(tuple(center + point))
                influences.append(bone)
        for ring in range(8):
            for sector in range(12):
                a = first + ring * 12 + sector
                b = first + ring * 12 + (sector + 1) % 12
                faces.append((a, a + 12, b + 12, b))
                material_ids.append(surfaces.index(surface))

    ellipsoid('GeometricTorso', (0, 0, 1.16), (.23, .13, .27), 'Chest')
    ellipsoid('GeometricHips', (0, 0, .89), (.19, .12, .12), 'Hips', dark)
    ellipsoid('GeometricHead', (0, 0, 1.57), (.145, .12, .15), 'Head')
    for x in [-.052, .052]:
        ellipsoid('RobotEye', (x, -.113, 1.6), (.024, .017, .02), 'Head', glow)
    for bone_name, _, head, tail in bones:
        if any(token in bone_name for token in ['UpLeg', 'ForeArm', 'Foot']) or bone_name in ['LeftArm', 'RightArm', 'LeftLeg', 'RightLeg', 'LeftHand', 'RightHand']:
            start, end = Vector(head), Vector(tail)
            width = .075 if 'Leg' in bone_name else .055
            ellipsoid('Geometric' + bone_name, (start + end) / 2, (width, width, (end - start).length / 2 + .02), bone_name, direction=end - start)
    mesh = bpy.data.meshes.new('PublicPlaceholderGeometry')
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new('PublicPlaceholderBody', mesh)
    bpy.context.collection.objects.link(obj)
    for surface in surfaces:
        mesh.materials.append(surface)
    for polygon, surface_index in zip(mesh.polygons, material_ids):
        polygon.material_index = surface_index
        polygon.use_smooth = True
    for bone_name, _, _, _ in bones:
        obj.vertex_groups.new(name=bone_name).add([i for i, influence in enumerate(influences) if influence == bone_name], 1, 'REPLACE')
    modifier = obj.modifiers.new('Public weighted skeleton', 'ARMATURE')
    modifier.object = rig
    obj.parent = rig
    # A fresh source scene has no packed images or inherited prototype data.
    clips = humanoid_clips(rig)
    output = BASE.parent / 'Resources/Fantasy'
    data, root = export_rig(name, rig, [obj], clips, 1.72, output,
                            {'mouth': 'Head', 'leftHand': 'LeftHand', 'rightHand': 'RightHand', 'chest': 'Chest', 'hips': 'Hips'})
    data['provenance'] = 'procedural-public-placeholder-v1'
    data['license'] = 'CC0-1.0'
    (output / (name + '.rig.json')).write_text(json.dumps(data, separators=(',', ':')) + '\n')
    bpy.ops.object.select_all(action='SELECT')
    target = output / (name + '.usdz')
    bpy.ops.wm.usd_export(filepath=str(target), selected_objects_only=True, export_animation=False,
                          export_armatures=True, export_materials=True, export_textures_mode='NEW',
                          generate_preview_surface=True, generate_materialx_network=False,
                          convert_orientation=True, export_global_forward_selection='NEGATIVE_Z',
                          export_global_up_selection='Y', export_lights=False, export_cameras=False,
                          triangulate_meshes=True)
    # Normalize ZIP timestamps without changing USDZ's alignment padding.
    contents = bytearray(target.read_bytes())
    with zipfile.ZipFile(target) as archive:
        for entry in archive.infolist():
            struct.pack_into('<HH', contents, entry.header_offset + 10, 0, 33)
    offset = 0
    while (offset := contents.find(b'PK\x01\x02', offset)) >= 0:
        struct.pack_into('<HH', contents, offset + 12, 0, 33)
        offset += 46
    target.write_bytes(contents)
    print('PUBLIC_PLACEHOLDER', name, len(data['bones']), list(data['clips']))


if '--alan-only' not in sys.argv:
    build('PortraitCharacter')
build('AlanCharacter')
