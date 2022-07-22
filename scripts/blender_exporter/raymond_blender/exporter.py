from email.mime import base
import os
import json
import bpy
from warnings import warn

from .materials import export_material
from .shapes import export_shape, get_shape_name_base
from .camera import export_camera, export_render


def export_materials(texturepath: str, image_cache: dict[str, str]):
    # @todo only export materials (and textures) that are used
    result = {}
    for material in bpy.data.materials.values():
        result[material.name] = export_material(material, texturepath, image_cache)
    return result


def export_shapes(depsgraph: bpy.types.Depsgraph, meshpath: str, use_selection: bool):
    shapes = {}
    entities = {}

    for inst_hack in depsgraph.object_instances:
        # can't use .values() or list() above because ???
        # use second variable to get strong typing with fake-bpy python module
        inst: bpy.types.DepsgraphObjectInstance = inst_hack

        object_eval = inst.object
        if use_selection and not object_eval.original.select_get():
            continue
        if not use_selection and not inst.show_self:
            continue
        
        objType = object_eval.type
        if objType == "MESH" or objType == "CURVE" or objType == "SURFACE":
            shape_name = get_shape_name_base(object_eval)
            
            if not shape_name in shapes:
                shapes[shape_name] = export_shape(object_eval, depsgraph, meshpath)
            
            if len(shapes[shape_name]) == 0:
                warn(f"Entity {object_eval.name} has no material or shape and will be ignored")
                continue

            entities[object_eval.name] = {
                "shape": shape_name,
                "visibility": {
                    "camera": object_eval.visible_camera,
                    "diffuse": object_eval.visible_diffuse,
                    "glossy": object_eval.visible_glossy,
                    "transmission": object_eval.visible_transmission,
                    "volume": object_eval.visible_volume_scatter,
                    "shadow": object_eval.visible_shadow
                },
                "matrix": [ x for row in inst.matrix_world for x in row ]
            }
        #elif objType == "LIGHT" and export_lights:
        #    export_light(
        #        result, inst)
    
    return (shapes, entities)


def export_scene(filepath, context: bpy.types.Context, use_selection: bool):
    depsgraph = context.evaluated_depsgraph_get()

    base_path = os.path.dirname(filepath)
    texturepath = os.path.join(base_path, "textures")
    meshpath = os.path.join(base_path, "meshes")
    os.makedirs(texturepath, exist_ok=True)
    os.makedirs(meshpath, exist_ok=True)

    image_cache = {}

    materials = export_materials(texturepath, image_cache)
    world = export_material(depsgraph.scene.world, texturepath, image_cache)
    (shapes, entities) = export_shapes(depsgraph, meshpath, use_selection)
    camera = export_camera(depsgraph.scene.camera)
    render = export_render(depsgraph.scene.render)

    result = {
        "materials": materials,
        "world": world,
        "shapes": shapes,
        "entities": entities,
        "camera": camera,
        "render": render
    }

    # write output file
    with open(filepath, "w") as fp:
        json.dump(result, fp, indent=2)
