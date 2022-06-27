import bpy
from warnings import warn


def _export_tex_image(result, node: bpy.types.ShaderNodeTexImage):
    result["filepath"] = node.image.filepath


def _export_val_to_rgb(result, node: bpy.types.ShaderNodeValToRGB):
    result["elements"] = []
    for element in node.color_ramp.elements.values():
        result["elements"].append({
            "position": element.position,
            "color": list(element.color)
        })


def export_material(material: bpy.types.Material):
    result = {}
    
    if not material.use_nodes:
        warn(f"Material `{material.name}' does not use nodes and can therefore not be exported.")
        return result
    
    for node in material.node_tree.nodes.values():
        result[node.name] = result_node = {
            "type": node.type,
            "inputs": {}
        }
        
        if isinstance(node, bpy.types.ShaderNodeTexImage):
            _export_tex_image(result_node, node)
        elif isinstance(node, bpy.types.ShaderNodeValToRGB):
            _export_val_to_rgb(result_node, node)
        
        for input in node.inputs.values():
            result_node["inputs"][input.identifier] = result_input = {
                "type": input.type
            }

            if input.is_linked:
                result_input["links"] = [
                    (link.from_node.name, link.from_socket.identifier)
                    for link in list(input.links)
                ]
            elif hasattr(input, "default_value"):
                value = input.default_value
                if not isinstance(value, (int, float)):
                    value = list(value)
                result_input["value"] = value
    
    return result
