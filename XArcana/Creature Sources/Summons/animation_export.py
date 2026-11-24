"""Bake weighted surfaces and bone clips for SceneKit, without modifying original sources."""
import base64
import json
import math
import struct
import bpy
from mathutils import Matrix, Vector


def packed(values, code):
    return base64.b64encode(struct.pack('<' + str(len(values)) + code, *values)).decode('ascii')


def matrix_values(matrix):
    return [round(matrix[row][col], 7) for col in range(4) for row in range(4)]


def prepare_surface(obj, subdivisions, budget):
    # Applying only the surface modifier preserves interpolated skin weights.
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    if subdivisions:
        modifier = obj.modifiers.new('Articulated surface detail', 'SUBSURF')
        modifier.levels = subdivisions
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.data.calc_loop_triangles()
    if len(obj.data.loop_triangles) > budget:
        modifier = obj.modifiers.new('Mobile surface budget', 'DECIMATE')
        modifier.ratio = budget / len(obj.data.loop_triangles)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    for p in obj.data.polygons:
        p.use_smooth = True


def normalization(objects, height):
    points = [o.matrix_world @ v.co for o in objects for v in o.data.vertices]
    lo = Vector([min(p[i] for p in points) for i in range(3)])
    hi = Vector([max(p[i] for p in points) for i in range(3)])
    scale = height / (hi.z - lo.z)
    center = Vector(((hi.x + lo.x) / 2, (hi.y + lo.y) / 2, lo.z))
    # Blender -Y forward becomes SceneKit +Z; Blender Z becomes SceneKit Y.
    axis = Matrix.Rotation(-math.pi / 2, 4, 'X')
    return axis @ Matrix.Scale(scale, 4) @ Matrix.Translation(-center)


def author_clip(rig, name, duration, poses, fps=24):
    rig.animation_data_create()
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    rig.animation_data.action = action
    for bone in rig.pose.bones:
        bone.rotation_mode = 'XYZ'
    for fraction, rotations, translations in poses:
        frame = round(fraction * duration * fps)
        for bone in rig.pose.bones:
            bone.rotation_euler = rotations.get(bone.name, (0, 0, 0))
            bone.location = translations.get(bone.name, (0, 0, 0))
            bone.scale = (1, 1, 1)
            bone.keyframe_insert('rotation_euler', frame=frame)
            bone.keyframe_insert('location', frame=frame)
    return action, 0, round(duration * fps), fps


def humanoid_clips(rig, demon=False):
    names = dict(hips='hips', spine='spine', chest='ribs', head='head', la='upper_arm.L', ra='upper_arm.R', lf='forearm.L', rf='forearm.R', ll='thigh.L', rl='thigh.R', lk='shin.Top.L', rk='shin.Top.R') if demon else dict(hips='Hips', spine='Spine', chest='Chest', head='Head', la='LeftArm', ra='RightArm', lf='LeftForeArm', rf='RightForeArm', ll='LeftUpLeg', rl='RightUpLeg', lk='LeftLeg', rk='RightLeg')
    def pose(t, data=None, y=0):
        rotations = {names[k]:v for k,v in (data or {}).items() if k in names}
        # Lower the arms from the source bind pose, while leaving fingers weighted.
        rotations.setdefault(names['la'], (0, 0, -.55 if demon else -.08))
        rotations.setdefault(names['ra'], (0, 0, .55 if demon else .08))
        return t, rotations, {names['hips']:(0,y,0)} if y else {}
    result = {}
    result['idle'] = author_clip(rig,'idle',2.4,[pose(0),pose(.5,{'chest':(.025,0,0),'head':(-.02,.025,0)}),pose(1)])
    walk=[]
    for t in [0,.25,.5,.75,1]:
        a=math.sin(t*math.tau)*.37
        walk.append(pose(t,{'ll':(a,0,0),'rl':(-a,0,0),'lk':(max(0,-a)*.8,0,0),'rk':(max(0,a)*.8,0,0),'la':(-a*.55,0,-.4),'ra':(a*.55,0,.4),'chest':(0,.07*math.sin(t*math.tau),0)}))
    result['walk']=author_clip(rig,'walk',.92,walk)
    result['slap']=author_clip(rig,'slap',.673,[pose(0),pose(.32,{'ra':(-.7,-.8,1.2),'rf':(-1,0,0),'chest':(0,-.35,0)}),pose(.52,{'ra':(-1.15,.85,.35),'rf':(-.2,0,0),'chest':(.12,.5,0)}),pose(.72,{'ra':(-.8,1,.1),'chest':(.1,.3,0)}),pose(1)])
    result['slam']=author_clip(rig,'slam',.66,[pose(0),pose(.32,{'spine':(-.38,0,0),'la':(-1.6,0,-.4),'ra':(-1.6,0,.4),'ll':(-.28,0,0),'rl':(-.28,0,0)},-.12),pose(.53,{'spine':(.7,0,0),'chest':(.35,0,0),'la':(-.9,0,-.2),'ra':(-.9,0,.2),'lk':(.55,0,0),'rk':(.55,0,0)},-.24),pose(.72,{'spine':(.4,0,0),'la':(-.7,0,-.3),'ra':(-.7,0,.3)},-.12),pose(1)])
    if demon:
        result['clawCombo']=author_clip(rig,'clawCombo',.77,[pose(0),pose(.2,{'la':(-.8,-.6,-1),'lf':(-.8,0,0),'chest':(0,.35,0)}),pose(.36,{'la':(-1,.8,-.2),'chest':(.12,-.35,0)}),pose(.55,{'ra':(-.8,.6,1),'rf':(-.8,0,0),'chest':(0,-.35,0)}),pose(.73,{'ra':(-1,-.8,.2),'chest':(.12,.35,0)}),pose(1)])
        breath=[pose(0),pose(.25,{'head':(-.35,0,0),'chest':(-.15,0,0)}),pose(.38,{'head':(.18,0,0),'chest':(.18,0,0)}),pose(.82,{'head':(.18,.08,0),'chest':(.18,0,0)}),pose(1)]
        for i in [1,2,3]: breath[i][1]['Jaw']=(.5,0,0)
        result['breath']=author_clip(rig,'breath',1.18,breath)
    return result


def export_rig(name, rig, objects, clips, height, folder, attachments):
    rig.data.pose_position='REST'
    bpy.context.view_layer.update()
    norm=normalization(objects,height)
    bones=list(rig.data.bones)
    ids={b.name:i for i,b in enumerate(bones)}
    globals_=[norm @ rig.matrix_world @ b.matrix_local for b in bones]
    result={'version':1,'asset':name,'bones':[],'meshes':[],'clips':{},'attachments':attachments}
    for i,b in enumerate(bones):
        parent=ids[b.parent.name] if b.parent else -1
        local=globals_[parent].inverted() @ globals_[i] if parent>=0 else globals_[i]
        result['bones'].append({'name':b.name,'parent':parent,'rest':matrix_values(local),'inverseBind':matrix_values(globals_[i].inverted())})
    for obj in objects:
        mesh=obj.data;mesh.calc_loop_triangles()
        vertex=[];normal=[];uv=[];weights=[];indices=[]
        groups={g.index:ids[g.name] for g in obj.vertex_groups if g.name in ids}
        world=norm @ obj.matrix_world
        normalmat=world.to_3x3().inverted().transposed()
        parts=[[] for _ in obj.data.materials]
        for loop in mesh.loops:
            v=mesh.vertices[loop.vertex_index]
            vertex.extend(world @ v.co)
            normal.extend((normalmat @ loop.normal).normalized())
            uv.extend(mesh.uv_layers.active.data[loop.index].uv if mesh.uv_layers.active else (0,0))
            influences=sorted([(g.weight,groups[g.group]) for g in v.groups if g.group in groups],reverse=True)[:4]
            total=sum(w for w,_ in influences)
            influences=[(w/total,i) for w,i in influences] if total else [(1,0)]
            influences += [(0,0)]*(4-len(influences))
            weights.extend(w for w,_ in influences); indices.extend(i for _,i in influences)
        for tri in mesh.loop_triangles: parts[min(tri.material_index,len(parts)-1)].extend(tri.loops)
        result['meshes'].append({'name':obj.name,'positions':packed(vertex,'f'),'normals':packed(normal,'f'),'uv':packed(uv,'f'),'weights':packed(weights,'f'),'boneIndices':packed(indices,'H'),'parts':[{'material':obj.data.materials[i].name,'indices':packed(p,'I')} for i,p in enumerate(parts) if p]})
    rig.data.pose_position='POSE'
    for clip,(action,start,end,fps) in clips.items():
        rig.animation_data_create();rig.animation_data.action=action
        # Blender 4+ action slots must be assigned when switching imported actions.
        if hasattr(action,'slots') and len(action.slots): rig.animation_data.action_slot=action.slots[0]
        frames=[]
        native_frames=[]
        for frame in range(start,end+1):
            bpy.context.scene.frame_set(frame);bpy.context.view_layer.update()
            worlds=[norm @ rig.matrix_world @ rig.pose.bones[b.name].matrix for b in bones]
            poses=[]
            for i,b in enumerate(bones):
                parent=ids[b.parent.name] if b.parent else -1
                local=worlds[parent].inverted() @ worlds[i] if parent>=0 else worlds[i]
                loc,rot,scale=local.decompose()
                poses.append([*[round(x,6) for x in loc],round(rot.x,6),round(rot.y,6),round(rot.z,6),round(rot.w,6),*[round(x,6) for x in scale]])
            frames.append(poses)
            native_poses = [p[:] for p in poses]
            for i,b in enumerate(bones):
                if not b.parent:
                    loc,rot,scale=rig.pose.bones[b.name].matrix.decompose()
                    native_poses[i]=[*loc,rot.x,rot.y,rot.z,rot.w,*scale]
            native_frames.append(native_poses)
        result['clips'][clip]={'duration':(end-start)/fps,'frames':frames,'nativeFrames':native_frames}
    path=folder/(name+'.rig.json');path.write_text(json.dumps(result,separators=(',',':'))+'\n')
    rig.animation_data_clear();rig.data.pose_position='REST'
    bpy.context.scene.frame_set(0)
    # Preserve the complete hierarchy and bind transforms in the native USD export.
    root=bpy.data.objects.new(name+'AssetRoot',None);bpy.context.collection.objects.link(root)
    for obj in [rig]+objects:
        if obj.parent not in [rig]+objects:
            world=obj.matrix_world.copy();obj.parent=root;obj.matrix_world=world
    root.matrix_world=Matrix.Rotation(math.pi / 2, 4, 'X') @ norm
    return result,root
