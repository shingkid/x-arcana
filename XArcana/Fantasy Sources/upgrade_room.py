"""Reapply licensed PBR materials and export the editable room for SceneKit.
Run with Blender --background --python upgrade_room.py.
All source textures are adjacent to this script; no network access is required.
"""
import bpy,math
from pathlib import Path
from mathutils import Vector
SRC=Path(__file__).resolve().parent;OUT=SRC.parent/'Resources/Fantasy'
bpy.ops.wm.open_mainfile(filepath=str(SRC/'FantasyRoom.blend'))
# Close the rear vault to prevent a visible gap above the portal.
rear=bpy.data.objects.get('Rear wall')
if rear:
 rear.location.z=3.0;rear.dimensions.z=6.0;bpy.context.view_layer.update()
# Read the fresh editable geometry once. Subsequent executions replace materials by name.
def pbr(name,asset):
 m=bpy.data.materials.get(name) or bpy.data.materials.new(name);m.use_nodes=True;m.node_tree.nodes.clear();nodes=m.node_tree.nodes;links=m.node_tree.links
 shader=nodes.new('ShaderNodeBsdfPrincipled');output=nodes.new('ShaderNodeOutputMaterial');links.new(shader.outputs['BSDF'],output.inputs['Surface'])
 for key,input in [('Diffuse','Base Color'),('Rough','Roughness'),('nor_gl','Normal')]:
  tex=nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(SRC/'Textures'/f'{asset}_{key}.jpg'),check_existing=True)
  if key!='Diffuse':tex.image.colorspace_settings.name='Non-Color'
  if key=='nor_gl':
   normal=nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.75;links.new(tex.outputs['Color'],normal.inputs['Color']);links.new(normal.outputs['Normal'],shader.inputs[input])
  else:links.new(tex.outputs['Color'],shader.inputs[input])
 return m
leather=pbr('PBR Worn book leather','brown_leather')
stone=pbr('PBR Timeworn castle stone','stone_wall_05');wood=pbr('PBR Ancient timber','wood_floor_worn');floor=pbr('PBR Worn stone paving','stone_floor')
def uv_world(o,scale=2):
 if not o.data.uv_layers:o.data.uv_layers.new(name='UVMap')
 layer=o.data.uv_layers.active
 for face in o.data.polygons:
  normal=o.matrix_world.to_3x3()@face.normal;axis=max(range(3),key=lambda i:abs(normal[i]))
  for li in face.loop_indices:
   co=o.matrix_world@o.data.vertices[o.data.loops[li].vertex_index].co
   layer.data[li].uv=((co.y/scale,co.z/scale) if axis==0 else (co.x/scale,co.z/scale) if axis==1 else (co.x/scale,co.y/scale))
for o in list(bpy.context.scene.objects):
 if o.name.startswith('Slate tile') or o.name=='Archive stone floor':bpy.data.objects.remove(o,do_unlink=True);continue
 if o.type!='MESH' or len(o.data.materials)!=1:continue
 name=o.data.materials[0].name
 if name.startswith('Book ') or name=='PBR Worn book leather':o.data.materials.clear();o.data.materials.append(leather);uv_world(o,.4)
 if name in ['Midnight basalt','Indigo velvet','colormap'] or name.startswith('PBR Timeworn'):o.data.materials.clear();o.data.materials.append(stone);uv_world(o,2.1)
 if name=='Smoked walnut' or name.startswith('PBR Ancient'):o.data.materials.clear();o.data.materials.append(wood);uv_world(o,1.0)
# A single non-overlapping floor surface prevents shadow artifacts and preserves floor y=0.
if not bpy.data.objects.get('PBR stone floor'):
 bpy.ops.mesh.primitive_plane_add(size=2,location=(0,0,0));o=bpy.context.object;o.name='PBR stone floor';o.scale=(5,6.8,1);o.data.materials.append(floor);uv_world(o,1.8)
# More detailed carved stones around the rear portal, away from the clear combat aisle.
if not bpy.data.objects.get('Portal carved voussoir 00'):
 for i in range(32):
  a=i*math.tau/32;x=2.10*math.cos(a);z=2.25+2.10*math.sin(a)
  bpy.ops.mesh.primitive_cube_add(size=1,location=(x,6.42,z));o=bpy.context.object;o.name=f'Portal carved voussoir {i:02d}';o.dimensions=(.35,.25,.30);o.rotation_euler.y=-a;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(stone)
  bevel=o.modifiers.new('Worn carved edge','BEVEL');bevel.width=.03;bevel.segments=3;bpy.ops.object.modifier_apply(modifier=bevel.name);uv_world(o,1.2)
# Retain each object in the source, with images packed for portable editing.
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'FantasyRoom.blend'))
groups={}
for o in list(bpy.context.scene.objects):
 if o.type=='MESH' and len(o.data.materials)==1:groups.setdefault(o.data.materials[0].name,[]).append(o)
for name,objects in groups.items():
 if len(objects)<2:continue
 bpy.ops.object.select_all(action='DESELECT')
 for o in objects:o.select_set(True)
 bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();bpy.context.object.name='Archive_'+name
bpy.ops.wm.usd_export(filepath=str(OUT/'FantasyRoom.usdz'),export_lights=False,export_cameras=False,generate_preview_surface=True,generate_materialx_network=False,export_textures_mode='NEW',convert_orientation=True,export_global_forward_selection='NEGATIVE_Z',export_global_up_selection='Y',convert_scene_units='METERS',export_custom_properties=False)
scene=bpy.context.scene;scene.cycles.samples=96;scene.render.filepath=str(SRC/'FantasyRoom-preview.png');bpy.ops.render.render(write_still=True)
meshes=[o for o in scene.objects if o.type=='MESH'];print('FINAL_ROOM',len(meshes),sum(sum(len(f.vertices)-2 for f in o.data.polygons) for o in meshes),'triangles')
