import bpy
import mathutils


def flat_matrix(matrix):
    return [ x for row in matrix for x in row ]
