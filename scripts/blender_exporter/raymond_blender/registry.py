import bpy

from .utils import find_unique_name

class ObjectRegistry(object):
    def __init__(self):
        self.converted: dict[str, dict] = {}
        self.names: dict[str, str] = {}
        self.internal_names: dict[str, str] = {}
    
    def _make_unique_name(self, name: str):
        return find_unique_name(self.converted, name)

    def internal_export(self, name: str, export_fn):
        if name not in self.internal_names:
            unique_name = self._make_unique_name(name)
            self.internal_names[name] = unique_name
            self.converted[unique_name] = export_fn(unique_name)
        return self.internal_names[name]
    
    def force_internal_export(self, name: str, converted: dict):
        unique_name = self._make_unique_name(name)
        self.converted[unique_name] = converted
        return unique_name
    
    def export(self, original: bpy.types.Object, export_fn):
        if original.name_full not in self.names:
            unique_name = self._make_unique_name(original.name)
            self.names[original.name_full] = unique_name
            self.converted[unique_name] = export_fn(unique_name)
        return self.names[original.name_full]

    def force_export(self, original: bpy.types.Object, converted: dict):
        unique_name = self._make_unique_name(original.name)
        self.converted[unique_name] = converted
        return unique_name


class SceneRegistry(object):
    def __init__(self, meshpath, texturepath):
        self.entities = ObjectRegistry()
        self.shapes = ObjectRegistry()
        self.materials = ObjectRegistry()
        self.lights = ObjectRegistry()
        self.images = ObjectRegistry()

        self.meshpath = meshpath
        self.texturepath = texturepath
