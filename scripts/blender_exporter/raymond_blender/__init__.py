from . import exporter_ui

bl_info = {
    "name": "Raymond Exporter",
    "author": "Alexander Rath",
    "description": "Export scene to raymond",
    "version": (0, 1, 0),
    "blender": (3, 2, 0),
    "location": "File > Import-Export",
    "category": "Import-Export",
    "tracker_url": "https://69co.de/alex/raymond/issues/new",
    "doc_url": "https://69co.de/alex/raymond",
    "support": "COMMUNITY",
}

def register():
    exporter_ui.register()

def unregister():
    exporter_ui.unregister()
