"""Build original, meter-scale wall botanicals in Blender; no external assets.

Blender --background --python scripts/build_jungle.py
Exports six USDZs (three shapes / two palettes), packed source, and a studio preview.
Blender X is horizontal, Z is up, -Y faces the room. USDZ is Y-up, +Z outward.
"""
from pathlib import Path
import json
import math
import random
import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'Art' / 'Jungle'
ASSETS = ROOT / 'PocketRealm' / 'Resources' / 'Jungle'
for directory in (ART, ART / 'Textures', ASSETS):
    directory.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version = 0
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1
scene.render.engine = 'CYCLES'
scene.cycles.samples = 40
scene.cycles.use_denoising = True
scene.view_settings.view_transform = 'AgX'
scene.render.image_settings.file_format = 'PNG'


def linear(hexcolor):
    c = np.array([int(hexcolor[i:i+2], 16) / 255 for i in (0, 2, 4)])
    return np.where(c <= .04045, c / 12.92, ((c + .055) / 1.055) ** 2.4)


def material(name, color, roughness):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*linear(color), 1)
    m.use_nodes = True
    shader = m.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = m.diffuse_color
    shader.inputs['Roughness'].default_value = roughness
    shader.inputs['Specular IOR Level'].default_value = .32
    return m


def leaf_material(palette):
    """UV-painted color/roughness: midrib, curved lateral veins and fine mottling."""
    size = 1024
    v, u = np.mgrid[0:size, 0:size].astype(np.float32) / (size - 1)
    x = (u - .5) * 2
    rib = np.exp(-(x / .022) ** 2)
    # Secondary veins bend toward the tip and stop at the center rib.
    phase = (v - .27 * np.abs(x) ** .75) * 10
    veins = np.exp(-(np.sin(phase * math.pi) / .11) ** 2)
    noise = np.random.default_rng(51).random((size, size)) - .5
    broad = np.sin(v * 19 + x * 7) * np.sin(x * 14 - v * 8)
    brightness = .78 + .12 * broad + .09 * noise + .18 * rib + .10 * veins
    green = np.array([.26, .43, .135] if palette == 'Forest' else [.25, .49, .20])
    colors = np.clip(brightness[..., None] * green, 0, 1)
    colors += (rib + veins * .20)[..., None] * np.array([.07, .06, .008])
    image = bpy.data.images.new(palette + '_leaf_color', width=size, height=size, alpha=False)
    image.pixels.foreach_set(np.dstack((colors, np.ones((size, size)))).astype(np.float32).ravel())
    image.filepath_raw = str(ART / 'Textures' / (image.name + '.png'))
    image.file_format = 'PNG'; image.save(); image.pack()
    rough = bpy.data.images.new(palette + '_leaf_roughness', width=size, height=size, alpha=False)
    rough.colorspace_settings.name = 'Non-Color'
    value = np.clip(.42 + .1 * np.abs(x) + .055 * noise + .08 * veins, 0, 1)
    rough.pixels.foreach_set(np.dstack((value, value, value, np.ones_like(value))).astype(np.float32).ravel())
    rough.filepath_raw = str(ART / 'Textures' / (rough.name + '.png'))
    rough.file_format = 'PNG'; rough.save(); rough.pack()
    m = material(palette + '_veined_leaf', '517A32', .48)
    shader = m.node_tree.nodes.get('Principled BSDF')
    for image, socket in ((image, 'Base Color'), (rough, 'Roughness')):
        node = m.node_tree.nodes.new('ShaderNodeTexImage'); node.image = image
        node.interpolation = 'Linear'
        m.node_tree.links.new(node.outputs['Color'], shader.inputs[socket])
    return m


M = {}
for palette, flower in [('Forest', 'E1CCE4'), ('Tropical', 'F1B6A4')]:
    M[palette] = [material(palette + '_stem', '526237', .68), leaf_material(palette),
                  material(palette + '_petal', flower, .46), material(palette + '_pollen', 'D8A648', .64)]
parts = []
palette = 'Forest'


def mesh(name, vertices, faces, material_index, uv=None):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces); data.update()
    obj = bpy.data.objects.new(name, data); bpy.context.collection.objects.link(obj)
    data.materials.append(M[palette][material_index])
    for p in data.polygons: p.use_smooth = True
    if uv:
        layer = data.uv_layers.new(name='UVMap')
        for loop in data.loops: layer.data[loop.index].uv = uv[loop.vertex_index]
    parts.append(obj)
    return obj


def tube(name, points, radius=.003, material_index=0):
    curve = bpy.data.curves.new(name, 'CURVE'); curve.dimensions = '3D'
    curve.resolution_u = 5; curve.bevel_depth = radius; curve.bevel_resolution = 2
    curve.use_fill_caps = True
    spline = curve.splines.new('BEZIER'); spline.bezier_points.add(len(points)-1)
    for i, (p, co) in enumerate(zip(spline.bezier_points, points)):
        p.co = co; p.handle_left_type = 'AUTO'; p.handle_right_type = 'AUTO'
        p.radius = 1 - .52 * i / max(1, len(points)-1)
    obj = bpy.data.objects.new(name, curve); bpy.context.collection.objects.link(obj)
    bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True); bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target='MESH')
    obj.data.materials.append(M[palette][material_index])
    for p in obj.data.polygons: p.use_smooth = True
    parts.append(obj)


def leaf(start, tip, width, twist=0, material_index=1, segments=16):
    """A cupped, gently curled blade with actual thickness and smooth normals."""
    start, tip = Vector(start), Vector(tip)
    axis = tip - start
    side = axis.cross(Vector((0, -1, 0))).normalized()
    front = side.cross(axis).normalized()
    side, front = side * math.cos(twist) + front * math.sin(twist), front * math.cos(twist) - side * math.sin(twist)
    vertices, uv, faces = [], [], []
    across = 4 if segments == 8 else 8
    for i in range(segments + 1):
        t = i / segments
        silhouette = max(.009, math.sin(math.pi * t) ** .78) * (1.05 - .28 * t)
        for j in range(across + 1):
            s = j / across * 2 - 1
            ripple = math.sin(t * 24 + s * 3) * .025 * abs(s) ** 3
            center = start + axis * t + front * (axis.length * .10 * math.sin(t * math.pi) - axis.length * .12 * t ** 5)
            point = center + side * (s * width * silhouette * (1 + ripple))
            point += front * (width * (.20 * (1 - abs(s)) - .16 * s * s) * math.sin(t * math.pi))
            vertices.append(point); uv.append((j / across, t))
    for i in range(segments):
        for j in range(across):
            a = i * (across+1) + j
            faces.append((a, a+1, a+across+2, a+across+1))
    obj = mesh('Curved_leaf' if material_index == 1 else 'Silk_petal', vertices, faces, material_index, uv)
    bpy.context.view_layer.objects.active = obj
    solid = obj.modifiers.new('Fine leaf edge', 'SOLIDIFY'); solid.thickness = .0007
    bpy.ops.object.modifier_apply(modifier=solid.name)


def flower(center, size, rng):
    center = Vector(center)
    for i in range(5):
        angle = i * math.tau / 5 + .25
        direction = Vector((math.cos(angle), -.20, math.sin(angle)))
        leaf(center, center + direction * size, size * .35, twist=.12, material_index=2)
    # Small rounded pollen stamens with short curved stalks.
    for i in range(7):
        angle = i * math.tau / 7
        end = center + Vector((math.cos(angle)*size*.12, -size*.25, math.sin(angle)*size*.12))
        tube('Stamen', [center, end], .0012, 3)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=size*.055, location=end)
        obj = bpy.context.object; obj.name = 'Pollen'; obj.data.materials.append(M[palette][3]); parts.append(obj)
        for p in obj.data.polygons: p.use_smooth = True


def vine(bloom=False):
    rng = random.Random(19 if bloom else 7)
    length = .69 if bloom else .88
    def stem(t): return Vector((.035*math.sin(t*8), -.032-.016*math.sin(t*5), -length*t))
    tube('Climbing_stem', [stem(i/12) for i in range(13)], .004)
    for i in range(13):
        t = .045 + i * .070
        sign = -1 if i % 2 else 1
        joint = stem(t)
        start = joint + Vector((sign*.025, -.009, -.015))
        tip = start + Vector((sign*(.10+rng.random()*.055), -.025-rng.random()*.025, -.07-rng.random()*.04))
        tube('Petiole', [joint, start], .0018)
        leaf(start, tip, .036+rng.random()*.012, rng.uniform(-.3, .3))
        if bloom and i in (2, 5, 9):
            center = joint + Vector((sign*.065, -.065, -.025))
            tube('Flower_stalk', [joint, center], .002)
            flower(center, .060 if i != 5 else .073, rng)
    # One curling tendril; the curve remains a tube when exported to RealityKit.
    joint = stem(.29)
    tube('Tendril', [joint + Vector((.05*t, -.008*t, .055*math.sin(t*4))) for t in np.linspace(0, 1, 12)], .0013)


def fern():
    for k in range(7):
        angle = -.9 + k * .3
        side = math.sin(angle)
        tip = Vector((side*.34, -.065-abs(side)*.035, -.14-math.cos(angle)*.32))
        start = Vector((0, -.02, -.015))
        def spine(t): return start.lerp(tip, t) + Vector((0, -.07*math.sin(t*math.pi), .05*math.sin(t*math.pi)))
        tube('Fern_rachis', [spine(t/8) for t in range(9)], .0023)
        axis = (tip-start).normalized(); across = axis.cross(Vector((0, -1, 0))).normalized()
        for j in range(1, 9):
            t = j/10
            for sign in (-1, 1):
                base = spine(t)
                end = base + across * sign * (.065*(1-t)+.010) + axis*.033
                leaf(base, end, .010*(1-t)+.004, .12*sign, segments=8)


roots, stats = [], {}
for palette in ('Forest', 'Tropical'):
    for shape in ('Trail', 'Bloom', 'Fern'):
        parts = []
        if shape == 'Fern': fern()
        else: vine(bloom=shape == 'Bloom')
        bpy.ops.object.select_all(action='DESELECT')
        for obj in parts: obj.select_set(True)
        bpy.context.view_layer.objects.active = parts[0]; bpy.ops.object.join()
        obj = bpy.context.object; obj.name = palette + shape
        # Bake an origin at the attachment point, not at an arbitrary joined leaf.
        scene.cursor.location = (0, 0, 0); bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
        obj.data.name = obj.name + '_Mesh'
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        # Make exactly the same geometry render in Blender and RealityKit.
        triangulate = obj.modifiers.new('Export triangles', 'TRIANGULATE')
        bpy.ops.object.modifier_apply(modifier=triangulate.name)
        bpy.ops.wm.usd_export(filepath=str(ASSETS / (obj.name + '.usdz')), selected_objects_only=True,
            export_animation=False, export_materials=True, generate_preview_surface=True,
            export_lights=False, export_cameras=False, convert_orientation=True,
            export_global_forward_selection='NEGATIVE_Z', export_global_up_selection='Y',
            export_custom_properties=False, export_mesh_colors=False)
        stats[obj.name] = {'triangles': len(obj.data.polygons), 'materials': len(obj.data.materials),
                           'sizeMetersBlenderXYZ': list(obj.dimensions), 'bytes': (ASSETS/(obj.name+'.usdz')).stat().st_size}
        roots.append(obj)
        obj.hide_render = True

# A neutral wall preview: lighting and shadows are studio presentation only, not baked into assets.
wallmat = material('Warm_plaster', 'DCD8CE', .85)
bpy.ops.mesh.primitive_plane_add(size=200, rotation=(math.pi/2, 0, 0), location=(0, .012, 0))
bpy.context.object.name = 'Preview_wall'; bpy.context.object.data.materials.append(wallmat)
for i, obj in enumerate(roots):
    obj.location = ((i % 3 - 1) * .62, 0, .15 if i < 3 else -1.04)
    obj.hide_render = False
world = scene.world; world.use_nodes = True
world.node_tree.nodes['Background'].inputs[0].default_value = (.6, .67, .73, 1)
world.node_tree.nodes['Background'].inputs[1].default_value = .45
for name, loc, energy, size in [('Window', (-1.5, -2.4, 2), 135, 2), ('Fill', (2, -1, .5), 45, 2)]:
    data = bpy.data.lights.new(name, 'AREA'); data.energy = energy; data.shape = 'DISK'; data.size = size
    obj = bpy.data.objects.new(name, data); bpy.context.collection.objects.link(obj); obj.location = loc
    obj.rotation_euler = (Vector((0, 0, -.5))-obj.location).to_track_quat('-Z', 'Y').to_euler()
data = bpy.data.cameras.new('Botanical_preview'); camera = bpy.data.objects.new('Botanical_preview', data)
bpy.context.collection.objects.link(camera); scene.camera = camera
data.type = 'ORTHO'; data.ortho_scale = 2.72
camera.location = (.5, -5, -.65)
camera.rotation_euler = (Vector((0, 0, -.85))-camera.location).to_track_quat('-Z', 'Y').to_euler()
scene.render.resolution_x = 1500; scene.render.resolution_y = 1500; scene.render.resolution_percentage = 100
scene.render.filepath = str(ART / 'jungle-botanicals.png')
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == 'VIEW_3D':
            area.spaces.active.region_3d.view_perspective = 'CAMERA'
            area.spaces.active.shading.color_type = 'MATERIAL'
            area.spaces.active.overlay.show_overlays = False
bpy.ops.wm.save_as_mainfile(filepath=str(ART / 'PocketRealm-Jungle.blend'))
(ART / 'manifest.json').write_text(json.dumps(stats, indent=2) + '\n')
bpy.ops.render.render(write_still=True)
print('JUNGLE_EXPORTS_COMPLETE', json.dumps(stats))
