"""Keyframe the exact Swift pose samples in Blender; render a small reaction reel.
First run scripts/export_motion_preview.swift as described in README.md.
The shipped USDZs use the same named controls, driven live by CreatureAnimator.
"""
from pathlib import Path
import bpy, json, math, subprocess, sys, shutil
from mathutils import Vector, Quaternion
ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'Art'/'Creatures'
bpy.ops.wm.open_mainfile(filepath=str(ART/'PocketRealm-Friends.blend'))
bpy.context.preferences.filepaths.save_version=0
scene=bpy.context.scene

def render_reel():
    scene.render.engine='CYCLES'
    scene.cycles.device='CPU'; scene.cycles.samples=4; scene.cycles.use_denoising=True
    scene.render.threads_mode='FIXED'; scene.render.threads=2
    scene.render.resolution_x=960; scene.render.resolution_y=360
    scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG'; scene.render.image_settings.color_mode='RGB'
    temporary=ROOT/'build'/'friend-preview-frame.png'
    scene.render.filepath=str(temporary)
    ffmpeg=shutil.which('ffmpeg') or '/opt/homebrew/bin/ffmpeg'
    output=ART/'friends-reactions.mp4'
    staging=ROOT/'build'/'friends-reactions.partial.mp4'
    command=[ffmpeg,'-y','-loglevel','error','-f','image2pipe','-vcodec','png','-r',str(scene.render.fps),'-i','-',
             '-c:v','libx264','-threads','2','-pix_fmt','yuv420p','-crf','21','-movflags','+faststart',str(staging)]
    process=subprocess.Popen(command,stdin=subprocess.PIPE)
    try:
        for frame in range(scene.frame_start,scene.frame_end+1):
            scene.frame_set(frame); bpy.ops.render.render(write_still=True)
            process.stdin.write(temporary.read_bytes())
            if frame % 12 == 0: print(f'REACTION_FRAME {frame}/{scene.frame_end}',flush=True)
    finally:
        process.stdin.close()
    assert process.wait()==0, 'Reaction video encoding failed'
    staging.replace(output)
    print('REACTION_PREVIEW_COMPLETE',flush=True)

if '--render-only' in sys.argv:
    render_reel(); sys.exit(0)

samples=json.loads((ROOT/'build'/'friend-motion-preview.json').read_text())
manifest=json.loads((ART/'manifest.json').read_text())
roots={name:bpy.data.objects[name] for name in manifest}
rest={o.name:(o.location.copy(),o.rotation_euler.to_quaternion(),o.scale.copy()) for root in roots.values() for o in [root,*root.children_recursive]}
particles={}

def material(name,color):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    shader=m.node_tree.nodes.get('Principled BSDF'); shader.inputs['Base Color'].default_value=(*color,1)
    shader.inputs['Roughness'].default_value=.45
    return m
hearts=material('Reaction_heart',(1,.21,.34)); stars=material('Reaction_star',(1,.68,.12))
for name,root in roots.items():
    particles[name]=[]
    for isheart in (True,False):
        count=40 if isheart else 10
        vertices=[(0,0,0)]
        for i in range(count):
            t=i*math.tau/count
            if isheart: x,z=math.sin(t)**3,(13*math.cos(t)-5*math.cos(2*t)-2*math.cos(3*t)-math.cos(4*t))/16
            else:
                r=1 if i%2==0 else .46; x,z=math.sin(t)*r,math.cos(t)*r
            vertices.append((x,0,z))
        faces=[(0,(i+1)%count+1,i+1) for i in range(count)]
        mesh=bpy.data.meshes.new('Heart' if isheart else 'Star'); mesh.from_pydata(vertices,[],faces); mesh.update()
        mesh.materials.append(hearts if isheart else stars)
        for i in range(7):
            o=bpy.data.objects.new(name+('_heart_' if isheart else '_star_')+str(i),mesh)
            bpy.context.collection.objects.link(o); o.parent=root
            particles[name].append((isheart,i,o))

basis=Quaternion((1,0,0),math.pi/2)
for frame in samples['frames']:
    f=frame['frame']
    for name,p in frame['friends'].items():
        root=roots[name]; loc,rot,scale=rest[name]
        pos=p['position']; angles=p['rotation']; sc=p['scale']
        root.location=loc+Vector((pos[0],-pos[2],pos[1]))
        q=Quaternion((0,1,0),angles[1]) @ Quaternion((1,0,0),angles[0]) @ Quaternion((0,0,1),angles[2])
        root.rotation_mode='QUATERNION'; root.rotation_quaternion=(basis @ q @ basis.inverted()) @ rot
        root.scale=Vector((scale.x*sc[0],scale.y*sc[2],scale.z*sc[1]))
        for path in ('location','rotation_quaternion','scale'): root.keyframe_insert(path,frame=f)
        for label in ('EyeL','EyeR','Mouth','AppendageL','AppendageR','Tail','Shell'):
            key=name+'__'+label
            if key not in bpy.data.objects: continue
            o=bpy.data.objects[key]; _,base_rotation,base_scale=rest[key]
            o.scale=base_scale; o.rotation_mode='QUATERNION'; o.rotation_quaternion=base_rotation
            if label in ('EyeL','EyeR'): o.scale.y *= max(.06,p['eyes'])
            elif label=='Mouth': o.scale.x *= 1+(p['mouth']-1)*.25; o.scale.y *= p['mouth']
            elif label.startswith('Appendage'):
                side=-1 if label.endswith('L') else 1
                axis=(0,1,0) if name=='Glimlo' else (0,0,1)
                o.rotation_quaternion=base_rotation @ Quaternion(axis,p['appendage']*side)
                if name=='Nibbi': o.rotation_quaternion @= Quaternion((1,0,0),p['appendage']*.4)
            elif label=='Tail': o.rotation_quaternion=base_rotation @ Quaternion((0,1,0),p['tail'])
            elif label=='Shell': o.rotation_quaternion=base_rotation @ Quaternion((0,0,1),p['tail']*.15)
            for path in ('rotation_quaternion','scale'): o.keyframe_insert(path,frame=f)
        for isheart,i,o in particles[name]:
            progress=(p['effectProgress']-i*.045)/.72
            enabled=p['effect']>0 and p['reaction']==('pet' if isheart else 'celebrate') and 0<progress<1
            if enabled:
                a=i*math.tau/7; spread=.13 if isheart else .23
                # Root is 0.22 scale in Blender; the live effect meshes use meter coordinates.
                o.location=(math.cos(a)*spread*(.5+progress)/.22,-(.14+math.sin(a)*.06)/.22,
                            (manifest[name]['heightMeters']*.75+progress*.22+math.sin(a)*.055)/.22)
                o.scale=(max(.00001,math.sin(progress*math.pi)*(.020 if isheart else .016))/.22,)*3
            else: o.scale=(.00001,)*3
            o.keyframe_insert('location',frame=f); o.keyframe_insert('scale',frame=f)

scene.render.fps=samples['fps']; scene.frame_start=1; scene.frame_end=len(samples['frames'])
for frame,label in ((1,'Arrive'),(19,'Hello'),(49,'Pet'),(75,'Play'),(117,'Quest complete')):
    scene.timeline_markers.new(label,frame=frame)
scene.frame_set(30)
# Leave the editable source showing the complete roster, with a playable timeline.
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'PocketRealm-Friends.blend'))
render_reel()
