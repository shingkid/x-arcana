import bpy,json
from pathlib import Path
root=Path(__file__).resolve().parents[2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(root/'Creature Sources/Skeleton/skeleton-uncompressed.glb'))
for ob in bpy.data.objects:
 print('OBJECT',ob.name,ob.type,tuple(ob.dimensions), 'action', ob.animation_data.action.name if ob.animation_data and ob.animation_data.action else None)
 if ob.type=='ARMATURE':
  print('BONES',[(b.name,tuple(b.head_local)) for b in ob.data.bones])
  print('NLA',[(t.name,[(s.name,s.action.name) for s in t.strips]) for t in ob.animation_data.nla_tracks])
print('ACTIONS',[(a.name,tuple(a.frame_range)) for a in bpy.data.actions])
print('IMAGES',[(im.name,tuple(im.size)) for im in bpy.data.images])
print('USD OPTIONS',[p.identifier for p in bpy.ops.wm.usd_export.get_rna_type().properties])
