import math
import os
import json
import shutil
import bpy
from warnings import warn

from .materials import export_default_material, export_material
from .shapes import export_shape, get_shape_name_base
from .camera import export_camera, export_render
from .utils import find_unique_name


def export_shapes(depsgraph: bpy.types.Depsgraph, meshpath: str, texturepath: str, image_cache: dict[str, str], use_selection: bool):
    shapes = {}
    entities = {}
    materials = {}

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
                warn(f"Entity {object_eval.name} has no shapes and will be ignored")
                continue
            
            name = find_unique_name(entities.keys(), object_eval.name)
            entities[name] = {
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

            obj: bpy.types.Object = object_eval
            for slot in obj.material_slots.values():
                material = slot.material
                if material is None:
                    # @todo avoid name clashes
                    materials["__DEFAULT"] = export_default_material()
                    continue
                    
                if material.name not in materials:
                    materials[material.name] = export_material(material, texturepath, image_cache)
        elif objType == "LIGHT":
            # We currently only support area light sources, as other light sources require special handling
            # (in particular, they require some form of next event estimation, as they cannot be hit by rays directly).

            light: bpy.types.AreaLight = object_eval.data
            if light.type != "AREA":
                warn(f"Light {object_eval.name} is of unsupported type '{light.type}'")
                continue
            
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
            material = export_material(light, texturepath, image_cache)

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
                "shape": light.shape,
                "color": list(light.color),
                "irradiance": light.energy / area,
                "spread": light.spread
            })
            materials[light.name] = material

            # STEP 3: export geometry
            # @todo avoid name clashes
            rectangle_path = os.path.join(meshpath, "rectangle.ply")
            shutil.copy(os.path.join(os.path.dirname(__file__), "library/rectangle.ply"), rectangle_path)
            shapes[light.name] = {
                "type": "ply",
                "filepath": rectangle_path,
                "materials": [ light.name ]
            }
            entities[light.name] = {
                "shape": light.name,
                "visibility": {
                    "camera": False,
                    "diffuse": True,
                    "glossy": True,
                    "transmission": True,
                    "volume": True,
                    "shadow": True
                },
                "matrix": [ x for row in matrix_world for x in row ]
            }
    
    return (shapes, entities, materials)


def export_scene(filepath, context: bpy.types.Context, use_selection: bool):
    depsgraph = context.evaluated_depsgraph_get()

    base_path = os.path.dirname(filepath)
    texturepath = os.path.join(base_path, "textures")
    meshpath = os.path.join(base_path, "meshes")
    os.makedirs(texturepath, exist_ok=True)
    os.makedirs(meshpath, exist_ok=True)

    image_cache = {}

    world = export_material(depsgraph.scene.world, texturepath, image_cache)
    (shapes, entities, materials) = export_shapes(depsgraph, meshpath, texturepath, image_cache, use_selection)
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
