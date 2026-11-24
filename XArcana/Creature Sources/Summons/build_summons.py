"""Convert the credited source sculptures into mobile USDZ models.
Run with Blender --background --factory-startup --disable-autoexec --python build_summons.py.
"""
import bpy
import json
import math
from pathlib import Path
from mathutils import Vector, Matrix
import numpy as np
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from animation_export import prepare_surface, export_rig, humanoid_clips

BASE = Path(__file__).resolve().parent
OUTPUT = BASE.parents[1] / 'Resources' / 'Creatures'
TEXTURES = BASE / 'textures'
TEXTURES.mkdir(exist_ok=True)
OUTPUT.mkdir(exist_ok=True)
REPORT = {}


def object_mode():
    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')


def material(name, diffuse, normal=None, silver=False):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bs = nodes.get('Principled BSDF')
    bs.inputs['Roughness'].default_value = 0.62 if silver else 0.73
    bs.inputs['Metallic'].default_value = 0.12 if silver else 0
    tex = nodes.new('ShaderNodeTexImage')
    tex.image = diffuse
    links.new(tex.outputs['Color'], bs.inputs['Base Color'])
    if silver:
        bs.inputs['Emission Color'].default_value = (0.025, 0.070, 0.12, 1)
        bs.inputs['Emission Strength'].default_value = 0.65
    if normal:
        normal.colorspace_settings.name = 'Non-Color'
        tex = nodes.new('ShaderNodeTexImage')
        tex.image = normal
        mapping = nodes.new('ShaderNodeNormalMap')
        mapping.inputs['Strength'].default_value = 0.70
        links.new(tex.outputs['Color'], mapping.inputs['Color'])
        links.new(mapping.outputs['Normal'], bs.inputs['Normal'])
    return mat


def recolor(image, name, silver):
    # Preserve the source's UV fur/skin structure instead of replacing it with a flat color.
    w, h = image.size
    pixels = np.array(image.pixels[:], dtype=np.float32).reshape((h, w, 4))
    if silver:
        value = pixels[:, :, :3] @ np.array([0.2126, 0.7152, 0.0722])
        value = 0.10 + np.power(np.clip(value, 0, 1), 0.7) * 0.48
        pixels[:, :, :3] = value[:, :, None] * np.array([0.54, 0.80, 1.0])
    else:
        # Deep oxblood skin and weathered bone retain the artist's painted markings.
        pixels[:, :, :3] *= np.array([0.60, 0.45, 0.40])
    result = bpy.data.images.new(name, width=w, height=h, alpha=True)
    result.pixels[:] = pixels.flatten()
    result.filepath_raw = str(TEXTURES / (name + '.png'))
    result.file_format = 'PNG'
    result.save()
    return result


def save_image(image, name):
    w, h = image.size
    pixels = list(image.pixels[:])
    result = bpy.data.images.new(name, width=w, height=h, alpha=True)
    result.colorspace_settings.name = 'Non-Color'
    result.pixels[:] = pixels
    result.filepath_raw = str(TEXTURES / (name + '.png'))
    result.file_format = 'PNG'
    result.save()
    return result


def finish(name, objects, rig, clips, height, attachments):
    data, root = export_rig(name, rig, objects, clips, height, OUTPUT, attachments)
    keep = set(objects + [rig, root])
    for obj in list(bpy.data.objects):
        if obj not in keep:
            bpy.data.objects.remove(obj, do_unlink=True)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.wm.usd_export(filepath=str(OUTPUT / (name + '.usdz')), selected_objects_only=True,
                          export_animation=False, export_armatures=True, export_shapekeys=False,
                          export_materials=True, export_textures_mode='NEW', overwrite_textures=True,
                          generate_preview_surface=True, generate_materialx_network=False,
                          convert_orientation=True, export_global_forward_selection='NEGATIVE_Z', export_global_up_selection='Y', export_lights=False, export_cameras=False,
                          export_custom_properties=False, triangulate_meshes=True,
                          usdz_downscale_size='1024', convert_world_material=False)
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(BASE / (name + '.blend')))
    REPORT[name] = {'triangles': sum(sum(len(__import__('base64').b64decode(p['indices'])) // 12 for p in m['parts']) for m in data['meshes']),
                    'bones': len(data['bones']), 'clips': list(clips), 'textures': '1024 px source maps',
                    'pose': 'Weighted detailed surface; independently animated skeleton'}


def demon():
    bpy.ops.wm.open_mainfile(filepath=str(BASE / 'downloads/Demon - Blend/demon.blend'), use_scripts=False)
    object_mode()
    obj = bpy.data.objects['Demon']
    rig = bpy.data.objects['Demon-Skeleton']
    rig.animation_data_clear()
    rig.data.pose_position = 'POSE'
    for bone in rig.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    color = bpy.data.images.load(str(BASE / 'downloads/Demon - Blend/demon_diffuse.png'))
    normal = bpy.data.images.load(str(BASE / 'downloads/Demon - Blend/demon_normals.png'))
    normal.colorspace_settings.name = 'Non-Color'
    normal = save_image(normal, 'Demon-normal')
    obj.data.materials.clear()
    obj.data.materials.append(material('Demon_SculptedSkin', recolor(color, 'Demon-color', False), normal))
    rig.data.pose_position = 'REST'
    prepare_surface(obj, 2, 48000)
    obj.name = 'DemonSculpt'
    clips = humanoid_clips(rig, demon=True)
    finish('Demon', [obj], rig, clips, 2.15, {'mouth':'Jaw','leftHand':'hand.L','rightHand':'hand.R','chest':'ribs','hips':'hips'})


def stag():
    bpy.ops.wm.open_mainfile(filepath=str(BASE / 'downloads/CDmir-Stag.blend'), use_scripts=False)
    object_mode()
    rig = bpy.data.objects['Armature']
    run = bpy.data.actions['Run']
    idle = bpy.data.actions['Idle.000']
    rig.animation_data_clear()
    rig.data.pose_position = 'REST'
    mapping = [('Body', 'body', 'deer-body-normal.png'), ('Head', 'head', 'deer-head-normal.png'),
               ('Antlers', 'deer-antlers.png', 'deer-antlers-normal.png')]
    mats = {}
    for key, color, normal in mapping:
        norm = bpy.data.images[normal]
        norm.colorspace_settings.name = 'Non-Color'
        mats[key] = material('Patronus_' + key, recolor(bpy.data.images[color], 'Stag-' + key + '-color', True),
                             save_image(norm, 'Stag-' + key + '-normal'), silver=True)
    eye = bpy.data.materials.new('Patronus_Eye')
    eye.diffuse_color = (.24, .65, 1, 1)
    eye.use_nodes = True
    bs = eye.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value = (.08, .22, .38, 1)
    bs.inputs['Roughness'].default_value = .18
    bs.inputs['Emission Color'].default_value = (.15, .4, .7, 1)
    bs.inputs['Emission Strength'].default_value = .8
    mats['Eye'] = eye
    objects = []
    for name in ['Body', 'Head', 'Horns', 'Eyes']:
        obj = bpy.data.objects[name]
        key = {'Body': 'Body', 'Head': 'Head', 'Horns': 'Antlers', 'Eyes': 'Eye'}[name]
        obj.data.materials.clear()
        obj.data.materials.append(mats[key])
        for polygon in obj.data.polygons:
            polygon.material_index = 0
        prepare_surface(obj, 2 if name != 'Eyes' else 1, 26000 if name == 'Body' else 14000)
        obj.name = 'Stag' + name
        objects.append(obj)
    clips = {'run': (run, 0, 14, 24), 'walk': (run, 0, 14, 16), 'idle': (idle, 0, 160, 24)}
    finish('Stag', objects, rig, clips, 2.10, {'mouth':'Head','chest':'Backbone.001','hips':'Hip'})


demon()
stag()
(BASE / 'asset-report.json').write_text(json.dumps(REPORT, indent=2) + '\n')
print('SUMMON_ASSETS', json.dumps(REPORT))
