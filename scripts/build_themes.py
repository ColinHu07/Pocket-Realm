"""Original wall-mounted Reef, Cavern and Woodland assets, authored in Blender.
Run: Blender --background --threads 2 --python scripts/build_themes.py
USDZ coordinates: meters, Y-up, wall at Z=0, geometry protrudes toward +Z.
"""
from pathlib import Path
import bpy
import math
import random
import json
import os
import shutil
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'Art' / 'Themes'
ASSETS = ROOT / 'PocketRealm' / 'Resources' / 'Themes'
for folder in (ART, ART / 'Textures', ASSETS): folder.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version = 0
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'; scene.unit_settings.scale_length = 1
scene.render.engine = 'CYCLES'; scene.cycles.samples = 32; scene.cycles.use_denoising = True
scene.render.threads_mode = 'FIXED'; scene.render.threads = 2
scene.render.image_settings.file_format = 'PNG'; scene.view_settings.view_transform = 'AgX'
parts = []
rng = random.Random(38)


def rgb(hex):
    c = np.array([int(hex[i:i+2], 16) / 255 for i in (0, 2, 4)])
    return np.where(c <= .04045, c / 12.92, ((c + .055) / 1.055) ** 2.4)


def mat(name, color, rough=.65, metal=0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    m.diffuse_color = (*rgb(color), 1)
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = m.diffuse_color
    p.inputs['Roughness'].default_value = rough
    p.inputs['Metallic'].default_value = metal
    return m


def texture_material(name, dark, light, style, rough=.75):
    m = mat(name, dark, rough)
    size = 1024
    v, u = np.mgrid[0:size, 0:size].astype(np.float32) / size
    # Smooth, tileable value noise avoids the crosshatch of summed sine waves.
    noise = np.zeros_like(u)
    random_grid = np.random.default_rng(79)
    for freq, amplitude in [(5, .5), (13, .3), (37, .16), (113, .09), (251, .04)]:
        grid = random_grid.random((freq, freq), dtype=np.float32) - .5
        x, y = u*freq, v*freq
        ix, iy = x.astype(int), y.astype(int)
        fx, fy = x-ix, y-iy
        fx, fy = fx*fx*(3-2*fx), fy*fy*(3-2*fy)
        low = grid[iy % freq, ix % freq]*(1-fx) + grid[iy % freq, (ix+1) % freq]*fx
        high = grid[(iy+1) % freq, ix % freq]*(1-fx) + grid[(iy+1) % freq, (ix+1) % freq]*fx
        noise += amplitude*(low*(1-fy)+high*fy)
    if style == 'bark':
        wave = np.sin((u * 21 + .26 * np.sin(v * 15) + .18 * noise) * math.tau)
        value = .48 + .25 * wave + .38 * noise
        value -= .22 * np.exp(-((wave + .8) / .15)**2)
    elif style == 'shelf':
        value = .5 + .25 * np.sin((v * 12 + .14 * np.sin(u*11)) * math.tau) + noise*.25
        value = np.where(v > .87, .88 + noise*.12, value)
    elif style == 'kelp':
        value = .42 + .10 * np.cos((u-.5)*math.tau) + .025*np.sin(u*85) + noise*.32
    elif style == 'sponge':
        pores = np.maximum(0, np.sin(u*153+np.sin(v*91))*np.cos(v*157)) ** 6
        value = .57 + noise*.55 - pores*.27
    else:
        value = .5 + noise
    value = np.clip(value, .03, .97)
    c = np.array([int(dark[i:i+2], 16)/255 for i in (0, 2, 4)])
    d = np.array([int(light[i:i+2], 16)/255 for i in (0, 2, 4)])
    color = c + value[..., None] * (d-c)
    color = np.where(color <= .04045, color / 12.92, ((color + .055) / 1.055) ** 2.4)
    def image(name, pixels, noncolor=False):
        im = bpy.data.images.new(name, width=size, height=size, alpha=False)
        if noncolor: im.colorspace_settings.name = 'Non-Color'
        im.pixels.foreach_set(np.dstack((pixels, np.ones_like(u))).astype(np.float32).ravel())
        im.filepath_raw = str(ART / 'Textures' / (name+'.png')); im.file_format='PNG'; im.save(); im.pack()
        return im
    node = m.node_tree.nodes.new('ShaderNodeTexImage'); node.image = image(name+'_color', color)
    p = m.node_tree.nodes.get('Principled BSDF')
    m.node_tree.links.new(node.outputs['Color'], p.inputs['Base Color'])
    dv, du = np.gradient(value)
    normal = np.dstack((-du*9, -dv*9, np.ones_like(u)))
    normal /= np.linalg.norm(normal, axis=2)[..., None]
    n = m.node_tree.nodes.new('ShaderNodeTexImage'); n.image = image(name+'_normal', normal*.5+.5, True)
    converter = m.node_tree.nodes.new('ShaderNodeNormalMap')
    m.node_tree.links.new(n.outputs['Color'], converter.inputs['Color'])
    m.node_tree.links.new(converter.outputs['Normal'], p.inputs['Normal'])
    return m


M = {
    'limestone': texture_material('Reef_limestone','5A6258','B3B29C','stone'),
    'coral': texture_material('Rose_gorgonian','874C43','DCA183','sponge',.62),
    'sponge': texture_material('Ochre_sponge','725527','C8A86A','sponge',.8),
    'spongeInside': mat('Sponge_inner_cavity','645138',.9),
    'kelp': texture_material('Golden_kelp','3C4626','93A660','kelp',.48),
    'basalt': texture_material('Weathered_basalt','252832','65666D','stone',.86),
    'ore': texture_material('Copper_ore','384C46','829E87','stone',.78),
    'bark': texture_material('Old_bark','302A22','8F8067','bark',.87),
    'shelf': texture_material('Turkey_tail_rings','624331','D9BF92','shelf',.76),
    'moss': texture_material('Moss_lichen','334334','879460','stone',.91),
    'fern': texture_material('Woodland_fronds','254133','749353','kelp',.58),
    'pearl': mat('Oyster_cap','C7C0A8',.65), 'gill': mat('Ivory_gills','A59D86',.84),
    'amethyst': mat('Amethyst','72628E',.17,.18), 'amethystPale': mat('Amethyst_pale','A89DB9',.20,.12),
    'quartz': mat('Smoky_quartz','B8BCB8',.17,.22), 'quartzDark': mat('Smoky_quartz_shadow','747C78',.21,.12),
    'copper': mat('Native_copper','A87848',.35,.72),
}


def select(objects):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects: obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]


def finish(obj, name, material, smooth=True):
    obj.name = name; obj.data.materials.append(M[material])
    if obj.type == 'MESH':
        for p in obj.data.polygons: p.use_smooth=smooth
    parts.append(obj)
    return obj


def mesh(name, vertices, faces, material, uv=None, smooth=True):
    data = bpy.data.meshes.new(name); data.from_pydata(vertices, [], faces); data.update()
    obj = bpy.data.objects.new(name, data); bpy.context.collection.objects.link(obj)
    if uv:
        layer = data.uv_layers.new(name='UVMap')
        for loop in data.loops: layer.data[loop.index].uv=uv[loop.vertex_index]
    return finish(obj, name, material, smooth)


def tube(name, points, radius, material, taper=.4, detail=2):
    curve = bpy.data.curves.new(name, 'CURVE'); curve.dimensions='3D'
    curve.resolution_u=4 if detail > 1 else 3; curve.bevel_resolution=detail; curve.bevel_depth=radius; curve.use_fill_caps=True
    spline=curve.splines.new('BEZIER'); spline.bezier_points.add(len(points)-1)
    for i,(p,co) in enumerate(zip(spline.bezier_points,points)):
        p.co=co; p.handle_left_type='AUTO'; p.handle_right_type='AUTO'; p.radius=1-taper*i/max(1,len(points)-1)
    obj=bpy.data.objects.new(name,curve); bpy.context.collection.objects.link(obj); select([obj])
    bpy.ops.object.convert(target='MESH'); finish(obj,name,material)


def fine_branch(name, points, radius, taper=.4):
    """Smooth-shaded six-sided microbranches; dense coral stays within the phone budget."""
    verts=[]; faces=[]; uv=[]; points=[Vector(p) for p in points]
    for i,p in enumerate(points):
        tangent=(points[min(i+1,len(points)-1)]-points[max(0,i-1)]).normalized()
        across=tangent.cross(Vector((0,1,0))).normalized(); other=tangent.cross(across)
        for j in range(6):
            angle=j/6*math.tau; r=radius*(1-taper*i/(len(points)-1))
            verts.append(p+(across*math.cos(angle)+other*math.sin(angle))*r)
            uv.append((j/6,i/(len(points)-1)))
        if i:
            for j in range(6): faces.append(((i-1)*6+j,(i-1)*6+(j+1)%6,i*6+(j+1)%6,i*6+j))
    mesh(name,verts,faces,'coral',uv)


def rock(center, scale, material='basalt', seed=3):
    r=random.Random(seed)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=18, radius=1)
    obj=bpy.context.object
    for v in obj.data.vertices:
        co=v.co.copy(); distort=1+.045*math.sin(co.x*11+co.z*6)+r.uniform(-.018,.018)
        v.co=Vector(center)+Vector((co.x*scale[0],co.y*scale[1],co.z*scale[2]))*distort
        v.co.y=min(-.002,v.co.y)
    return finish(obj,'Weathered_substrate',material)


def blade(start, tip, width, material='kelp', ruffle=.1, segments=18):
    start,tip=Vector(start),Vector(tip); axis=tip-start
    across=axis.cross(Vector((0,-1,0))).normalized(); forward=across.cross(axis).normalized()
    verts,uv,faces=[],[],[]; cols=6
    for i in range(segments+1):
        t=i/segments
        center=start+axis*t+forward*(math.sin(t*math.pi)*axis.length*.10)
        if material == 'kelp':
            center += across*math.sin(t*math.tau)*axis.length*.10
            center += forward*math.sin(t*math.pi*2.4)*axis.length*.06
        for j in range(cols+1):
            s=j/cols*2-1
            w=width*max(.01,math.sin(math.pi*t)**(.35 if material == 'kelp' else .7))
            point=center+across*s*w+forward*w*(.18*(1-abs(s))+ruffle*math.sin(t*32)*s*s)
            verts.append(point); uv.append((j/cols,t))
    for i in range(segments):
        for j in range(cols):
            a=i*(cols+1)+j; faces.append((a,a+1,a+cols+2,a+cols+1))
    obj=mesh('Curled_blade',verts,faces,material,uv)
    select([obj]); mod=obj.modifiers.new('Leaf_thickness','SOLIDIFY'); mod.thickness=.0008
    bpy.ops.object.modifier_apply(modifier=mod.name)


def reef_fan():
    rock((0,-.032,-.50),(.18,.05,.10),'limestone')
    # A reticulated fan with tapering wavy rays and an irregular fine branch network.
    rays=[]
    for branch in range(25):
        angle=-1.03+branch*.086+rng.uniform(-.01,.01)
        reach=.50+rng.uniform(-.025,.035)
        root=Vector((0,-.055,-.50)); points=[]
        for j in range(15):
            t=j/14
            points.append(root+Vector((math.sin(angle)*.34*t+.006*math.sin(j*2+branch)*t,
                -.028*t+.009*math.sin(j+branch)*t,math.cos(angle)*reach*t)))
        fine_branch('Sea_fan_ray',points,.0034,.60)
        rays.append(points)
    for i in range(24):
        for j in range(2,15):
            a,b=rays[i][j],rays[i+1][j]
            mid=a.lerp(b,.5)+Vector((.004*rng.uniform(-1,1),-.006,rng.uniform(-.012,.012)))
            fine_branch('Organic_fan_lattice',[a,mid,b],.0016,.12)
            if j<14 and (i+j)%3!=0:
                c=rays[i+1][j+1]
                fine_branch('Fine_fan_network',[mid,mid.lerp(c,.5)+Vector((-.004,0,.004)),c],.0011,.3)
    for i in range(6):
        rock((rng.uniform(-.13,.13),-.074,-.5+rng.uniform(-.04,.03)),(.035,.013,.025),'limestone',i)


def sponge_tube(base, radius, length, lean):
    base=Vector(base); verts=[]; uv=[]; faces=[]; rings=14; sides=32
    # One continuous profile: outer wall, rounded lip, inner wall, bowl-shaped hollow.
    profile=[(t/rings,1+.035*math.sin(t*1.3)) for t in range(rings+1)]
    profile += [(1.008,.91),(1.005,.78),(.985,.69),(.9,.66),(.6,.52),(.22,.24),(.15,.02)]
    for i,(t,r) in enumerate(profile):
        center=base+Vector((lean*t*t,-.025*t,length*t))
        for j in range(sides):
            a=j/sides*math.tau
            rr=radius*r*(1+.045*math.sin(a*5+t*8))
            verts.append(center+Vector((rr*math.cos(a),rr*math.sin(a),0)))
            uv.append((j/sides,t))
    for i in range(len(profile)-1):
        for j in range(sides):
            a=i*sides+j; b=i*sides+(j+1)%sides
            faces.append((a,b,b+sides,a+sides))
    obj=mesh('Hollow_tube_sponge',verts,faces,'sponge',uv)
    obj.data.materials.append(M['spongeInside'])
    for face in obj.data.polygons:
        if face.index >= (rings+3)*sides: face.material_index=1


def reef_sponges():
    rock((0,-.035,-.49),(.22,.05,.11),'limestone',8)
    for x,y,r,h,lean in [(-.13,-.08,.044,.27,-.02),(-.065,-.10,.055,.39,-.03),(.055,-.08,.063,.47,.025),(.14,-.105,.045,.28,.04),(0,-.16,.052,.24,-.03)]:
        sponge_tube((x,y,-.49),r,h,lean)


def reef_kelp():
    rock((0,-.035,-.63),(.19,.05,.11),'limestone',12)
    for i in range(8):
        x=(i-3.5)*.023
        root=Vector((x,-.065,-.63)); tip=Vector((x+rng.uniform(-.14,.14),-.085-rng.random()*.06,-rng.uniform(.04,.28)))
        tube('Kelp_stipe',[root,root.lerp(tip,.06),root.lerp(tip,.12)],.003,'kelp')
        blade(root,tip,.026+rng.random()*.017,ruffle=.30)
    sponge_tube((.12,-.07,-.59),.026,.12,.015)


def crystal(base, tip, radius, material):
    base,tip=Vector(base),Vector(tip); axis=tip-base; n=axis.normalized()
    u=n.cross(Vector((0,0,1)) if abs(n.z)<.9 else Vector((1,0,0))).normalized(); v=n.cross(u)
    verts=[]
    for t,r in [(0,radius*.82),(.73,radius),(1,radius*.035)]:
        for i in range(6):
            a=i/6*math.tau
            verts.append(base+axis*t+(u*math.cos(a)+v*math.sin(a))*r)
    faces=[tuple(reversed(range(6)))]
    for row in range(2):
        for i in range(6): faces.append((row*6+i,row*6+(i+1)%6,(row+1)*6+(i+1)%6,(row+1)*6+i))
    faces.append(tuple(range(12,18)))
    obj=mesh('Prismatic_crystal',verts,faces,material,smooth=False)
    select([obj]); bevel=obj.modifiers.new('Fine_crystal_edges','BEVEL'); bevel.width=.0009; bevel.segments=2
    bpy.ops.object.modifier_apply(modifier=bevel.name)


def geode():
    # Open elliptical mineral pocket: rim and cavity are real geometry, with UV stone grain.
    verts=[]; uv=[]; faces=[]; sides=64
    profile=[(.99,-.012),(1.02,-.074),(.94,-.125),(.77,-.117),(.64,-.06),(.34,-.025),(.01,-.022)]
    for j,(r,y) in enumerate(profile):
        for i in range(sides):
            a=i/sides*math.tau; wobble=1+.045*math.sin(a*7)+.035*math.cos(a*11)
            verts.append((math.cos(a)*.245*r*wobble,y+.008*math.sin(a*9)*r,-.28+math.sin(a)*.275*r*wobble)); uv.append((i/sides,j/6))
    for j in range(len(profile)-1):
        for i in range(sides):
            a=j*sides+i; b=j*sides+(i+1)%sides; faces.append((a,b,b+sides,a+sides))
    mesh('Broken_geode_shell',verts,faces,'basalt',uv)
    for i in range(101):
        a=rng.random()*math.tau; radius=math.sqrt(rng.random())*.7
        x=math.cos(a)*.245*radius; z=-.28+math.sin(a)*.275*radius
        base=Vector((x,-.025-.065*radius*radius,z))
        tip=base+Vector((rng.uniform(-.02,.02),-rng.uniform(.04,.09),rng.uniform(.035,.085)))
        crystal(base,tip,rng.uniform(.010,.020),'amethyst' if i%3 else 'amethystPale')


def quartz_cluster():
    rock((0,-.048,-.28),(.24,.07,.27),'basalt',14)
    for i in range(28):
        base=Vector((rng.uniform(-.16,.16),-.095,rng.uniform(-.45,-.15)))
        tip=base+Vector((rng.uniform(-.05,.05),-rng.uniform(.05,.105),rng.uniform(.035,.17)))
        crystal(base,tip,rng.uniform(.012,.026),'quartz' if i%4 else 'quartzDark')


def copper_outcrop():
    rock((0,-.049,-.29),(.23,.07,.27),'basalt',19)
    for i in range(12):
        x=rng.uniform(-.17,.17); z=rng.uniform(-.48,-.11)
        rock((x,-.10,z),(.045,.026,.05),'ore',30+i)
    for i in range(18):
        x=rng.uniform(-.15,.15); z=rng.uniform(-.47,-.11)
        def face_y(x,z): return -.049-.07*math.sqrt(max(.05,1-(x/.23)**2-((z+.29)/.27)**2))-.005
        tube('Copper_vein',[(x,face_y(x,z),z),(x+.025,face_y(x+.025,z+.02),z+.02),(x+.017,face_y(x+.017,z+.04),z+.04)],.002,'copper',.25)
        bpy.ops.mesh.primitive_cube_add(size=1,location=(x,face_y(x,z)-.004,z))
        obj=bpy.context.object; obj.scale=(.008,.008,.008); obj.rotation_euler=(rng.random(),rng.random(),rng.random())
        select([obj]); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        bevel=obj.modifiers.new('Worn_ore_edges','BEVEL'); bevel.width=.0015; bevel.segments=2
        bpy.ops.object.modifier_apply(modifier=bevel.name); finish(obj,'Copper_crystal', 'copper',False)


def bark(seed=2):
    rock((0,-.025,-.31),(.135,.052,.31),'bark',seed)
    for i in range(12):
        x=rng.uniform(-.10,.10); z=rng.uniform(-.53,-.08)
        rock((x,-.07,z),(.035,.015,.024),'moss',i+seed)


def shelf(center, radius, material='shelf', arch=.025):
    center=Vector(center); verts=[]; uv=[]; faces=[]; arcs=36; rings=12
    # Kidney-shaped bracket, attached at its back and flared out from the wall.
    for side in [1,-1]:
        for j in range(rings+1):
            t=j/rings
            for i in range(arcs+1):
                a=-math.pi*.12+i/arcs*math.pi*1.24
                width=radius*(1+.045*math.sin(a*9))
                x=math.cos(a)*width*t
                y=-math.sin(a)*width*t
                z=arch*(1-t*t)+.009*math.sin(a*2)*t
                if side==-1: z-=.012*(1-.7*t)
                verts.append(center+Vector((x,y,z))); uv.append((i/arcs,t))
    layer=(rings+1)*(arcs+1)
    for side in range(2):
        for j in range(rings):
            for i in range(arcs):
                a=side*layer+j*(arcs+1)+i
                face=(a,a+1,a+arcs+2,a+arcs+1)
                faces.append(face if side==0 else tuple(reversed(face)))
    for i in range(arcs):
        a=rings*(arcs+1)+i; faces.append((a,layer+a,layer+a+1,a+1))
    mesh('Layered_bracket',verts,faces,material,uv)
    if material=='pearl':
        for i in range(24):
            a=i/23*math.pi*1.02
            begin=center+Vector((math.cos(a)*radius*.13,-math.sin(a)*radius*.13,arch-.015))
            end=center+Vector((math.cos(a)*radius*.88,-math.sin(a)*radius*.88,-.008))
            tube('Radial_gill',[begin,begin.lerp(end,.5)+Vector((0,0,.006)),end],.0013,'gill',.6,detail=1)


def woodland_shelves():
    bark(20)
    for i in range(6):
        side=-1 if i%2 else 1
        shelf((side*.045,-.075,-.13-i*.076),.085+rng.random()*.04)


def woodland_oysters():
    bark(34)
    for i in range(5):
        center=Vector(((-1 if i%2 else 1)*.05,-.10,-.13-i*.084))
        tube('Oyster_stem',[center+Vector((0,.03,-.035)),center],.013,'gill',.25)
        shelf(center,.09+rng.random()*.04,'pearl',.035)


def woodland_fern():
    bark(51)
    for k in range(6):
        root=Vector((0,-.08,-.33)); angle=-1.1+k*.44
        tip=Vector((math.sin(angle)*.27,-.10-abs(math.sin(angle))*.035,-.33+math.cos(angle)*.31))
        tube('Fern_rachis',[root,root.lerp(tip,.5)+Vector((0,-.025,0)),tip],.0024,'fern')
        across=(tip-root).cross(Vector((0,-1,0))).normalized()
        for j in range(1,9):
            t=j/10; base=root.lerp(tip,t)+Vector((0,-.022*math.sin(t*math.pi),0))
            for sign in [-1,1]:
                end=base+across*sign*(.065*(1-t)+.012)+(tip-root).normalized()*.027
                blade(base,end,.008*(1-t)+.004,'fern',.02,segments=6)


builders={'ReefFan':reef_fan,'ReefSponges':reef_sponges,'ReefKelp':reef_kelp,
          'CavernAmethyst':geode,'CavernQuartz':quartz_cluster,'CavernCopper':copper_outcrop,
          'WoodlandShelves':woodland_shelves,'WoodlandOysters':woodland_oysters,'WoodlandFern':woodland_fern}
roots={}; stats={}
for index,(name,builder) in enumerate(builders.items()):
    parts=[]; rng=random.Random(200+index); builder(); select(parts); bpy.ops.object.join()
    obj=bpy.context.object; obj.name=name
    # Fit all assets against the wall; the upper attachment origin is consistent across themes.
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    top=max(v.co.z for v in obj.data.vertices); back=max(v.co.y for v in obj.data.vertices)
    for v in obj.data.vertices: v.co.z-=top; v.co.y-=max(0,back)
    scene.cursor.location=(0,0,0); bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    mod=obj.modifiers.new('Export_triangles','TRIANGULATE'); bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.data.name=name+'_Mesh'
    triangles=len(obj.data.polygons)
    assert triangles < 36000,(name,triangles)
    bpy.ops.wm.usd_export(filepath=str(ASSETS/(name+'.usdz')),selected_objects_only=True,
        export_animation=False,export_materials=True,generate_preview_surface=True,export_lights=False,export_cameras=False,
        convert_orientation=True,export_global_forward_selection='NEGATIVE_Z',export_global_up_selection='Y',
        export_custom_properties=False,export_mesh_colors=False)
    stats[name]={'triangles':triangles,'materials':len(obj.data.materials),'sizeMetersBlenderXYZ':list(obj.dimensions),
                 'bytes':(ASSETS/(name+'.usdz')).stat().st_size}
    roots[name]=obj; obj.hide_render=True

(ART/'manifest.json').write_text(json.dumps(stats,indent=2)+'\n')

wall=mat('Studio_plaster','C9C8C2',.85)
bpy.ops.mesh.primitive_plane_add(size=100,rotation=(math.pi/2,0,0),location=(0,.012,0))
obj=bpy.context.object; obj.name='Studio_wall'; obj.data.materials.append(wall)
scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.62,.69,.74,1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value=.4
for name,loc,power,size in [('Window',(-1.3,-1.9,1.8),115,1.8),('Fill',(1.5,-1,.7),35,1.6)]:
    data=bpy.data.lights.new(name,'AREA'); data.energy=power; data.shape='DISK'; data.size=size
    obj=bpy.data.objects.new(name,data); bpy.context.collection.objects.link(obj); obj.location=loc
    obj.rotation_euler=(Vector((0,0,-.3))-obj.location).to_track_quat('-Z','Y').to_euler()
data=bpy.data.cameras.new('Theme_camera'); camera=bpy.data.objects.new('Theme_camera',data)
bpy.context.collection.objects.link(camera); scene.camera=camera; data.type='ORTHO'; data.ortho_scale=2.15
camera.location=(.38,-4.3,.40)
camera.rotation_euler=(Vector((0,0,-.3))-camera.location).to_track_quat('-Z','Y').to_euler()
scene.render.resolution_x=1200; scene.render.resolution_y=680; scene.render.resolution_percentage=100
for theme in os.environ.get('POCKET_THEME_PREVIEWS','Reef,Cavern,Woodland').split(','):
    group=[obj for name,obj in roots.items() if name.startswith(theme)]
    for i,obj in enumerate(group): obj.hide_render=False; obj.location=(.66*(i-1),0,0)
    scene.render.filepath=str(ART/(theme+'-preview.png')); bpy.ops.render.render(write_still=True)
    folder=ROOT/'PocketRealm'/'Resources'/'Assets.xcassets'/('Theme'+theme+'.imageset'); folder.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(ART/(theme+'-preview.png'),folder/'preview.png')
    (folder/'Contents.json').write_text(json.dumps({'images':[{'filename':'preview.png','idiom':'universal'}],'info':{'author':'xcode','version':1}},indent=2)+'\n')
    for obj in group: obj.hide_render=True
for i,(name,obj) in enumerate(roots.items()):
    obj.hide_render=False; obj.location=((i%3-1)*.66,0,-(i//3)*.9)
data.ortho_scale=3.05
camera.location=(.35,-5,-.65); camera.rotation_euler=(Vector((0,0,-1.2))-camera.location).to_track_quat('-Z','Y').to_euler()
scene.render.resolution_x=1200; scene.render.resolution_y=1440
scene.render.filepath=str(ART/'themes-lineup.png')
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_perspective='CAMERA'
            area.spaces.active.shading.color_type='MATERIAL'; area.spaces.active.overlay.show_overlays=False
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'PocketRealm-Themes.blend'),compress=True)
(ART/'manifest.json').write_text(json.dumps(stats,indent=2)+'\n')
bpy.ops.render.render(write_still=True)
print('THEME_EXPORTS_COMPLETE',json.dumps(stats))
