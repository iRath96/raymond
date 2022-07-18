import bpy
from warnings import warn


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
        
        result_node["parameters"] = {}
        if isinstance(node, bpy.types.ShaderNodeTexImage):
            result_node["parameters"] = {
                "filepath": node.image.filepath,
                "interpolation": node.interpolation,
                "projection": node.projection,
                "extension": node.extension,
                "source": node.image.source,
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
            bpy.types.ShaderNodeMixShader,
            bpy.types.ShaderNodeSeparateColor,
            bpy.types.ShaderNodeHueSaturation,
            bpy.types.ShaderNodeLightPath,
            bpy.types.ShaderNodeEmission,
            bpy.types.ShaderNodeNewGeometry
        )):
            # no parameters
            pass
        else:
            warn(f"Node type not supported: {node}")
        
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
