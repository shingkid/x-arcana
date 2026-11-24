"""Convert the CC0 tevy skeleton to native USDZ, preserving mesh, PBR maps and walk cycle."""
import bpy, json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
SOURCE=Path(__file__).resolve().parent
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SOURCE/'skeleton-uncompressed.glb'))
rig=next(ob for ob in bpy.data.objects if ob.type=='ARMATURE')
mesh=next(ob for ob in bpy.data.objects if ob.type=='MESH' and ob.name.startswith('skeleton'))
for ob in list(bpy.data.objects):
 if ob not in (rig,mesh): bpy.data.objects.remove(ob,do_unlink=True)
for track in rig.animation_data.nla_tracks: track.mute=True
rig.animation_data.action=bpy.data.actions['walk']
rig.animation_data.action_slot=rig.animation_data.action.slots[0]
scene=bpy.context.scene
scene.render.fps=24
scene.frame_start=1
scene.frame_end=25
scene.frame_set(1)
for p in mesh.data.polygons: p.use_smooth=True
mesh.data.calc_loop_triangles()
metrics={'triangles':len(mesh.data.loop_triangles),'vertices':len(mesh.data.vertices),'joints':len(rig.data.bones),'texture_sizes':{im.name:list(im.size) for im in bpy.data.images},'source':'https://tevy.dev/models/skeleton/v1/lod0.glb','license':'CC0-1.0'}
(SOURCE/'metrics.json').write_text(json.dumps(metrics,indent=2)+'\n')
for image in bpy.data.images: image.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'Skeleton.blend'))
bpy.ops.wm.usd_export(filepath=str(ROOT/'Resources/Creatures/Skeleton.usdz'),export_animation=True,export_armatures=True,only_deform_bones=False,export_materials=True,generate_preview_surface=True,generate_materialx_network=False,export_textures_mode='NEW',export_lights=False,export_cameras=False,convert_orientation=True,export_global_forward_selection='NEGATIVE_Z',export_global_up_selection='Y',meters_per_unit=1.0,triangulate_meshes=True)
# A studio preview is only an authoring check, not a device gameplay capture.
scene.frame_set(7)
scene.render.engine='CYCLES';scene.cycles.samples=24
scene.world=bpy.data.worlds.new('Studio');scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.07,.085,.10,1)
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.4
for name,loc,power,size,color in [('Key',(2,-3,4),500,3,(1,.84,.66)),('Rim',(-2,1,3),650,2,(.32,.61,1)),('Fill',(-2,-2,1),150,2,(.66,.8,1))]:
 data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=color
 ob=bpy.data.objects.new(name,data);scene.collection.objects.link(ob);ob.location=loc;ob.rotation_euler=(Vector((0,0,1))-ob.location).to_track_quat('-Z','Y').to_euler()
camdata=bpy.data.cameras.new('Preview');cam=bpy.data.objects.new('Preview',camdata);scene.collection.objects.link(cam)
cam.location=(2.25,-4.5,2.1);cam.rotation_euler=(Vector((0,0,.95))-cam.location).to_track_quat('-Z','Y').to_euler();camdata.type='ORTHO';camdata.ortho_scale=2.15;scene.camera=cam
scene.render.resolution_x=700;scene.render.resolution_y=900;scene.render.resolution_percentage=100
scene.render.filepath=str(SOURCE/'skeleton-studio-preview.png')
bpy.ops.render.render(write_still=True)
print('SKELETON_METRICS',json.dumps(metrics))
