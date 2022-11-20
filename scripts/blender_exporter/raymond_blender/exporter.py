import os
import json
import bpy

from .registry import SceneRegistry
from .lights import export_world_light, export_light
from .shapes import export_shape
from .camera import export_camera, export_render


def export_objects(registry: SceneRegistry, depsgraph: bpy.types.Depsgraph, use_selection: bool):
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
            def export_object():
                # @todo instancing with different materials not yet supported
                shape_name = registry.shapes.export(
                    object_eval.original.data,
                    lambda unique_name: export_shape(registry, object_eval, depsgraph, unique_name)
                )
                return {
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
            
            registry.entities.force_export(object_eval, export_object())
        elif objType == "LIGHT":
            export_light(registry, object_eval.data, inst)


def export_scene(filepath, context: bpy.types.Context, use_selection: bool):
    depsgraph = context.evaluated_depsgraph_get()

    basepath = os.path.dirname(filepath)
    registry = SceneRegistry(basepath)

    export_world_light(registry, depsgraph.scene.world)
    export_objects(registry, depsgraph, use_selection)

    result = {
        "materials": registry.materials.converted,
        "shapes": registry.shapes.converted,
        "entities": registry.entities.converted,
        "lights": registry.lights.converted,
        "camera": export_camera(depsgraph.scene.camera),
        "render": export_render(depsgraph.scene.render)
    }

    # write output file
    with open(filepath, "w") as fp:
        json.dump(result, fp, indent=2)
