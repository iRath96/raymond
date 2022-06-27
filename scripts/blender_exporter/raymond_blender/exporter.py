import os
import json
import bpy
from warnings import warn

from .materials import export_material


def export_materials():
    result = {}
    for material in bpy.data.materials.values():
        result[material.name] = export_material(material)
    return result


def export_scene(filepath, context, use_selection):
    depsgraph = context.evaluated_depsgraph_get()

    result = {
        "materials": export_materials()
    }

    # write output file
    with open(filepath, 'w') as fp:
        json.dump(result, fp, indent=2)
