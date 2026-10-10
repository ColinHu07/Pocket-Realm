"""Original Pocket Realm characters. Run with Blender 4.5 in background mode.
Exports editable .blend sources, Y-up meter-scale USDZs, GLBs and studio portraits.
No third-party models, textures, fonts, or character references are used.
"""
from pathlib import Path
import bpy
import math
import json
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'Art' / 'Creatures'
ASSETS = ROOT / 'PocketRealm' / 'Resources' / 'Creatures'
for folder in (ART, ASSETS): folder.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 48
scene.cycles.use_denoising = True
scene.render.image_settings.file_format = 'PNG'
scene.view_settings.view_transform = 'AgX'
scene.world.color = (0.22, 0.22, 0.22)
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1


def mat(name, hexcolor, roughness=.48, emission=0):
    rgb = tuple(int(hexcolor[i:i+2],16)/255 for i in (0,2,4))
    # Hex palette is sRGB; shader inputs are linear.
    rgb = tuple(c / 12.92 if c <= .04045 else ((c+.055)/1.055)**2.4 for c in rgb)
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb,1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*rgb,1)
    p.inputs['Roughness'].default_value = roughness
    if emission:
        p.inputs['Emission Color'].default_value = (*rgb,1)
        p.inputs['Emission Strength'].default_value = emission
    return m

M = {k:mat(k,c,r,e) for k,c,r,e in [
    ('ink','243F43',.27,0),('shine','FFFDF3',.26,0),('cream','FFF1CB',.6,0),
    ('blush','F39791',.6,0),('mint','81D6AE',.5,0),('mintLight','B5E8B9',.6,0),
    ('leaf','389F7B',.48,0),('leafLight','B7D979',.5,0),('bag','DDB373',.68,0),
    ('seam','8A6650',.6,0),('peach','F6AF81',.5,0),('apricot','EE865D',.6,0),
    ('wing','FFDC9C',.6,0),('wingSpot','F8B96A',.5,0),('glow','FFE7A0',.35,.25),
    ('lilac','B7A4D9',.5,0),('paleLilac','DACBEA',.6,0),('shell','746C9E',.55,0),
    ('shellRidge','D1BAE3',.5,0),('teal','81D9CD',.4,0),('floor','F3ECDD',.8,0),
    ('plinth','E3DAC8',.7,0)]}

active_root = None

def finish(obj, name, material):
    obj.name = name
    if material: obj.data.materials.append(M[material])
    if obj.type == 'MESH':
        for p in obj.data.polygons: p.use_smooth = True
    if active_root: obj.parent = active_root
    return obj


def orb(name, loc, scale, material, rotation=(0,0,0), segments=24, rings=16):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1, location=loc)
    o=bpy.context.object
    o.scale=scale
    o.rotation_euler=rotation
    return finish(o,name,material)


def line(name, points, radius, material):
    c=bpy.data.curves.new(name,'CURVE'); c.dimensions='3D'; c.resolution_u=8
    c.bevel_depth=radius; c.bevel_resolution=3
    s=c.splines.new('BEZIER'); s.bezier_points.add(len(points)-1)
    for p,co in zip(s.bezier_points,points):
        p.co=co; p.handle_left_type='AUTO'; p.handle_right_type='AUTO'
    o=bpy.data.objects.new(name,c); bpy.context.collection.objects.link(o)
    bpy.context.view_layer.objects.active=o; o.select_set(True)
    bpy.ops.object.convert(target='MESH'); o.select_set(False)
    return finish(o,name,material)


def leaf(name, loc, length, width, material, angle=0):
    # Closed, softly ridged leaf with tapered tip and a generous cartoon silhouette.
    vertices=[]; faces=[]; rows=12; cols=10
    for i in range(rows+1):
        t=i/rows; w=width * math.sin(math.pi*t)**.8
        for j in range(cols):
            a=j/cols*2*math.pi
            vertices.append((w*math.cos(a), .10*math.sin(math.pi*t)*math.sin(a), length*t))
    for i in range(rows):
        for j in range(cols):
            a=i*cols+j; b=i*cols+(j+1)%cols
            faces.append((a,b,b+cols,a+cols))
    me=bpy.data.meshes.new(name); me.from_pydata(vertices,[],faces); me.update()
    o=bpy.data.objects.new(name,me); bpy.context.collection.objects.link(o)
    o.location=loc; o.rotation_euler[1]=angle
    return finish(o,name,material)


def face(z, front, spacing=.245, blush=True):
    for side in (-1,1):
        x=side*spacing
        orb('eye_L' if side<0 else 'eye_R',(x,front,z),(.092,.048,.122),'ink')
        orb('eye_glint',(x-.022,front-.045,z+.036),(.027,.018,.032),'shine',segments=16,rings=10)
        orb('eye_glint_small',(x+.027,front-.043,z-.038),(.012,.012,.015),'shine',segments=12,rings=8)
        if blush: orb('cheek',(side*(spacing+.15),front+.055,z-.145),(.112,.035,.053),'blush')
    line('smile',[(-.095,front-.009,z-.17),(0,front-.032,z-.215),(.095,front-.009,z-.17)],.018,'ink')


def make_mosskip():
    orb('body',(0,0,.80),(.62,.43,.70),'mint')
    orb('face_mask',(0,-.322,1.05),(.51,.16,.40),'mintLight')
    orb('tummy',(0,-.396,.55),(.29,.06,.29),'cream')
    for s in (-1,1):
        orb('foot',(s*.29,-.08,.16),(.23,.32,.15),'leaf')
        orb('arm',(s*.61,-.025,.70),(.16,.19,.34),'mint',rotation=(0,s*-.48,0))
        leaf('leaf_cape',(s*.15,.13,.88),.59,.20,'leaf',s*1.15)
    leaf('sprout_left',(-.07,0,1.39),.78,.235,'leaf',-.65)
    leaf('sprout_right',(.06,.025,1.39),.60,.22,'leafLight',.7)
    line('sprout_vein',[(-.10,-.067,1.50),(-.25,-.08,1.76),(-.45,-.02,1.96)],.015,'mintLight')
    face(1.105,-.487)
    # A seed satchel, with a sewn flap and a tiny sprout clasp.
    line('satchel_strap',[(-.45,-.29,1.23),(-.12,-.49,.90),(.40,-.40,.55)],.033,'seam')
    orb('satchel',(.42,-.37,.46),(.255,.13,.235),'bag')
    orb('satchel_flap',(.42,-.49,.55),(.23,.035,.12),'cream')
    orb('satchel_button',(.42,-.529,.49),(.037,.018,.037),'leaf')
    for x,z in ((-.14,.49),(-.06,.37),(.02,.49)):
        orb('tummy_seed',(x,-.458,z),(.021,.013,.037),'bag',rotation=(0,.25,0),segments=12,rings=8)


def make_glimlo():
    # Four petal wings give a moth-like silhouette without insect realism.
    for s in (-1,1):
        orb('upper_wing_L' if s<0 else 'upper_wing_R',(s*.66,.16,1.23),(.49,.13,.69),'wing',rotation=(0,s*.58,0))
        orb('lower_wing',(s*.64,.18,.65),(.39,.13,.40),'wing',rotation=(0,s*-.42,0))
        orb('wing_inlay',(s*.79,.012,1.34),(.235,.028,.39),'wingSpot',rotation=(0,s*.58,0))
        orb('wing_dot',(s*.87,-.007,1.43),(.081,.019,.10),'cream')
        orb('lower_wing_inlay',(s*.75,.03,.60),(.17,.025,.17),'apricot')
    orb('body',(0,0,.74),(.40,.34,.62),'apricot')
    orb('head',(0,-.08,1.29),(.52,.39,.46),'peach')
    for i in range(7):
        a=i/6*math.pi
        orb('fluff_collar',(.40*math.cos(a),-.22,.96-.10*math.sin(a)),(.13,.14,.13),'cream')
    face(1.32,-.447,spacing=.225)
    orb('forehead_moon',(0,-.425,1.57),(.10,.035,.082),'cream')
    for s in (-1,1):
        line('antenna',[(s*.20,0,1.65),(s*.32,-.01,1.93),(s*.49,-.03,1.98)],.027,'apricot')
        orb('antenna_lamp',(s*.49,-.03,1.99),(.092,.075,.114),'glow')
        orb('foot',(s*.20,-.08,.15),(.15,.23,.14),'peach')
        orb('arm',(s*.33,-.37,.73),(.12,.13,.25),'peach',rotation=(0,s*.55,0))
    # A warm seed lantern carried between its paws.
    line('lantern_handle',[(-.13,-.51,.57),(-.13,-.51,.80),(0,-.51,.86),(.13,-.51,.80),(.13,-.51,.57)],.025,'seam')
    orb('lantern',(0,-.52,.47),(.21,.18,.23),'glow')
    orb('lantern_base',(0,-.52,.27),(.16,.14,.045),'bag')
    orb('lantern_lid',(0,-.52,.67),(.15,.14,.044),'bag')
    leaf('lantern_spark',(0,-.705,.43),.12,.045,'shine',.2)


def make_pebblin():
    orb('tail',(0,.44,.27),(.49,.59,.21),'lilac')
    orb('body',(0,-.17,.50),(.60,.54,.40),'lilac')
    orb('head',(0,-.43,.90),(.52,.38,.48),'paleLilac')
    orb('chin',(0,-.56,.62),(.40,.21,.20),'lilac')
    # Shell is a tilted smooth pebble with a real raised spiral on its side.
    orb('shell',(0,.36,.91),(.67,.46,.67),'shell')
    points=[]
    for i in range(80):
        a=-math.pi*.4+i/79*math.pi*3.8
        r=.47*(1-i/91)
        points.append((.58+.06*(1-r/.47),.34+math.cos(a)*r,.92+math.sin(a)*r))
    line('shell_spiral',points,.051,'shellRidge')
    for s in (-1,1):
        orb('foot',(s*.42,-.38,.21),(.20,.30,.16),'paleLilac')
        line('feeler',[(s*.26,-.40,1.20),(s*.32,-.42,1.43),(s*.38,-.42,1.52)],.056,'lilac')
        orb('feeler_tip',(s*.38,-.42,1.52),(.093,.073,.102),'teal')
    face(.96,-.79,spacing=.225)
    for x,y,z,sz in ((-.28,.30,1.46,.13),(0,.34,1.59,.16),(.27,.35,1.47,.12)):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1,location=(x,y,z))
        o=bpy.context.object; o.scale=(sz,sz,sz*1.6); finish(o,'dream_crystal','teal')
        for p in o.data.polygons: p.use_smooth=False
    for x,y,z in ((-.46,-.44,.49),(-.51,-.28,.53),(.45,-.43,.48)):
        orb('freckle',(x,y,z),(.029,.025,.021),'cream',segments=12,rings=8)


roots=[]; stats={}
for name,builder in [('Mosskip',make_mosskip),('Glimlo',make_glimlo),('Pebblin',make_pebblin)]:
    bpy.ops.object.select_all(action='DESELECT')
    active_root=bpy.data.objects.new(name,None)
    bpy.context.collection.objects.link(active_root)
    builder()
    root=active_root
    root.scale=(.22,.22,.22)
    bpy.ops.object.select_all(action='DESELECT')
    root.select_set(True)
    for child in root.children: child.select_set(True)
    bpy.context.view_layer.objects.active=root
    tri_count=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in root.children if o.type=='MESH')
    stats[name]={'triangles':tri_count,'meshes':len(root.children),'heightMeters':round(max((o.matrix_world @ Vector(c)).z for o in root.children for c in o.bound_box),3)}
    bpy.ops.wm.usd_export(filepath=str(ASSETS/f'{name}.usdz'), selected_objects_only=True,
        export_animation=False, export_materials=True, generate_preview_surface=True,
        export_lights=False, export_cameras=False, convert_orientation=True,
        export_global_forward_selection='NEGATIVE_Z', export_global_up_selection='Y',
        export_custom_properties=False)
    bpy.ops.export_scene.gltf(filepath=str(ART/f'{name}.glb'),export_format='GLB',use_selection=True,export_yup=True,export_animations=False)
    roots.append(root)
    root.hide_render=True
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
light('Key_softbox',(-1.2,-1.6,2.5),130,2)
light('Fill_softbox',(1.5,-.5,1.0),65,1.5)
light('Rim_softbox',(0,1.5,1.8),180,1.4)
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
scene.cycles.samples=64
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
