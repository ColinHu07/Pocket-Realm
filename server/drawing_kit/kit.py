"""Helpers for Codex-written Blender scripts that turn a paper drawing into a Pocket Realm keepsake.

Usage inside build.py (run with: blender --background --python build.py):
    import sys; sys.path.insert(0, ".")
    import kit
    kit.reset()
    body = kit.add(bpy.ops.mesh.primitive_uv_sphere_add, radius=1, location=(0, 0, 1))
    kit.paint(body, kit.material("Body", (0.95, 0.55, 0.4)))
    kit.finish("paper boat")   # normalizes size, exports model.usdz, renders preview.png

Blender is Z-up while modelling; the export converts to the app's Y-up, -Z-forward convention.
"""
import json
import math
import os

import bpy
from mathutils import Vector

TARGET_SIZE = 0.22  # meters along the longest side, matching the app's keepsakes
MAX_TRIANGLES = 60_000


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def add(operator, **options):
    """Run a primitive-add operator and return the object it created."""
    operator(**options)
    return bpy.context.active_object


def material(name, rgb, roughness=0.55, metallic=0.0, glow=0.0):
    """Solid-color PBR material; glow > 0 adds emission in the same color (exports to USD)."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    shader = mat.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = (*rgb, 1)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    if glow > 0:
        shader.inputs["Emission Color"].default_value = (*rgb, 1)
        shader.inputs["Emission Strength"].default_value = glow
    mat.diffuse_color = (*rgb, 1)
    return mat


def paint(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    return obj


def smooth(obj, subdivisions=0):
    if subdivisions:
        modifier = obj.modifiers.new("Subdivision", "SUBSURF")
        modifier.levels = modifier.render_levels = subdivisions
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def _meshes():
    return [o for o in bpy.context.scene.objects if o.type in {"MESH", "CURVE", "FONT", "SURFACE", "META"}]


def _bake_geometry():
    """Apply modifiers, convert curves/text to meshes, and apply transforms."""
    bpy.ops.object.select_all(action="DESELECT")
    for obj in _meshes():
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
    if not bpy.context.selected_objects:
        raise SystemExit("kit.finish: the scene has no geometry to export")
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def _bounds(objects):
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    low = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    high = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return low, high


def _triangles(objects):
    return sum(len(p.vertices) - 2 for o in objects for p in o.data.polygons)


def _normalize():
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for obj in meshes:
        if not obj.data.materials:
            paint(obj, material(obj.name + "_color", (0.9, 0.85, 0.75)))
    triangles = _triangles(meshes)
    if triangles > MAX_TRIANGLES:
        ratio = MAX_TRIANGLES / triangles
        for obj in meshes:
            bpy.context.view_layer.objects.active = obj
            modifier = obj.modifiers.new("Budget", "DECIMATE")
            modifier.ratio = ratio
            bpy.ops.object.modifier_apply(modifier=modifier.name)
    low, high = _bounds(meshes)
    size = max(high - low)
    if size <= 0:
        raise SystemExit("kit.finish: the model has no size")
    scale = TARGET_SIZE / size
    center = (low + high) / 2
    for obj in meshes:
        obj.location = (obj.location - center) * scale
        obj.scale = obj.scale * scale
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return meshes, _triangles(meshes)


def _export(path):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.context.scene.objects:
        obj.select_set(obj.type == "MESH")
    # Same settings as scripts/build_creatures.py, so drawings match the bundled friends.
    bpy.ops.wm.usd_export(filepath=path, selected_objects_only=True,
        export_animation=False, export_materials=True, generate_preview_surface=True,
        export_lights=False, export_cameras=False, convert_orientation=True,
        export_global_forward_selection="NEGATIVE_Z", export_global_up_selection="Y",
        export_custom_properties=False, export_mesh_colors=False)


def render_preview(path="preview.png", resolution=384):
    """Small Cycles CPU render from the front-left, for checking the model against the drawing."""
    scene = bpy.context.scene
    camera = bpy.data.objects.new("PreviewCamera", bpy.data.cameras.new("PreviewCamera"))
    scene.collection.objects.link(camera)
    camera.location = (0.27, -0.32, 0.19)
    direction = Vector((0, 0, 0)) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    for name, energy, location in (("Key", 60, (1, -1, 1.5)), ("Fill", 25, (-1.2, -0.4, 0.6))):
        light = bpy.data.objects.new(name, bpy.data.lights.new(name, "AREA"))
        light.data.energy = energy
        light.data.size = 1
        light.location = location
        light.rotation_euler = (Vector((0, 0, 0)) - light.location).to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(light)
    world = bpy.data.worlds.new("PreviewWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.08, 0.1, 0.1, 1)
    scene.world = world
    # Transparent background, so the render works as a sticker-style thumbnail in the app.
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.render.resolution_x = scene.render.resolution_y = resolution
    scene.render.filepath = os.path.abspath(path)
    bpy.ops.render.render(write_still=True)
    for obj in (camera,) + tuple(o for o in scene.objects if o.type == "LIGHT"):
        bpy.data.objects.remove(obj, do_unlink=True)


def finish(name, kind="object", verb="use", uses=2, title="", arrival="", success="", lines=(),
           voice="normal", model_path="model.usdz", preview=True):
    """Normalize the size, export the USDZ, render preview.png, and record the game card.

    kind: "tool" (held and swung), "character" (walks up and talks), or "object" (lands nearby).
    verb: what the player taps, e.g. "bonk". uses: taps needed, 1-5. title: a character's name.
    arrival/success: one sentence each. lines: up to 3 short things it says. voice: high/low/normal.
    """
    _bake_geometry()
    meshes, triangles = _normalize()
    _export(os.path.abspath(model_path))
    if preview:
        render_preview()
    card = {"name": str(name)[:40], "kind": kind, "verb": verb, "uses": uses, "title": title,
            "arrival": arrival, "success": success, "lines": list(lines)[:3], "voice": voice,
            "objects": len(meshes), "triangles": triangles}
    with open("result.json", "w") as handle:
        json.dump(card, handle)
    print(f"kit.finish: exported {model_path} ({len(meshes)} objects, {triangles} triangles)")
