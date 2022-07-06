import os
import json
import bpy
from warnings import warn

from .materials import export_material
from .shapes import export_shape, get_shape_name_base


def export_materials():
    result = {}
    for material in bpy.data.materials.values():
        result[material.name] = export_material(material)
    return result


def export_shapes(filepath: str, depsgraph: bpy.types.Depsgraph, use_selection: bool):
    meshpath = os.path.join(os.path.dirname(filepath), "meshes")
    os.makedirs(meshpath, exist_ok=True)

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
                "matrix": [ x for row in inst.matrix_world for x in row ]
            }
        #elif objType == "LIGHT" and export_lights:
        #    export_light(
        #        result, inst)
    
    return (shapes, entities)


def export_scene(filepath, context, use_selection):
    depsgraph = context.evaluated_depsgraph_get()

    materials = export_materials()
    (shapes, entities) = export_shapes(filepath, depsgraph, use_selection)

    result = {
        "materials": materials,
        "shapes": shapes,
        "entities": entities
    }

    # write output file
    with open(filepath, "w") as fp:
        json.dump(result, fp, indent=2)
