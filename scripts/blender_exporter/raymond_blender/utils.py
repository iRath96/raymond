import bpy
import mathutils


def flat_matrix(matrix):
    return [ x for row in matrix for x in row ]


def find_unique_name(used: set[str], name: str):
    if not name in used:
        return name
    
    i = 1
    while True:
        candidate = f"{name}.{i:03d}"
        if not candidate in used:
            return candidate
        i += 1
