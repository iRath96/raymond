import os
from warnings import warn
import bmesh
import bpy

# SPDX-License-Identifier: GPL-2.0-or-later

"""
This script exports Stanford PLY files from Blender. It supports normals,
colors, and texture coordinates per face or per vertex.
"""

import bpy


def _write_ascii(fw, ply_verts: list, ply_faces: list) -> None:

    # Vertex data
    # ---------------------------

    for v, normal, uv in ply_verts:
        fw(b"%.6f %.6f %.6f" % v.co[:])
        fw(b" %.6f %.6f %.6f" % normal[:])
        fw(b" %.6f %.6f" % uv)
        fw(b"\n")

    # Face data
    # ---------------------------

    for (mat_id,pf) in ply_faces:
        fw(b"%d" % len(pf))
        for index in pf:
            fw(b" %d" % index)
        fw(b" %d" % mat_id)
        fw(b"\n")


def ply_save(filepath, bm: bmesh.types.BMesh):
    uv_lay = bm.loops.layers.uv.active

    normal = uv = None

    ply_faces = []
    ply_verts = []
    ply_vert_map = {}
    ply_vert_id = 0

    for f_hack in bm.faces:
        f: bmesh.types.BMFace = f_hack

        pf = []

        # @todo we should also be exporting vertices that do not belong to any loop,
        # as the default generated UV maps rely on the bounds of the object
        for loop in f.loops:
            v = map_id = loop.vert

            if f.smooth:
                normal = v.normal
            else:
                normal = f.normal

            if uv_lay is None:
                uv = (0, 0)
            else:
                uv = loop[uv_lay].uv[:]
            
            map_id = (v, tuple(normal), tuple(uv))

            # Identify vertex by pointer unless exporting UVs,
            # in which case id by UV coordinate (will split edges by seams).
            if (_id := ply_vert_map.get(map_id)) is not None:
                pf.append(_id)
                continue

            ply_verts.append((v, normal, uv))
            ply_vert_map[map_id] = ply_vert_id
            pf.append(ply_vert_id)
            ply_vert_id += 1
        
        ply_faces.append((f.material_index, pf))

    with open(filepath, "wb") as file:
        fw = file.write
        file_format = b"ascii"

        # Header
        # ---------------------------

        fw(b"ply\n")
        fw(b"format %s 1.0\n" % file_format)
        fw(b"comment Copyright raymond exporter research team\n")

        fw(b"element vertex %d\n" % len(ply_verts))
        fw(
            b"property float x\n"
            b"property float y\n"
            b"property float z\n"
        )
        fw(
            b"property float nx\n"
            b"property float ny\n"
            b"property float nz\n"
        )
        fw(
            b"property float s\n"
            b"property float t\n"
        )

        fw(b"element face %d\n" % len(ply_faces))
        fw(b"property list uchar uint vertex_indices\n")
        fw(b"property uchar material_index\n")
        fw(b"end_header\n")

        # Geometry
        # ---------------------------

        _write_ascii(fw, ply_verts, ply_faces)


# The following "solidification" does not work due to:
# https://developer.blender.org/T99249
# After fixing, it should work without explicit handling "non-smooth" faces from our side
def _solidify_bmesh(bm):
    """Will fix vertex normals if given face is solid."""

    solid_faces = [ f for f in bm.faces if not f.smooth ]
    for f in solid_faces:
        verts_modified = False
        new_verts = []
        for vert in f.verts:
            if len(vert.link_faces) > 1:  # Only care about vertices shared by multiple faces
                new_vert = bm.verts.new(vert.co, vert)
                new_vert.copy_from(vert)
                new_vert.normal = f.normal
                new_vert.index = len(bm.verts) - 1
                new_verts.append(new_vert)
                verts_modified = True
            else:
                vert.normal = f.normal
                new_verts.append(vert)

        if verts_modified:
            bm.faces.new(new_verts, f)
            bm.faces.remove(f)


def get_shape_name_base(obj):
    return obj.original.data.name  # We use the original mesh name!


def _export_bmesh_by_material(me: bpy.types.Mesh, name: str, meshpath: str):
    # split bms by materials
    bm = bmesh.new()
    bm.from_mesh(me)

    bmesh.ops.triangulate(bm, faces=bm.faces)

    # Solidify if necessary
    #_solidify_bmesh(bm)

    if me.use_auto_smooth:
        warn("'Auto Smooth' not supported!")
    
    bm.normal_update()

    filepath = os.path.join(meshpath, f"{name}.ply")
    ply_save(filepath, bm)

    bm.free()
    return {
        "type": "ply",
        "filepath": filepath,
        "materials": [
            ("__DEFAULT" if mat is None else mat.name)
            for mat in me.materials.values()
        ]
    }


def export_shape(obj: bpy.types.Object, depsgraph: bpy.types.Depsgraph, meshpath: str):
    name = get_shape_name_base(obj)

    try:
        me = obj.to_mesh(preserve_all_data_layers=False, depsgraph=depsgraph)
    except RuntimeError:
        return []

    shapes = _export_bmesh_by_material(me, name, meshpath)
    obj.to_mesh_clear()

    return shapes
