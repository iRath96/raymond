from copy import deepcopy
import bpy
import os
import json

from warnings import warn

from .registry import SceneRegistry
from .utils import find_unique_name


def load_library_json(name: str):
    library_path = os.path.join(os.path.dirname(__file__), "library")
    with open(os.path.join(library_path, name + ".json")) as f:
        return json.load(f)

_DEFAULT_WORLD    = load_library_json("world.default")
_DEFAULT_MATERIAL = load_library_json("material.default")
_DEFAULT_LIGHT    = load_library_json("light.default")


class RMNode(object):
    def __init__(self, node: bpy.types.Node):
        self.bl_node = node
        self.links: dict[str, (str, str)] = {} # input identifier -> (from_node.name, from_output.name)
        self.values: dict[str, any] = {} # input identifier -> any

        for input in node.inputs.values():
            if input.is_linked:
                if len(input.links) != 1:
                    warn("Multi-input links are not supported!")
                    continue
                
                link = input.links[0]
                self.links[input.identifier] = (link.from_node.name, link.from_socket.identifier)
            
            if hasattr(input, "default_value"):
                value = input.default_value
                if not isinstance(value, (int, float)):
                    value = list(value)
                self.values[input.identifier] = value


class RMNodeGraph(object):
    def __init__(self, node_tree: bpy.types.NodeTree):
        self.nodes: dict[str, RMNode] = {} # node.name -> RMNode

        for node in node_tree.nodes.values():
            self.nodes[node.name] = RMNode(node)
    
    def delete_node(self, node_name):
        if node_name is None:
            return
        
        for (other_name, node) in self.nodes.items():
            for (input_name, link) in node.links.items():
                if link[0] == node_name:
                    warn(f"cannot remove node '{node_name}' as '{other_name}'.'{input_name}' still relies on output '{link[1]}'!")
                    return
        
        del self.nodes[node_name]

    # @todo this could be made more efficient if the graph was double linked
    def replace_link(self, old_link, new_link):
        for node in self.nodes.values():
            for (inp, link) in list(node.links.items()):
                if link == old_link:
                    if new_link is None:
                        del node.links[inp]
                    else:
                        node.links[inp] = new_link
    
    def replace_link_with_value(self, old_link, value):
        for node in self.nodes.values():
            for (inp, link) in list(node.links.items()):
                if link == old_link:
                    del node.links[inp]
                    node.values[inp] = value # @todo casting?

    def apply_renaming(self, renaming: dict[str, str]):
        old_nodes = self.nodes
        self.nodes = {}

        for (old_name, new_name) in renaming.items():
            node = old_nodes[old_name]
            self.nodes[new_name] = node
            for (inp, (link_node, link_output)) in node.links.items():
                node.links[inp] = (renaming[link_node], link_output)

    def use_labels_as_names(self):
        renaming = {}
        used_names = set()
        for (old_name, node) in self.nodes.items():
            new_name = find_unique_name(used_names, node.bl_node.label or node.bl_node.name)
            renaming[old_name] = new_name
            used_names.add(new_name)
        self.apply_renaming(renaming)
    
    def avoid_names(self, used_names: set[str]):
        renaming = {}
        for old_name in self.nodes.keys():
            new_name = find_unique_name(used_names, old_name)
            renaming[old_name] = new_name
            used_names.add(new_name)
        self.apply_renaming(renaming)

    def remove_muted_nodes(self):
        for (node_name, node) in list(self.nodes.items()):
            if not node.bl_node.mute:
                continue
            
            warn("Node muting has not been tested!")
            for output in node.bl_node.outputs.values():
                link = None
                for input in node.bl_node.inputs.values():
                    if input.type == output.type and input.is_linked:
                        link = node.links[output.identifier]
                        break
                
                self.replace_link((node_name, input.identifier), link)

    def remove_reroute_nodes(self):
        for (node_name, node) in list(self.nodes.items()):
            if isinstance(node.bl_node, bpy.types.NodeReroute):
                assert(len(node.bl_node.inputs) == 1)
                assert(len(node.bl_node.outputs) == 1)

                in_id = node.bl_node.inputs[0].identifier
                out_id = node.bl_node.outputs[0].identifier

                self.replace_link((node_name, out_id), node.links.get(in_id))
                self.delete_node(node_name)

    def remove_layout_nodes(self):
        for (node_name, node) in list(self.nodes.items()):
            if isinstance(node.bl_node, bpy.types.NodeFrame):
                self.delete_node(node_name)
    
    # @todo we do not support casting via GroupOutput yet
    # (e.g., a color A connected to a float GroupOutput B connected to a color input C causes the color
    # at C to become black and white, but since we directly connect A->C we do not get this effect)
    def inline_node_groups_recursively(self, max_depth=8):
        if max_depth == 0:
            warn("Maximum depth reached while inlining node group")
            return
        
        for (node_name, node) in list(self.nodes.items()):
            if not isinstance(node.bl_node, bpy.types.ShaderNodeGroup):
                continue
            
            sub_graph = RMNodeGraph(node.bl_node.node_tree)
            sub_graph.inline_node_groups_recursively(max_depth - 1)
            sub_graph.avoid_names(set(self.nodes.keys()))

            groupinputs: list[str] = []
            groupoutput: str = None

            for (sub_node_name, sub_node) in sub_graph.nodes.items():
                if isinstance(sub_node.bl_node, bpy.types.NodeGroupInput):
                    groupinputs.append(sub_node_name)
                    continue
                elif isinstance(sub_node.bl_node, bpy.types.NodeGroupOutput):
                    if sub_node.bl_node.is_active_output:
                        groupoutput = sub_node_name
                        # we keep this node, because its outputs might be referenced and we want
                        # replace_link to update this node
                    else:
                        continue

                assert(sub_node_name not in self.nodes)
                self.nodes[sub_node_name] = sub_node
            
            for input in node.bl_node.inputs.values():
                for groupinput in groupinputs:
                    if input.identifier in node.links:
                        self.replace_link((groupinput, input.identifier), node.links[input.identifier])
                    else:
                        self.replace_link_with_value((groupinput, input.identifier), node.values[input.identifier])
            
            for output in node.bl_node.outputs.values():
                if groupoutput is not None:
                    onode = sub_graph.nodes[groupoutput]
                    if output.identifier in onode.links:
                        self.replace_link((node_name, output.identifier), onode.links[output.identifier])
                    else:
                        self.replace_link_with_value((node_name, output.identifier), onode.values[output.identifier])
                else:
                    self.replace_link((node_name, output.identifier), None)
            
            self.delete_node(groupoutput)
            self.delete_node(node_name)


def _save_image(image: bpy.types.Image, path: str, is_f32=False, keep_format=False):
    # Make sure the image is loaded to memory, so we can write it out
    if not image.has_data:
        image.pixels[0]

    # Export the actual image data
    old_path = image.filepath_raw
    old_format = image.file_format
    try:
        image.filepath_raw = path
        if not keep_format:
            image.file_format = "PNG" if not is_f32 else "OPEN_EXR"
        image.save()
    finally:  # Never break the scene!
        image.filepath_raw = old_path
        image.file_format = old_format


def _handle_image(registry: SceneRegistry, image: bpy.types.Image):
    image_name = registry.images.export(image, lambda unique_name: _export_image(registry, image, unique_name))
    return registry.images.converted[image_name]

def _export_image(registry: SceneRegistry, image: bpy.types.Image, unique_name: str):
    result = None
    
    if image.source == "GENERATED":
        # @todo escape image.name, avoid filename collisions
        extension = ".png" if not image.use_generated_float else ".exr"
        img_path = os.path.join(registry.texturepath, unique_name + extension)
        _export_image(image, img_path, is_f32=image.use_generated_float)
        result = img_path
    elif image.source == "FILE":
        img_path = bpy.path.abspath(bpy.path.resolve_ncase(image.filepath_raw), library=image.library).replace("\\", "/")
        if img_path.startswith("//"):
            img_path = img_path[2:]

        export_image = image.packed_file or img_path == ""
        if export_image:
            img_basename = bpy.path.basename(img_path)

            # Special case: We can not export PNG if bit depth is not 8 (or 32), for whatever reason
            if img_basename == "" or image.depth > 32 or image.depth == 16:
                keep_format = False
                if image.depth > 32 or image.depth == 16 or image.file_format in ["OPEN_EXR", "OPEN_EXR_MULTILAYER", "HDR"]:
                    is_f32 = True
                    extension = ".exr"
                else:
                    is_f32 = False
                    extension = ".png"
                img_path = os.path.join(registry.texturepath, unique_name + extension)
            else:
                keep_format = True
                is_f32 = False  # Does not matter
                parts = img_basename.split(".")
                extension = ".png" if len(parts) == 1 else parts[-1]
                img_path = os.path.join(registry.texturepath, unique_name + extension)

            _save_image(image, img_path, is_f32=is_f32, keep_format=keep_format)
        
        result = img_path
    else:
        warn(f"Image type {image.source} not supported")
    
    return result


def export_default_material(unique_name):
    return _DEFAULT_MATERIAL


# @todo material type should be 'Material | World | Light'
def export_material(registry: SceneRegistry, material: bpy.types.Material):
    result = {}
    
    if not material.use_nodes:
        if isinstance(material, bpy.types.Light):
            return deepcopy(_DEFAULT_LIGHT)
        elif isinstance(material, bpy.types.World):
            return deepcopy(_DEFAULT_WORLD)
        elif isinstance(material, bpy.types.Material):
            return deepcopy(_DEFAULT_MATERIAL)
        else:
            warn(f"Unsupported use of node trees")
            return result
    
    node_graph = RMNodeGraph(material.node_tree)
    node_graph.inline_node_groups_recursively()
    node_graph.remove_reroute_nodes()
    node_graph.remove_muted_nodes()
    node_graph.remove_layout_nodes()
    node_graph.use_labels_as_names()

    for (node_name, rm_node) in node_graph.nodes.items():
        node = rm_node.bl_node

        if isinstance(node, bpy.types.ShaderNodeOutputMaterial) \
        or isinstance(node, bpy.types.ShaderNodeOutputWorld) \
        or isinstance(node, bpy.types.ShaderNodeOutputLight):
            if not node.is_active_output:
                continue

            if node.target == "EEVEE":
                # @todo verify this works
                continue

        result[node_name] = result_node = {
            "type": node.type,
            "inputs": {}
        }
        
        result_node["parameters"] = {}
        if isinstance(node, bpy.types.ShaderNodeTexImage):
            result_node["parameters"] = {
                "filepath": _handle_image(registry, node.image),
                "interpolation": node.interpolation,
                "projection": node.projection,
                "extension": node.extension,
                "source": node.image.source,
                "colorspace": node.image.colorspace_settings.name,
                "alpha": node.image.alpha_mode
            }
        elif isinstance(node, bpy.types.ShaderNodeTexEnvironment):
            result_node["parameters"] = {
                "filepath": _handle_image(registry, node.image),
                "interpolation": node.interpolation,
                "projection": node.projection,
                "colorspace": node.image.colorspace_settings.name,
                "alpha": node.image.alpha_mode
            }
        elif isinstance(node, bpy.types.ShaderNodeTexSky):
            result_node["parameters"] = {
                "air_density": node.air_density,
                "altitude": node.altitude,
                "dust_density": node.dust_density,
                "ground_albedo": node.ground_albedo,
                "ozone_density": node.ozone_density,
                "sky_type": node.sky_type,
                "sun_direction": list(node.sun_direction),
                "sun_disc": node.sun_disc,
                "sun_elevation": node.sun_elevation,
                "sun_intensity": node.sun_intensity,
                "sun_rotation": node.sun_rotation,
                "sun_size": node.sun_size,
                "turbidity": node.turbidity
            }
        elif isinstance(node, bpy.types.ShaderNodeMath):
            result_node["parameters"] = {
                "operation": node.operation,
                "use_clamp": node.use_clamp
            }
        elif isinstance(node, bpy.types.ShaderNodeVectorMath):
            result_node["parameters"] = {
                "operation": node.operation
            }
        elif isinstance(node, bpy.types.ShaderNodeDisplacement):
            result_node["parameters"] = {
                "space": node.space
            }
        elif isinstance(node, bpy.types.ShaderNodeTexNoise):
            result_node["parameters"] = {
                "noise_dimensions": node.noise_dimensions
            }
        elif isinstance(node, bpy.types.ShaderNodeRGBCurve):
            mapping = node.mapping
            result_node["parameters"] = {
                "black_level": list(mapping.black_level),
                "white_level": list(mapping.white_level),
                "clip_min_x": mapping.clip_min_x,
                "clip_min_y": mapping.clip_min_y,
                "clip_max_x": mapping.clip_max_x,
                "clip_max_y": mapping.clip_max_y,
                "extend": mapping.extend,
                "tone": mapping.tone,
                "curves": [[
                    {
                        "location": list(point.location),
                        "handle_type": point.handle_type
                    } for point in curve.points.values()
                ] for curve in mapping.curves.values()]
            }
        elif isinstance(node, bpy.types.ShaderNodeValToRGB):
            result_node["parameters"] = {
                "color_mode": node.color_ramp.color_mode,
                "interpolation": node.color_ramp.interpolation,
                "hue_interpolation": node.color_ramp.hue_interpolation,
                "elements": [{
                    "position": element.position,
                    "color": list(element.color)
                } for element in node.color_ramp.elements.values()]
            }
        elif isinstance(node, bpy.types.ShaderNodeMixRGB):
            result_node["parameters"] = {
                "blend_type": node.blend_type,
                "use_clamp": node.use_clamp
            }
        elif isinstance(node, bpy.types.ShaderNodeBsdfPrincipled):
            result_node["parameters"] = {
                "distribution": node.distribution,
                "subsurface_method": node.subsurface_method
            }
        elif isinstance(node, bpy.types.ShaderNodeMapping):
            result_node["parameters"] = {
                "type": node.type
            }
        elif isinstance(node, bpy.types.ShaderNodeNormalMap):
            result_node["parameters"] = {
                "space": node.space,
                "uv_map": node.uv_map
            }
        elif isinstance(node, bpy.types.ShaderNodeBsdfGlass):
            result_node["parameters"] = {
                "distribution": node.distribution
            }
        elif isinstance(node, bpy.types.ShaderNodeBsdfGlossy):
            result_node["parameters"] = {
                "distribution": node.distribution
            }
        elif isinstance(node, bpy.types.ShaderNodeBump):
            result_node["parameters"] = {
                "invert": node.invert
            }
        elif isinstance(node, bpy.types.ShaderNodeCombineColor):
            result_node["parameters"] = {
                "mode": node.mode
            }
        elif isinstance(node, bpy.types.ShaderNodeSeparateColor):
            result_node["parameters"] = {
                "mode": node.mode
            }
        elif isinstance(node, bpy.types.ShaderNodeUVMap):
            result_node["parameters"] = {
                "from_instancer": node.from_instancer,
                "uv_map": node.uv_map
            }
        elif isinstance(node, (
            bpy.types.ShaderNodeOutputMaterial,
            bpy.types.ShaderNodeTexCoord,
            bpy.types.ShaderNodeInvert,
            bpy.types.ShaderNodeBsdfTransparent,
            bpy.types.ShaderNodeBsdfTranslucent,
            bpy.types.ShaderNodeMixShader,
            bpy.types.ShaderNodeSeparateColor,
            bpy.types.ShaderNodeHueSaturation,
            bpy.types.ShaderNodeLightPath,
            bpy.types.ShaderNodeEmission,
            bpy.types.ShaderNodeNewGeometry,
            bpy.types.ShaderNodeBackground,
            bpy.types.ShaderNodeOutputWorld,
            bpy.types.ShaderNodeOutputLight,
            bpy.types.ShaderNodeGamma,
            bpy.types.ShaderNodeTexChecker,
            bpy.types.ShaderNodeBrightContrast,
            bpy.types.ShaderNodeFresnel,
            bpy.types.ShaderNodeBlackbody,
            bpy.types.ShaderNodeBsdfDiffuse
        )):
            # no parameters
            pass
        else:
            warn(f"Node type not supported: {node.bl_idname}")
        
        for input in node.inputs.values():
            result_node["inputs"][input.identifier] = result_input = {
                "type": input.type
            }

            if (link := rm_node.links.get(input.identifier)):
                result_input["links"] = [ link ]
            elif (value := rm_node.values.get(input.identifier)) is not None:
                result_input["value"] = value
        
        # patch incorrect output types
        if isinstance(material, bpy.types.Material) and isinstance(node, bpy.types.ShaderNodeOutputLight):
            result_node["type"] = "OUTPUT_MATERIAL"
        elif isinstance(material, bpy.types.Light) and isinstance(node, bpy.types.ShaderNodeOutputMaterial):
            result_node["type"] = "OUTPUT_LIGHT"
            if "Surface" in result_node["inputs"]:
                result_node["inputs"] = {
                    "Surface": result_node["inputs"]["Surface"]
                }
            else:
                result_node["inputs"] = {}
    
    return result
