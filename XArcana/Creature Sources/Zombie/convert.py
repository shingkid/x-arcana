"""Prepare the CC0 Innerscene office zombie for the native encounter."""
import bpy,json,math,hashlib,sys,tempfile
import numpy as np
from pathlib import Path
from mathutils import Vector, Quaternion
from mathutils.bvhtree import BVHTree
SRC=Path(__file__).resolve().parent
ROOT=SRC.parents[1]
sys.path.insert(0, str(SRC.parent / 'Summons'))
from animation_export import export_rig, author_clip
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SRC/'office-zombie-original.glb'))
meshes=[ob for ob in bpy.context.scene.objects if ob.type=='MESH']
for ob in meshes:
 ob.data.calc_loop_triangles()
triangles=sum(len(ob.data.loop_triangles) for ob in meshes)
if triangles>55000:
 for ob in meshes:
  bpy.context.view_layer.objects.active=ob
  modifier=ob.modifiers.new('Mobile surface budget','DECIMATE');modifier.ratio=50000/triangles
  bpy.ops.object.modifier_apply(modifier=modifier.name)
for ob in meshes:
 for poly in ob.data.polygons:poly.use_smooth=True
 ob.data.calc_loop_triangles()
# Fit a UV patch to the existing tilted face using its actual eyes and mouth.
body=next(ob for ob in meshes if 'body and clothing' in ob.name)
eyes=next(ob for ob in meshes if ob.name=='Eyes')
def material_points(ob, phrase):
    indices={v for p in ob.data.polygons if phrase in ob.data.materials[p.material_index].name.lower() for v in p.vertices}
    return [ob.matrix_world @ ob.data.vertices[i].co for i in indices]
def mean(points):return sum(points,Vector())/len(points)
eye_points=material_points(eyes,'pale iris')
eye_mid=mean(eye_points)
left=mean([p for p in eye_points if p.x<eye_mid.x])
right=mean([p for p in eye_points if p.x>=eye_mid.x])
mouth=mean(material_points(body,'mouth'))
axis_x=(right-left).normalized()
axis_y=eye_mid-mouth
axis_y=(axis_y-axis_x*axis_y.dot(axis_x)).normalized()
normal=axis_x.cross(axis_y).normalized()
center=eye_mid+axis_y*.012
width=.185;height=.245
rows=40;columns=32
bvh=BVHTree.FromObject(body,bpy.context.evaluated_depsgraph_get())
vertices=[];uvs=[];faces=[]
for row in range(rows+1):
    for col in range(columns+1):
        u=col/columns;v=row/rows
        point=center+axis_x*((u-.5)*width)+axis_y*((v-.5)*height)
        hit,hit_normal,_,_=bvh.ray_cast(point+normal*.30,-normal,.6)
        if hit is not None and hit.z>1.39:
            nx=(u-.5)*2;ny=(v-.5)*2
            bridge=.004-.015*(nx*nx+.8*ny*ny)
            depth=max((hit-center).dot(normal),bridge)
            point+=normal*(depth+.0025)
        else:
            point-=normal*.035
        vertices.append(point);uvs.append((u,v))
for row in range(rows):
    for col in range(columns):
        a=row*(columns+1)+col
        if ((col+.5)/columns*2-1)**2+((row+.5)/rows*2-1)**2<=1:
            faces.append((a,a+1,a+columns+2,a+columns+1))
patch_data=bpy.data.meshes.new('Portrait face surface')
patch_data.from_pydata(vertices,[],faces);patch_data.update()
uv_layer=patch_data.uv_layers.new(name='FaceUV')
for polygon in patch_data.polygons:
    polygon.use_smooth=True
    for loop_index in polygon.loop_indices:
        uv_layer.data[loop_index].uv=uvs[patch_data.loops[loop_index].vertex_index]
patch=bpy.data.objects.new('PortraitFace',patch_data);bpy.context.scene.collection.objects.link(patch)
placeholder=bpy.data.materials.new('Portrait face placeholder');placeholder.diffuse_color=(.50,.57,.42,1)
patch.data.materials.append(placeholder)
# The runtime replaces this placeholder with the original NPC photo and a feathered UV crop.
patch.hide_render=True
# Preserve the source facial landmarks in patch UV coordinates for runtime photo alignment.
def patch_uv(point):
    d=point-center
    return {'x':d.dot(axis_x)/width+.5,'y':d.dot(axis_y)/height+.5}
face_mapping={'leftEye':patch_uv(left),'rightEye':patch_uv(right),'mouth':patch_uv(mouth),'width':width,'height':height}
(ROOT/'Resources/Creatures/ZombieFace.json').write_text(json.dumps(face_mapping,indent=2)+'\n')
(SRC/'face-mapping.json').write_text(json.dumps(face_mapping,indent=2)+'\n')
patch_data.calc_loop_triangles()
meshes.append(patch)
# The retained GLB is immutable. All material and silhouette edits below are reproducible.
# Store the same head and fitted face in every body so the landmark contract is unchanged.
original_positions = {ob.name: [v.co.copy() for v in ob.data.vertices] for ob in meshes}
original_hash = hashlib.sha256((SRC / 'office-zombie-original.glb').read_bytes()).hexdigest()

cloth_vertices = {}
for ob in meshes:
    cloth_vertices[ob.name] = {v for polygon in ob.data.polygons
        if any(word in ob.data.materials[polygon.material_index].name.lower() for word in ['shirt', 'trousers'])
        for v in polygon.vertices}

# Neutral office colors preserve the source texture's dirt and surface variation.
palette = {
    'skin, pale': (.52, .49, .46), 'skin, sunken': (.23, .20, .20),
    'office shirt': (.56, .57, .55), 'trousers': (.055, .063, .072),
    'tie,': (.085, .068, .063), 'nails': (.36, .33, .30),
    'hair': (.065, .055, .046),
}
for mat in bpy.data.materials:
    if not mat.use_nodes:
        continue
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    if bsdf:
        bsdf.inputs['Roughness'].default_value = .88
    target = next((rgb for key, rgb in palette.items() if key in mat.name.lower()), None)
    for texture in [n for n in mat.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image]:
        derived = texture.image.copy()
        derived.name = 'Office_' + mat.name.replace(',', '')
        derived.scale(1024, 1024)
        if target:
            pixels = np.array(derived.pixels[:], dtype=np.float32).reshape((-1, 4))
            luminance = pixels[:, :3] @ np.array([.2126, .7152, .0722], dtype=np.float32)
            detail = np.clip(luminance / max(.001, float(np.median(luminance))), .48, 1.22)
            if 'shirt' in mat.name.lower() or 'trousers' in mat.name.lower():
                # Keep source wear visible in the muted palette without inventing wound maps.
                detail = np.clip(1 + (detail - 1) * 1.65, .40, 1.25)
            pixels[:, :3] = np.clip(detail[:, None] * np.array(target), 0, 1)
            derived.pixels[:] = pixels.ravel()
        derived.pack()
        texture.image = derived
        if bsdf and ('shirt' in mat.name.lower() or 'trousers' in mat.name.lower()):
            # Source surface variation drives subtle cloth roughness.
            grayscale = mat.node_tree.nodes.new('ShaderNodeRGBToBW')
            mat.node_tree.links.new(texture.outputs['Color'], grayscale.inputs['Color'])
            roughness = mat.node_tree.nodes.new('ShaderNodeMapRange')
            roughness.inputs['To Min'].default_value = .78
            roughness.inputs['To Max'].default_value = .98
            mat.node_tree.links.new(grayscale.outputs[0], roughness.inputs['Value'])
            mat.node_tree.links.new(roughness.outputs[0], bsdf.inputs['Roughness'])

# Height-dependent shaping changes shoulders, waist, and hips independently.
# All vertices above 1.43 m, including the full head and face overlay, are untouched.
profiles = {
    'neutral': [(0, 1), (.70, 1), (.88, 1.03), (1.02, .96), (1.20, .96), (1.34, .96), (1.43, 1)],
    'male': [(0, 1), (.70, 1), (.88, 1), (1.02, .99), (1.20, 1.04), (1.34, 1.04), (1.43, 1)],
    'female': [(0, 1), (.70, .96), (.88, 1.13), (.98, 1.08), (1.08, .83), (1.22, .80), (1.34, .80), (1.43, 1)],
}

def profile_scale(height, profile):
    for (low, a), (high, b) in zip(profile, profile[1:]):
        if low <= height <= high:
            t = (height - low) / (high - low)
            t = t * t * (3 - 2 * t)
            return a + (b - a) * t
    return 1

# The source is posed, so use its anatomical joint positions as the bind pose.
# Segment-distance weights keep the authored clothing, fingers and face intact.
joints = [
    ('Hips', None, (-.045,.025,.91), (-.045,.015,1.06)),
    ('Spine', 'Hips', (-.045,.015,1.06), (-.045,-.015,1.22)),
    ('Chest', 'Spine', (-.045,-.015,1.22), (-.055,-.045,1.40)),
    ('Neck', 'Chest', (-.055,-.045,1.40), (-.065,-.10,1.48)),
    ('Head', 'Neck', (-.065,-.10,1.48), (-.08,-.15,1.67)),
    ('LeftArm', 'Chest', (.13,-.045,1.35), (.12,-.285,1.21)),
    ('LeftForeArm', 'LeftArm', (.12,-.285,1.21), (-.105,-.48,1.15)),
    ('LeftHand', 'LeftForeArm', (-.105,-.48,1.15), (-.12,-.55,1.08)),
    ('RightArm', 'Chest', (-.22,-.015,1.33), (-.245,.015,1.07)),
    ('RightForeArm', 'RightArm', (-.245,.015,1.07), (-.245,-.095,.88)),
    ('RightHand', 'RightForeArm', (-.245,-.095,.88), (-.245,-.115,.78)),
    ('LeftUpLeg', 'Hips', (.07,.015,.89), (.105,-.015,.51)),
    ('LeftLeg', 'LeftUpLeg', (.105,-.015,.51), (.13,.015,.12)),
    ('LeftFoot', 'LeftLeg', (.13,.015,.12), (.13,-.08,.055)),
    ('RightUpLeg', 'Hips', (-.105,.025,.89), (-.115,.14,.51)),
    ('RightLeg', 'RightUpLeg', (-.115,.14,.51), (-.13,.25,.12)),
    ('RightFoot', 'RightLeg', (-.13,.25,.12), (-.13,.15,.055)),
]
armature = bpy.data.armatures.new('Infected human joints')
rig = bpy.data.objects.new('ZombieRig', armature)
bpy.context.scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
for name, parent, head, tail in joints:
    bone = armature.edit_bones.new(name)
    bone.head = head; bone.tail = tail
    if parent: bone.parent = armature.edit_bones[parent]
bpy.ops.object.mode_set(mode='OBJECT')

def segment_distance(point, a, b):
    a = Vector(a); b = Vector(b)
    delta = b-a
    return (point - (a + delta * min(1, max(0, (point-a).dot(delta)/delta.length_squared)))).length

for ob in meshes:
    groups = {name: ob.vertex_groups.new(name=name) for name, *_ in joints}
    for vertex in ob.data.vertices:
        point = ob.matrix_world @ vertex.co
        if ob is patch or ob is eyes or point.z >= 1.43:
            weights = [('Head', 1)]
        elif ob.name == 'Hand, left':
            weights = [('LeftHand', 1)]
        elif ob.name == 'Hand, right':
            weights = [('RightHand', 1)]
        else:
            candidates = joints[:4] + joints[5:]
            if point.z < .82:
                candidates = joints[11:] + joints[:1]
            elif point.z < 1.02 and point.x > -.18 and point.y > -.18:
                candidates = joints[:2] + [joints[11], joints[14]]
            distances = sorted((segment_distance(point, a, b), name) for name, _, a, b in candidates)[:4]
            raw = [(name, 1 / max(.018, distance) ** 6) for distance, name in distances]
            total = sum(weight for _, weight in raw)
            weights = [(name, weight/total) for name, weight in raw]
        for name, weight in weights:
            if weight > .0001: groups[name].add([vertex.index], weight, 'REPLACE')
    modifier = ob.modifiers.new('Weighted infected movement', 'ARMATURE')
    modifier.object = rig

# Convert world-axis rotations into each posed bone's local frame.
def pose(t, angles, bob=0):
    rotations = {}
    for name, xyz in angles.items():
        basis = rig.data.bones[name].matrix_local.to_3x3()
        rotation = Quaternion()
        for axis, angle in zip([(1,0,0), (0,1,0), (0,0,1)], xyz):
            rotation = rotation @ Quaternion(basis.inverted() @ Vector(axis), angle)
        rotations[name] = rotation.to_euler('XYZ')
    return t, rotations, {'Hips': (0,bob,0)} if bob else {}

walk = []
for i in range(17):
    t=i/16; cycle=t*math.tau; step=math.sin(cycle)
    walk.append(pose(t, {
        'LeftUpLeg': (.27*step,0,0), 'RightUpLeg': (-.22*step,0,0),
        'LeftLeg': (-max(0,-step)*.30,0,0), 'RightLeg': (-max(0,step)*.23,0,0),
        'LeftFoot': (.09*step,0,0), 'RightFoot': (-.07*step,0,0),
        'Spine': (.055, .025*step, 0), 'Chest': (.025,0,.055*step),
        'Head': (-.02+.018*math.sin(2*cycle), .055+.022*step, -.015*step),
        'LeftArm': (-.12*step,0,.035*step), 'RightArm': (.16*step,.025,0),
        'LeftForeArm': (.07*step,0,.04), 'RightForeArm': (-.03,0,.06+.035*step),
    }, .006*math.sin(2*cycle)))
clips = {'walk': author_clip(rig,'walk',1.18,walk)}
clips['idle'] = author_clip(rig,'idle',2.4,[pose(0,{'Spine':(.06,0,0),'Head':(0,.055,0)}),
    pose(.5,{'Spine':(.07,0,.015),'Head':(.025,.075,-.018),'RightForeArm':(0,0,.045)}),
    pose(1,{'Spine':(.06,0,0),'Head':(0,.055,0)})])
clips['swipe'] = author_clip(rig,'swipe',.64,[pose(0,{}),
    pose(.25,{'Chest':(-.04,0,-.18),'LeftArm':(-.20,0,-.16),'LeftForeArm':(0,0,-.20)}),
    pose(.53,{'Chest':(.12,0,.23),'LeftArm':(-.35,0,.42),'LeftForeArm':(0,0,.32),'Head':(.08,0,.07)}),
    pose(.78,{'Chest':(.07,0,.1),'LeftArm':(-.18,0,.18)}),pose(1,{})])
clips['bite'] = author_clip(rig,'bite',.64,[pose(0,{}),
    pose(.25,{'Spine':(-.08,0,0),'Head':(-.16,0,0)}),
    pose(.53,{'Spine':(.19,0,0),'Chest':(.16,0,0),'Neck':(.12,0,0),'Head':(.11,0,0),
              'LeftArm':(-.14,0,.1),'RightArm':(-.12,0,-.07)}),
    pose(.78,{'Spine':(.08,0,0),'Head':(.08,0,0)}),pose(1,{})])
original_matrices = {ob.name: ob.matrix_world.copy() for ob in [rig] + meshes}
report = {'source_sha256': original_hash, 'license': 'CC0-1.0', 'models': {}}
for style, profile in profiles.items():
    for ob in meshes:
        inverse = ob.matrix_world.inverted()
        for vertex, original in zip(ob.data.vertices, original_positions[ob.name]):
            point = ob.matrix_world @ original
            if point.z < 1.43 and ob is not patch:
                width_scale = profile_scale(point.z, profile)
                point.x = -.045 + (point.x + .045) * width_scale
                if style == 'female':
                    waist = math.exp(-((point.z - 1.08) / .11) ** 2)
                    point.y *= 1 - .09 * waist
                    # A small clothed chest contour, restricted to the front of the torso.
                    chest = math.exp(-((point.z - 1.25) / .08) ** 2)
                    central = max(0, 1 - abs(point.x + .045) / .20)
                    if -.23 < point.y < -.02:
                        point.y -= .018 * chest * central
            if vertex.index in cloth_vertices[ob.name] and .20 < point.z < 1.40:
                # Millimetre folds break the plastic silhouette without adding geometry.
                crease = (.0018 * math.sin(point.z * 94 + point.x * 24)
                          + .0010 * math.sin(point.z * 49 - point.y * 63))
                joint_fold = .35 + .65 * max(math.exp(-((point.z-z)/.08)**2) for z in [.5,1.03,1.19])
                normal = ob.matrix_world.to_3x3() @ vertex.normal
                point += normal.normalized() * crease * joint_fold
            vertex.co = inverse @ point
        ob.data.update()
    suffix = '' if style == 'neutral' else style.title()
    name = 'Zombie' + suffix
    patch.hide_render = False
    rig.data.pose_position = 'REST'
    bpy.context.view_layer.update()
    rig_data, export_root = export_rig(name, rig, meshes, clips, 1.708764076, ROOT / 'Resources/Creatures',
        {'leftHand':'LeftHand','rightHand':'RightHand','leftFoot':'LeftFoot','rightFoot':'RightFoot','head':'Head'})
    bpy.context.preferences.filepaths.save_version = 0
    # Packed images need no machine-specific source or cache paths in a public file.
    for image in bpy.data.images:
        image.filepath = '//textures/' + image.name
        for packed in image.packed_files: packed.filepath = image.filepath
    for text in bpy.data.texts:
        text.filepath = ''
    bpy.context.scene.render.filepath = '//preview'
    for screen in bpy.data.screens:
        for area in screen.areas:
            for space in area.spaces:
                params = getattr(space, 'params', None)
                if params is not None and hasattr(params, 'directory'): params.directory = b'//'
    with tempfile.TemporaryDirectory(prefix='xarcana-zombie-source-', dir='/private/tmp') as temporary:
        portable = Path(temporary) / (name + '.blend')
        bpy.ops.wm.save_as_mainfile(filepath=str(portable), relative_remap=False, compress=False)
        data = portable.read_bytes()
        if b'/Users/' in data:
            Path('/private/tmp/xarcana-zombie-unsanitized.blend').write_bytes(data)
        assert b'/Users/' not in data, 'A local author path remains in the generated source'
        (SRC / (name + '.blend')).write_bytes(data)
    bpy.ops.wm.usd_export(filepath=str(ROOT / 'Resources/Creatures' / (name + '.usdz')),
        export_animation=False, export_materials=True, generate_preview_surface=True,
        generate_materialx_network=False, export_textures_mode='NEW', export_lights=False,
        export_cameras=False, convert_orientation=True, export_global_forward_selection='NEGATIVE_Z',
        export_global_up_selection='Y', meters_per_unit=1.0, triangulate_meshes=True,
        usdz_downscale_size='1024')
    head_unchanged = all((vertex.co - original).length < 0.000001
        for ob in meshes for vertex, original in zip(ob.data.vertices, original_positions[ob.name])
        if (ob.matrix_world @ original).z >= 1.43 or ob is patch)
    assert head_unchanged, 'Body deformation changed the face contract'
    triangles = sum(len(ob.data.loop_triangles) for ob in meshes)
    assert 48000 <= triangles <= 55000
    report['models'][style] = {'file': name + '.usdz', 'triangles': triangles,
        'mesh_count': len(meshes), 'bones': len(rig_data['bones']),
        'clips': {clip: data['duration'] for clip, data in rig_data['clips'].items()},
        'weighted_vertices': sum(len(ob.data.vertices) for ob in meshes),
        'head_and_face_unchanged': head_unchanged,
        'shoulder_width_factor': profile_scale(1.26, profile),
        'hip_width_factor': profile_scale(.88, profile)}
    # Unparent before deriving the next body to prevent cumulative normalization.
    for ob in [rig] + meshes:
        if ob.parent == export_root:
            ob.parent = None; ob.matrix_world = original_matrices[ob.name]
    bpy.data.objects.remove(export_root, do_unlink=True)
assert hashlib.sha256((SRC / 'office-zombie-original.glb').read_bytes()).hexdigest() == original_hash
(SRC / 'metrics.json').write_text(json.dumps(report, indent=2) + '\n')
hash_targets = [SRC / 'office-zombie-original.glb'] + [
    ROOT / 'Resources/Creatures' / filename
    for row in report['models'].values()
    for filename in [row['file'], row['file'].replace('.usdz', '.rig.json')]]
(SRC / 'SHA256SUMS').write_text(''.join(
    hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + str(path.relative_to(ROOT.parent)) + '\n'
    for path in hash_targets))
print('ZOMBIE_METRICS', json.dumps(report))
