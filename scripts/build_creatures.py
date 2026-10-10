"""Original Pocket Realm characters, sculpted and texture-painted in Blender 5.2.
Run with Blender --background --python scripts/build_creatures.py.
Exports editable packed .blend, Y-up meter-scale USDZs, GLBs and portraits.
"""
from pathlib import Path
import bpy
import math
import json
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'Art' / 'Creatures'
ASSETS = ROOT / 'PocketRealm' / 'Resources' / 'Creatures'
for folder in (ART, ASSETS, ART/'Textures'): folder.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 48
scene.cycles.use_denoising = True
scene.render.image_settings.file_format = 'PNG'
scene.view_settings.view_transform = 'AgX'
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1
# Keep generated backups out of the checked-in art directory.
bpy.context.preferences.filepaths.save_version = 0


def rgb(hexcolor):
    values = np.array([int(hexcolor[i:i+2],16)/255 for i in (0,2,4)])
    return np.where(values <= .04045, values/12.92, ((values+.055)/1.055)**2.4)


def mat(name, color, roughness=.45, emission=0, soft=0):
    color = rgb(color)
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color,1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color,1)
    p.inputs['Roughness'].default_value = roughness
    p.inputs['Subsurface Weight'].default_value = soft
    p.inputs['Subsurface Radius'].default_value = (.3,.15,.08)
    if emission:
        p.inputs['Emission Color'].default_value = (*color,1)
        p.inputs['Emission Strength'].default_value = emission
    return m

M = {k:mat(k,c,r,e) for k,c,r,e in [
    ('ink','163B36',.19,0),('shine','FFFDF3',.23,0),('cream','FFF1CB',.6,0),
    ('mint','63C798',.45,0),('mintLight','B4E7B4',.5,0),
    ('leaf','278960',.43,0),('leafLight','96C957',.46,0),('bag','BE874D',.64,0),
    ('seam','845C39',.63,0),('peach','EEA27A',.48,0),('apricot','DE815B',.5,0),
    ('wing','F6D091',.49,0),('glow','FFDB7F',.3,.35),
    ('lilac','AA93D0',.45,0),('shell','71619A',.36,0),
    ('teal','6ECDBD',.28,0),('floor','E8E5DB',.8,0)]}
active_root = None
bodies = {}


def finish(obj, name, material):
    obj.name = name
    if material: obj.data.materials.append(M[material])
    if obj.type == 'MESH':
        for p in obj.data.polygons: p.use_smooth = True
    if active_root: obj.parent = active_root
    return obj


def select_only(objects):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects: obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]


def orb(name, loc, scale, material=None, rotation=(0,0,0), segments=40, rings=28):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1, location=loc)
    o=bpy.context.object; o.scale=scale; o.rotation_euler=rotation
    return finish(o,name,material)


def line(name, points, radius, material=None):
    c=bpy.data.curves.new(name,'CURVE'); c.dimensions='3D'; c.resolution_u=10
    c.bevel_depth=radius; c.bevel_resolution=4; c.use_fill_caps=True
    s=c.splines.new('BEZIER'); s.bezier_points.add(len(points)-1)
    for p,co in zip(s.bezier_points,points):
        p.co=co; p.handle_left_type='AUTO'; p.handle_right_type='AUTO'
    o=bpy.data.objects.new(name,c); bpy.context.collection.objects.link(o)
    select_only([o]); bpy.ops.object.convert(target='MESH')
    return finish(bpy.context.object,name,material)


def apply_modifier(obj, modifier):
    select_only([obj]); bpy.ops.object.modifier_apply(modifier=modifier.name)


def connected_components(mesh):
    neighbors=[[] for _ in mesh.vertices]
    for edge in mesh.edges:
        a,b=edge.vertices; neighbors[a].append(b); neighbors[b].append(a)
    remaining=set(range(len(neighbors))); sizes=[]
    while remaining:
        pending=[remaining.pop()]; size=0
        while pending:
            v=pending.pop(); size+=1
            for n in neighbors[v]:
                if n in remaining: remaining.remove(n); pending.append(n)
        sizes.append(size)
    return sorted(sizes,reverse=True)


def sculpt(name, parts, voxel=.022, iterations=22, reduction=.20):
    """Fuse actual volumes, relax the joins, then subdivide the continuous surface."""
    select_only(parts)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.object.join(); obj=bpy.context.object; obj.name=name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    modifier=obj.modifiers.new('Fuse sculpt volumes','REMESH')
    modifier.mode='VOXEL'; modifier.voxel_size=voxel; modifier.use_smooth_shade=True
    apply_modifier(obj,modifier)
    modifier=obj.modifiers.new('Relax organic transitions','SMOOTH')
    modifier.factor=1.25; modifier.iterations=iterations
    apply_modifier(obj,modifier)
    modifier=obj.modifiers.new('Polish sculpt surface','SUBSURF'); modifier.levels=1
    apply_modifier(obj,modifier)
    modifier=obj.modifiers.new('Mobile surface budget','DECIMATE'); modifier.ratio=reduction
    apply_modifier(obj,modifier)
    obj.data.materials.clear()
    for poly in obj.data.polygons: poly.use_smooth=True
    parts=connected_components(obj.data)
    assert len(parts)==1, f'{name} is not a continuous sculpt: {parts}'
    obj['continuous_surface']=True
    print('SCULPT',name,len(obj.data.vertices),'vertices, one connected surface',flush=True)
    return obj


def mix(a,b,f): return a*(1-f[:,None])+b*f[:,None]
def mask(x,z,cx,cz,rx,rz): return np.exp(-(((x-cx)/rx)**2+((z-cz)/rz)**2)*2)


def paint(obj, kind, resolution=1024):
    """Bake positional paint into a portable image, so markings never float above skin."""
    xyz=np.array([v.co[:] for v in obj.data.vertices]); x,y,z=xyz.T
    front=np.clip(-y*8,0,1)
    if kind=='Mosskip':
        colors=np.tile(rgb('66BE8F'),(len(x),1))
        colors=mix(colors,rgb('C3E7AB'),mask(x,z,0,1.14,.64,.47)*front*.88)
        colors=mix(colors,rgb('F6E7B4'),mask(x,z,0,.61,.39,.35)*front*.95)
        colors=mix(colors,rgb('388E66'),np.clip((.33-z)*4,0,.7))
        face_z=1.00; cheeks=.41
    elif kind=='Glimlo':
        colors=np.tile(rgb('E89A70'),(len(x),1))
        colors=mix(colors,rgb('FFE1A5'),mask(x,z,0,.81,.38,.35)*front*.92)
        colors=mix(colors,rgb('F8C999'),mask(x,z,0,1.4,.58,.38)*front*.40)
        colors=mix(colors,rgb('FFE4A6'),mask(x,z,0,1.62,.12,.075)*front*.9)
        face_z=1.20; cheeks=.38
    elif kind=='Pebblin':
        colors=np.tile(rgb('B09BCC'),(len(x),1))
        colors=mix(colors,rgb('DFCCEA'),mask(x,z,0,1.01,.68,.57)*front*.85)
        colors=mix(colors,rgb('91CABC'),np.clip((z-1.42)*10,0,1))
        face_z=.89; cheeks=.37
    elif kind.startswith('wing'):
        ax=np.abs(x)
        colors=np.tile(rgb('EAC078'),(len(x),1))
        colors=mix(colors,rgb('F9DEAB'),mask(ax,z,.60,1.18,.8,.85)*.85)
        colors=mix(colors,rgb('D88E59'),mask(ax,z,.90,1.37,.29,.43)*.73)
        colors=mix(colors,rgb('FFF0C9'),mask(ax,z,.91,1.44,.10,.13)*.96)
        colors=mix(colors,rgb('D39172'),mask(ax,z,.81,.60,.22,.21)*.77)
        # Fine, softly painted branching membrane veins.
        vein=np.exp(-((ax-(.32+(1.5-z)*.60))/.017)**2)*np.clip((1.4-z)*2,0,.35)
        colors=mix(colors,rgb('B98151'),vein)
    elif kind=='shell':
        colors=np.tile(rgb('7D6AA4'),(len(x),1))
        colors=mix(colors,rgb('B8A0CE'),np.clip((z-.7)*.48,0,.45))
        centers=np.array(shell_spiral_points)
        distance=np.min(np.sum((xyz[:,None,:]-centers[None,:,:])**2,axis=2),axis=1)**.5
        colors=mix(colors,rgb('C6AFDA'),np.exp(-(distance/.07)**2)*.78)
    if kind in ('Mosskip','Glimlo','Pebblin'):
        blush=np.maximum(mask(x,z,-cheeks,face_z,.15,.085),mask(x,z,cheeks,face_z,.15,.085))*front
        colors=mix(colors,rgb('EA9C96'),blush*.76)
        # Very subtle pigment variation, not a bumpy procedural surface.
        grain=np.sin(x*171+z*93)*np.sin(y*87-z*137)
        colors*=1+grain[:,None]*.018
    colors=np.clip(colors,0,1)
    attr=obj.data.color_attributes.new(name='SkinPaint',type='FLOAT_COLOR',domain='POINT')
    rgba=np.column_stack((colors,np.ones(len(colors))))
    attr.data.foreach_set('color',rgba.ravel())
    select_only([obj]); bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=1.1519,island_margin=.015)
    bpy.ops.object.mode_set(mode='OBJECT')
    material=mat(kind+'_paint','FFFFFF',.49,soft=.065 if kind in bodies else .02)
    obj.data.materials.clear(); obj.data.materials.append(material)
    nodes=material.node_tree.nodes; links=material.node_tree.links
    p=nodes.get('Principled BSDF'); out=nodes.get('Material Output')
    color=nodes.new('ShaderNodeVertexColor'); color.layer_name='SkinPaint'
    emission=nodes.new('ShaderNodeEmission'); links.new(color.outputs['Color'],emission.inputs['Color'])
    links.new(emission.outputs[0],out.inputs['Surface'])
    image=bpy.data.images.new(kind+'_BaseColor',width=resolution,height=resolution)
    image.filepath_raw=str(ART/'Textures'/f'{kind}_BaseColor.png'); image.file_format='PNG'
    texture=nodes.new('ShaderNodeTexImage'); texture.image=image; nodes.active=texture
    scene.cycles.samples=1
    bpy.ops.object.bake(type='EMIT',margin=12,use_clear=True)
    image.save(); image.pack()
    links.new(p.outputs[0],out.inputs['Surface']); links.new(texture.outputs['Color'],p.inputs['Base Color'])
    nodes.remove(color); nodes.remove(emission)
    scene.cycles.samples=48
    # Display painting in Blender solid/material view as well.
    material.diffuse_color=(*np.mean(colors,axis=0),1)


def leaf(name, loc, length, width, material, angle=0):
    vertices=[(0,0,0)]; faces=[]; rows=28; cols=16
    for i in range(1,rows):
        t=i/rows; w=width*math.sin(math.pi*t)**.82
        for j in range(cols):
            a=j/cols*2*math.pi
            vertices.append((w*math.cos(a),-.12*math.sin(math.pi*t)+.055*math.sin(math.pi*t)*math.sin(a),length*t))
    tip=len(vertices); vertices.append((0,0,length))
    for j in range(cols): faces.append((0,1+(j+1)%cols,1+j))
    for i in range(rows-2):
        for j in range(cols):
            a=1+i*cols+j; b=1+i*cols+(j+1)%cols; faces.append((a,b,b+cols,a+cols))
    base=1+(rows-2)*cols
    for j in range(cols): faces.append((base+j,base+(j+1)%cols,tip))
    me=bpy.data.meshes.new(name); me.from_pydata(vertices,[],faces); me.update()
    o=bpy.data.objects.new(name,me); bpy.context.collection.objects.link(o)
    o.location=loc; o.rotation_euler[1]=angle; finish(o,name,material)
    modifier=o.modifiers.new('Silky leaf curvature','SUBSURF'); modifier.levels=1; apply_modifier(o,modifier)
    return o


def surface(body,x,z):
    tree=BVHTree.FromPolygons([v.co for v in body.data.vertices],[p.vertices[:] for p in body.data.polygons])
    loc,normal,_,_=tree.ray_cast(Vector((x,-3,z)),Vector((0,1,0)))
    assert loc is not None, f'Missing face surface {body.name} {(x,z)}'
    return loc,normal


def face(body,z,spacing=.245):
    for side in (-1,1):
        x=side*spacing; loc,normal=surface(body,x,z)
        eye=orb('eye_L' if side<0 else 'eye_R',loc+normal*.009,(.086,.040,.111),'ink')
        eye.rotation_euler=normal.to_track_quat('-Y','Z').to_euler()
        # Small intentional highlight embedded into the glossy eye surface.
        p=loc+normal*.044+Vector((-.021,0,.033))
        orb('eye_catchlight',p,(.019,.010,.024),'shine',segments=24,rings=16)
    points=[]
    for x,dz in ((-.09,-.166),(-.045,-.198),(0,-.21),(.045,-.198),(.09,-.166)):
        loc,n=surface(body,x,z+dz); points.append(loc+n*.006)
    line('gentle_smile',points,.011,'ink')


def rounded_box(name,loc,scale,material,bevel):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc)
    o=bpy.context.object; o.scale=scale; finish(o,name,material)
    select_only([o]); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    modifier=o.modifiers.new('Soft sewn corners','BEVEL'); modifier.width=bevel; modifier.segments=6; apply_modifier(o,modifier)
    modifier=o.modifiers.new('Weighted leather normals','WEIGHTED_NORMAL'); apply_modifier(o,modifier)
    return o


def make_mosskip():
    parts=[orb('torso',(0,0,.83),(.62,.44,.72))]
    for s in (-1,1):
        parts.append(orb('foot',(s*.28,-.06,.20),(.24,.31,.21)))
        parts.append(orb('arm',(s*.52,-.015,.71),(.205,.22,.36),rotation=(0,s*-.42,0)))
    body=sculpt('Mosskip_continuous_body',parts); bodies['Mosskip']=body; paint(body,'Mosskip')
    sprout=leaf('sprout_left',(-.06,.035,1.46),.74,.23,'leaf',-.63)
    leaf('sprout_right',(.075,.04,1.45),.59,.215,'leafLight',.68)
    bpy.context.view_layer.update()
    line('leaf_midrib',[sprout.matrix_world @ Vector((0,-.175*math.sin(math.pi*t)-.002,.74*t))
                       for t in (.12,.25,.4,.55,.7,.85)],.007,'mintLight')
    for s in (-1,1): leaf('shoulder_leaf',(s*.25,.15,1.04),.43,.15,'leaf',s*1.35)
    face(body,1.16)
    points=[]
    for x,z in ((-.45,.99),(-.32,.88),(-.10,.74),(.15,.64),(.40,.54)):
        loc,n=surface(body,x,z); points.append(loc+n*.029)
    line('seed_satchel_strap',points,.021,'seam')
    rounded_box('seed_satchel',(.43,-.40,.49),(.38,.21,.32),'bag',.10)
    rounded_box('satchel_fold',(.43,-.52,.59),(.36,.035,.14),'cream',.047)
    orb('sprout_clasp',(.43,-.55,.54),(.032,.014,.030),'leaf',segments=24,rings=16)


def make_wing(s):
    # Single scalloped, gently domed membrane, with no stacked oval inlays.
    segments=[
        ((.20,.95),(.20,1.37),(.58,1.87),(.91,1.84)),
        ((.91,1.84),(1.32,1.81),(1.37,1.25),(1.02,1.02)),
        ((1.02,1.02),(.94,.96),(.86,.93),(.91,.88)),
        ((.91,.88),(1.22,.61),(1.05,.31),(.79,.34)),
        ((.79,.34),(.50,.34),(.23,.52),(.20,.95))]
    contour=[]
    for ps in segments:
        ps=np.array(ps)
        for i in range(18):
            t=i/18; contour.append((1-t)**3*ps[0]+3*(1-t)**2*t*ps[1]+3*(1-t)*t*t*ps[2]+t**3*ps[3])
    center=np.array([.55,1.0]); vertices=[]; faces=[]; n=len(contour); rings=14
    # Latitude construction joins both sides at the shared outer edge.
    vertices.append((s*center[0],.11-.060,center[1]))
    for i in range(1,rings*2):
        a=math.pi*i/(rings*2); r=math.sin(a)
        for p in contour:
            q=center+(p-center)*r
            vertices.append((s*q[0],.11-.06*math.cos(a)+.075*(q[0]-.5)**2,q[1]))
    last=len(vertices); vertices.append((s*center[0],.11+.060,center[1]))
    for j in range(n): faces.append((0,1+j,1+(j+1)%n))
    for i in range(rings*2-2):
        for j in range(n):
            a=1+i*n+j; b=1+i*n+(j+1)%n; faces.append((a,a+n,b+n,b))
    start=1+(rings*2-2)*n
    for j in range(n): faces.append((start+j,last,start+(j+1)%n))
    me=bpy.data.meshes.new('wing_membrane'); me.from_pydata(vertices,[],faces); me.update()
    o=bpy.data.objects.new('wing_L' if s<0 else 'wing_R',me); bpy.context.collection.objects.link(o)
    finish(o,o.name,None); select_only([o]); bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT'); bpy.ops.mesh.normals_make_consistent(inside=False); bpy.ops.object.mode_set(mode='OBJECT')
    paint(o,'wing_L' if s<0 else 'wing_R')


def make_glimlo():
    parts=[orb('torso',(0,0,.75),(.38,.31,.60)),orb('head',(0,-.06,1.29),(.51,.37,.48))]
    for s in (-1,1):
        parts.append(orb('foot',(s*.19,-.08,.20),(.16,.23,.20)))
        parts.append(orb('paw',(s*.30,-.245,.74),(.15,.16,.30),rotation=(0,s*.47,0)))
        parts.append(line('antenna',[(s*.20,0,1.64),(s*.30,-.01,1.91),(s*.46,-.01,1.98)],.042))
    body=sculpt('Glimlo_continuous_body',parts,voxel=.017,iterations=16)
    bodies['Glimlo']=body; paint(body,'Glimlo'); face(body,1.36,.225)
    for s in (-1,1):
        make_wing(s)
        orb('antenna_lantern',(s*.46,-.01,1.98),(.070,.068,.091),'glow')
    line('lantern_handle',[(-.13,-.47,.58),(-.12,-.47,.76),(0,-.47,.81),(.12,-.47,.76),(.13,-.47,.58)],.022,'seam')
    orb('seed_lantern',(0,-.50,.47),(.19,.155,.21),'glow')
    orb('lantern_foot',(0,-.50,.28),(.14,.12,.035),'bag')
    orb('lantern_lid',(0,-.50,.65),(.14,.12,.035),'bag')
    for a in (-.8,.8):
        line('lantern_rib',[(math.sin(a)*.10,-.59,.30),(math.sin(a)*.18,-.635,.47),(math.sin(a)*.10,-.59,.64)],.009,'bag')


shell_spiral_points=[]
def make_pebblin():
    parts=[orb('tail',(0,.42,.25),(.46,.58,.22)),orb('torso',(0,-.13,.47),(.59,.52,.38)),orb('head',(0,-.42,.91),(.51,.37,.49))]
    for s in (-1,1):
        parts.append(orb('foot',(s*.39,-.34,.21),(.22,.29,.18)))
        parts.append(line('feeler',[(s*.26,-.40,1.23),(s*.32,-.40,1.44),(s*.37,-.40,1.55)],.063))
        parts.append(orb('feeler_tip',(s*.37,-.40,1.55),(.090,.078,.098)))
    body=sculpt('Pebblin_continuous_body',parts,voxel=.019,iterations=18)
    bodies['Pebblin']=body; paint(body,'Pebblin'); face(body,1.045,.225)
    shell=orb('shell_core',(0,.36,.94),(.67,.48,.66))
    for i in range(110):
        t=i/109; a=-2.1+t*math.pi*3.1; r=.53*(1-t)+.055*t
        y=.36+math.sin(a)*r*.72; z=.94+math.cos(a)*r
        x=.67*math.sqrt(max(.01,1-((y-.36)/.48)**2-((z-.94)/.66)**2))
        shell_spiral_points.append((x+.002,y,z))
    ridge=line('shell_growth_spiral',shell_spiral_points,.035)
    shell=sculpt('Pebblin_sculpted_shell',[shell,ridge],voxel=.014,iterations=5,reduction=.14); paint(shell,'shell')
    for x,y,z,sz in ((-.25,.30,1.51,.10),(0,.34,1.62,.13),(.24,.35,1.52,.09)):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1,location=(x,y,z))
        o=bpy.context.object; o.scale=(sz,sz,sz*1.65); finish(o,'dream_crystal','teal')
        select_only([o]); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        modifier=o.modifiers.new('Soft crystal edges','BEVEL'); modifier.width=.008; modifier.segments=3; apply_modifier(o,modifier)
        for p in o.data.polygons: p.use_smooth=False


roots=[]; stats={}
for name,builder in [('Mosskip',make_mosskip),('Glimlo',make_glimlo),('Pebblin',make_pebblin)]:
    bpy.ops.object.select_all(action='DESELECT')
    active_root=bpy.data.objects.new(name,None); bpy.context.collection.objects.link(active_root)
    builder(); root=active_root; root.scale=(.22,.22,.22)
    bpy.context.view_layer.update()
    select_only([root,*root.children])
    for obj in root.children:
        if obj.type=='MESH': obj.data.name=obj.name+'_Mesh'
    tri_count=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in root.children if o.type=='MESH')
    stats[name]={'triangles':tri_count,'meshes':len(root.children),'heightMeters':round(max((o.matrix_world @ Vector(c)).z for o in root.children for c in o.bound_box),3),'bodyConnectedComponents':len(connected_components(bodies[name].data)),'paintedBaseColor':True}
    bpy.ops.wm.usd_export(filepath=str(ASSETS/f'{name}.usdz'), selected_objects_only=True,
        export_animation=False, export_materials=True, generate_preview_surface=True,
        export_lights=False, export_cameras=False, convert_orientation=True,
        export_global_forward_selection='NEGATIVE_Z', export_global_up_selection='Y',
        export_custom_properties=False,export_mesh_colors=False)
    bpy.ops.export_scene.gltf(filepath=str(ART/f'{name}.glb'),export_format='GLB',use_selection=True,export_yup=True,export_animations=False)
    roots.append(root)
active_root=None

# Studio lighting and a warm, quiet ground plane. Geometry exports above exclude the studio.
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.006))
floor=bpy.context.object; floor.name='Studio_floor'; floor.data.materials.append(M['floor'])
world=scene.world; world.use_nodes=True
world.node_tree.nodes['Background'].inputs[0].default_value=(.55,.62,.65,1)
world.node_tree.nodes['Background'].inputs[1].default_value=.35

def light(name,loc,energy,size):
    d=bpy.data.lights.new(name,'AREA'); d.energy=energy; d.shape='DISK'; d.size=size
    o=bpy.data.objects.new(name,d); bpy.context.collection.objects.link(o); o.location=loc
    o.rotation_euler=(Vector((0,0,.2))-o.location).to_track_quat('-Z','Y').to_euler()
light('Key_softbox',(-1.2,-1.6,2.5),100,1.5)
light('Fill_softbox',(1.5,-.5,1.0),40,1.5)
light('Rim_softbox',(0,1.5,1.8),115,1.4)
c=bpy.data.cameras.new('Portrait_camera'); camera=bpy.data.objects.new('Portrait_camera',c); bpy.context.collection.objects.link(camera)
scene.camera=camera; c.type='ORTHO'; c.lens=50

def aim(loc,target,scale):
    camera.location=loc; camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler(); c.ortho_scale=scale

def visible(root, show):
    root.hide_render=not show
    for child in root.children: child.hide_render=not show

for root in roots: visible(root,False)
for root in roots:
    visible(root,True)
    aim((.68,-1.8,.88),(0,0,.23),.64)
    scene.render.resolution_x=640; scene.render.resolution_y=640; scene.render.resolution_percentage=100
    scene.render.filepath=str(ART/f'{root.name}.png')
    bpy.ops.render.render(write_still=True)
    # Store the same render in an asset catalog for the native character picker.
    import shutil
    folder=ROOT/'PocketRealm'/'Resources'/'Assets.xcassets'/f'{root.name}.imageset'
    folder.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(ART/f'{root.name}.png',folder/f'{root.name}.png')
    (folder/'Contents.json').write_text(json.dumps({'images':[{'filename':f'{root.name}.png','idiom':'universal'}],'info':{'author':'xcode','version':1}},indent=2)+'\n')
    visible(root,False)

for root,x in zip(roots,(-.65,0,.65)):
    visible(root,True); root.location.x=x
    # A little rotation lets the last friend's spiral shell read in the lineup.
    root.rotation_euler.z= -.22 if root.name=='Pebblin' else .06
scene.render.resolution_x=1800; scene.render.resolution_y=1000
scene.cycles.samples=48
aim((.70,-3.8,1.65),(0,0,.21),2.08)
scene.render.filepath=str(ART/'friends-lineup.png')
# Open the editable source on the composed camera view.
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == 'VIEW_3D':
            area.spaces.active.region_3d.view_perspective = 'CAMERA'
            area.spaces.active.shading.color_type = 'MATERIAL'
            area.spaces.active.overlay.show_overlays = False
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'PocketRealm-Friends.blend'))
bpy.ops.render.render(write_still=True)
(ART/'manifest.json').write_text(json.dumps(stats,indent=2)+'\n')
print('CREATURE_EXPORTS_COMPLETE',json.dumps(stats))
