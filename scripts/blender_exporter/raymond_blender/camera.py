import bpy
from .utils import flat_matrix


def export_camera(camera: bpy.types.Camera):
    if camera is None:
        return None

    result = {
        "near_clip": camera.data.clip_start,
        "far_clip": camera.data.clip_end,
        "film": {
            "width": camera.data.sensor_width,
            "height": camera.data.sensor_height
        },
        "transform": flat_matrix(camera.matrix_world)
    }

    dof: bpy.types.CameraDOFSettings = camera.data.dof
    if dof.use_dof:
        result["dof"] = {
            "focus": dof.focus_distance,
            "fstop": dof.aperture_fstop
        }
    
    if camera.type == "ORTHO":
        result["type"] = "orthogonal"
        result["scale"] = 1 / camera.data.ortho_scale
    else:
        result["type"] = "perspective"
        result["focal_length"] = camera.data.lens
    
    return result


def export_render(render: bpy.types.RenderSettings):
    res_x = render.resolution_x * (render.resolution_percentage / 100)
    res_y = render.resolution_y * (render.resolution_percentage / 100)
    
    return {
        "resolution": {
            "width": res_x,
            "height": res_y
        }
    }
