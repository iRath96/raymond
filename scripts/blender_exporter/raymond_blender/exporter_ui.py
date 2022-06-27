import mathutils

import bpy
from bpy.props import (
    BoolProperty,
    FloatProperty,
    StringProperty
)
from bpy_extras.io_utils import (
    ExportHelper
)
from bpy_extras.wm_utils.progress_report import (
    ProgressReport
)

from .exporter import *


class ExportRaymond(bpy.types.Operator, ExportHelper):
    """Export scene to raymond"""

    bl_idname = "export_scene.raymond"
    bl_label = "Export raymond Scene"
    bl_description = "Export scene to raymond"
    bl_options = {'PRESET'}

    filename_ext = ".json"
    filter_glob: StringProperty(
        default="*.json",
        options={'HIDDEN'}
    )

    use_selection: BoolProperty(
        name="Selection Only",
        description="Export selected objects only",
        default=False,
    )

    animations: BoolProperty(
        name="Export Animations",
        description="If true, writes .json for each frame in the animation.",
        default=False,
    )

    check_extension = True

    def execute(self, context):
        keywords = self.as_keywords(
            ignore=(
                "filepath",
                "filter_glob",
                "animations",
                "check_existing"
            ),
        )

        with ProgressReport(context.window_manager) as progress:
            # Exit edit mode before exporting, so current object states are exported properly.
            if bpy.ops.object.mode_set.poll():
                bpy.ops.object.mode_set(mode='OBJECT')

            if self.animations is True:
                scene_frames = range(
                    context.scene.frame_start, context.scene.frame_end + 1)
                progress.enter_substeps(len(scene_frames))
                for frame in scene_frames:
                    context.scene.frame_set(frame)
                    progress.enter_substeps(1)
                    export_scene(self.filepath.replace(
                        '.json', f'{frame:04}.json'), context, **keywords)
                progress.leave_substeps()
            else:
                export_scene(self.filepath, context, **keywords)
        return {'FINISHED'}

    def draw(self, context):
        pass


class RAYMOND_PT_export_include(bpy.types.Panel):
    bl_space_type = 'FILE_BROWSER'
    bl_region_type = 'TOOL_PROPS'
    bl_label = "Include"
    bl_parent_id = "FILE_PT_operator"

    @classmethod
    def poll(cls, context):
        sfile = context.space_data
        operator = sfile.active_operator

        return operator.bl_idname == "EXPORT_SCENE_OT_RAYMOND"

    def draw(self, context):
        layout = self.layout
        layout.use_property_split = True
        layout.use_property_decorate = False  # No animation.

        sfile = context.space_data
        operator = sfile.active_operator

        col = layout.column(heading="Limit to")
        col.prop(operator, 'use_selection')

        layout.separator()
        
        layout.prop(operator, 'animations')


def menu_func_export(self, context):
    self.layout.operator(ExportRaymond.bl_idname, text="raymond (.json)")


classes = (
    ExportRaymond,
    RAYMOND_PT_export_include
)


def register():
    for cls in classes:
        bpy.utils.register_class(cls)
    bpy.types.TOPBAR_MT_file_export.append(menu_func_export)


def unregister():
    bpy.types.TOPBAR_MT_file_export.remove(menu_func_export)
    for cls in classes:
        bpy.utils.unregister_class(cls)


if __name__ == "__main__":
    register()
