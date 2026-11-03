import bpy
bpy.context.scene.render.resolution_x=bpy.context.scene.render.resolution_y=512
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
result={'resolution':512,'source':bpy.data.filepath}
