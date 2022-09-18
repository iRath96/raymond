import bpy
import math
import os
import shutil

from warnings import warn

from .utils import describe_cycles_visibility, describe_visibility
from .materials import export_material
from .registry import SceneRegistry


def _export_area_light(registry: SceneRegistry, light: bpy.types.Light, inst: bpy.types.DepsgraphObjectInstance):
    # To export area lights, we convert them to ordinary shapes with a special kind of material:
    # 1) We generate the material for them.
    #      The rendered will treat them differently due to the use of OUTPUT_LIGHT instead of OUTPUT_MATERIAL.
    # 2) The OUTPUT_LIGHT node is augmented will the parameters of the light source.
    #      This includes color, shape, strength, and spread.
    # 3) We export simple quad geometry.
    #      Disks/Ellipses are handled by the "shape" info on OUTPUT_LIGHT;
    #      this allows us to have crisp analytical disk shapes without having to triangulate them or support
    #      disk intersection in our renderer.

    # STEP 1: export material
    # @todo avoid name clashes
    material = export_material(registry, light)
    material_name = registry.materials.force_export(light, material)

    # STEP 2: augment OUTPUT_LIGHT node with parameters
    output_node = None
    for node in material.values():
        if node["type"] == "OUTPUT_LIGHT":
            output_node = node
            break
    else:
        # no OUTPUT_LIGHT node was found, so we need to create one
        # @todo avoid name clashes
        output_node = {
            "type": "OUTPUT_LIGHT",
            "inputs": {},
            "parameters": {}
        }
        material["Light Output"] = output_node
    
    # Compute actual matrix
    # From my understanding, object transforms in Blender are always similarity transformations.
    # This means we do not need to worry about the angle formed by the spanning vectors of our
    # area light when computing the area for power normalization, as they will still be orthogonal.
    scale_x = light.size
    if light.shape == "SQUARE" or light.shape == "DISK":
        scale_y = light.size
    elif light.shape == "RECTANGLE" or light.shape == "ELLIPSE":
        scale_y = light.size_y
    else:
        warn(f"Unsupported light shape '{light.shape}'")
        scale_y = light.size
    
    matrix_world = [ [ x for x in row ] for row in inst.matrix_world ]
    for i in range(3):
        matrix_world[i][0] *= scale_x
        matrix_world[i][1] *= scale_y
    size_x = math.sqrt(sum([ matrix_world[i][0]**2 for i in range(3) ]))
    size_y = math.sqrt(sum([ matrix_world[i][1]**2 for i in range(3) ]))

    if light.shape == "SQUARE" or light.shape == "RECTANGLE":
        area = size_x * size_y
    else:
        area = size_x * size_y * (math.pi / 4)

    output_node["parameters"].update({
        "cast_shadows": light.cycles.cast_shadow,
        "use_mis": light.cycles.use_multiple_importance_sampling,

        "shape": light.shape,
        "color": list(light.color),
        "irradiance": light.energy / area,
        "spread": light.spread,
    })

    # STEP 3: export geometry
    rectangle_path = os.path.join(registry.meshpath, "rectangle.ply")
    shutil.copy(os.path.join(os.path.dirname(__file__), "library/rectangle.ply"), rectangle_path)
    shape_name = registry.shapes.force_export(light, {
        "type": "ply",
        "filepath": rectangle_path,
        "materials": [ material_name ]
    })
    registry.entities.force_export(light, {
        "shape": shape_name,
        "visibility": describe_visibility(inst.object),
        "matrix": [ x for row in matrix_world for x in row ]
    })


def _export_point_light(registry: SceneRegistry, light: bpy.types.PointLight, inst: bpy.types.DepsgraphObjectInstance):
    material_name = registry.materials.export(light, lambda unique_name: export_material(registry, light))
    registry.lights.force_export(light, {
        "type": "POINT",
        "material": material_name,

        "visibility": describe_visibility(inst.object),
        "cast_shadows": light.cycles.cast_shadow,
        "use_mis": light.cycles.use_multiple_importance_sampling,

        "parameters": {
            "power": light.energy,
            "color": list(light.color),
            "radius": light.shadow_soft_size,
        }
    })


def _export_spot_light(registry: SceneRegistry, light: bpy.types.SpotLight, inst: bpy.types.DepsgraphObjectInstance):
    material_name = registry.materials.export(light, lambda unique_name: export_material(registry, light))
    registry.lights.force_export(light, {
        "type": "SPOT",
        "material": material_name,

        "visibility": describe_visibility(inst.object),
        "cast_shadows": light.cycles.cast_shadow,
        "use_mis": light.cycles.use_multiple_importance_sampling,

        "parameters": {
            "power": light.energy,
            "color": list(light.color),
            "radius": light.shadow_soft_size,
            "spot_size": light.spot_size,
            "spot_blend": light.spot_blend,
        }
    })


def _export_sun_light(registry: SceneRegistry, light: bpy.types.SunLight, inst: bpy.types.DepsgraphObjectInstance):
    material_name = registry.materials.export(light, lambda unique_name: export_material(registry, light))
    registry.lights.force_export(light, {
        "type": "SUN",
        "material": material_name,

        "visibility": describe_visibility(inst.object),
        "cast_shadows": light.cycles.cast_shadow,
        "use_mis": light.cycles.use_multiple_importance_sampling,

        "parameters": {
            "power": light.energy,
            "color": list(light.color),
            "angle": light.angle,
        }
    })


def export_light(registry: SceneRegistry, light: bpy.types.Light, inst: bpy.types.DepsgraphObjectInstance):
    if light.cycles.is_portal:
        warn(f"Light portals are not supported")
        return

    if light.type == "AREA":
        _export_area_light(registry, light, inst)
    elif light.type == "POINT":
        _export_point_light(registry, light, inst)
    elif light.type == "SPOT":
        _export_spot_light(registry, light, inst)
    elif light.type == "SUN":
        _export_sun_light(registry, light, inst)
    else:
        warn(f"Unsupported light type: {light.type}")


def export_world_light(registry: SceneRegistry, world: bpy.types.World):
    material_name = registry.materials.export(world, lambda unique_name: export_material(registry, world))
    registry.lights.force_export(world, {
        "type": "WORLD",
        "material": material_name,

        "visibility": describe_cycles_visibility(world.cycles_visibility),
        "cast_shadows": True,
        "use_mis": True,

        "parameters": {}
    })
