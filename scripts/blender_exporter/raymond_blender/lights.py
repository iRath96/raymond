import bpy
import math
import os
import shutil

from warnings import warn

from .utils import describe_cycles_visibility, describe_visibility
from .materials import export_material
from .registry import SceneRegistry


def _export_light(registry: SceneRegistry, light: bpy.types.Light, inst: bpy.types.DepsgraphObjectInstance, type: str):
    material_name = registry.materials.export(light, lambda unique_name: export_material(registry, light))
    return {
        "type": type,
        "material": material_name,

        "visibility": describe_visibility(inst.object),
        "cast_shadows": light.cycles.cast_shadow,
        "use_mis": light.cycles.use_multiple_importance_sampling,
    }


def _export_area_light(registry: SceneRegistry, light: bpy.types.Light, inst: bpy.types.DepsgraphObjectInstance):
    if light.cycles.is_portal:
        warn(f"Light portals are not supported")
        return
    
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
    
    registry.lights.force_export(light, {
        **_export_light(registry, light, inst, "AREA"),
        "parameters": {
            "transform": [ x for row in matrix_world for x in row ],
            "power": light.energy,
            "color": list(light.color),
            "spread": light.spread,
            "is_circular": light.shape in [ "DISK", "ELLIPSE" ]
        }
    })


def _export_point_light(registry: SceneRegistry, light: bpy.types.PointLight, inst: bpy.types.DepsgraphObjectInstance):
    registry.lights.force_export(light, {
        **_export_light(registry, light, inst, "POINT"),
        "parameters": {
            "location": list(inst.object.location),
            "power": light.energy,
            "color": list(light.color),
            "radius": light.shadow_soft_size,
        }
    })


def _export_spot_light(registry: SceneRegistry, light: bpy.types.SpotLight, inst: bpy.types.DepsgraphObjectInstance):
    registry.lights.force_export(light, {
        **_export_light(registry, light, inst, "SPOT"),
        "parameters": {
            "location": list(inst.object.location),
            "direction": list(inst.matrix_world[2]),
            "power": light.energy,
            "color": list(light.color),
            "radius": light.shadow_soft_size,
            "spot_size": light.spot_size,
            "spot_blend": light.spot_blend,
        }
    })


def _export_sun_light(registry: SceneRegistry, light: bpy.types.SunLight, inst: bpy.types.DepsgraphObjectInstance):
    registry.lights.force_export(light, {
        **_export_light(registry, light, inst, "SUN"),
        "parameters": {
            "direction": list(inst.matrix_world[2]),
            "power": light.energy,
            "color": list(light.color),
            "angle": light.angle,
        }
    })


def export_light(registry: SceneRegistry, light: bpy.types.Light, inst: bpy.types.DepsgraphObjectInstance):
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
