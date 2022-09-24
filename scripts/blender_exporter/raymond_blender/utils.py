import bpy


def flat_matrix(matrix):
    return [ x for row in matrix for x in row ]


def find_unique_name(used: set[str], name: str):
    unique_name = name
    index = 0

    while unique_name in used:
        unique_name = f"{name}.{index:03d}"
        index += 1
    
    return unique_name


def describe_visibility(object: bpy.types.Object):
    return {
        "camera": object.visible_camera,
        "diffuse": object.visible_diffuse,
        "glossy": object.visible_glossy,
        "transmission": object.visible_transmission,
        "volume": object.visible_volume_scatter,
        "shadow": object.visible_shadow
    }


def describe_cycles_visibility(object):
    return {
        "camera": object.camera,
        "diffuse": object.diffuse,
        "glossy": object.glossy,
        "transmission": object.transmission,
        "volume": object.scatter,
        "shadow": object.shadow
    }
