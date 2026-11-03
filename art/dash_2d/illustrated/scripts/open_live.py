import bpy
from pathlib import Path
root=Path(__file__).resolve().parents[1]
if bpy.data.is_dirty:bpy.ops.wm.save_as_mainfile(filepath=str(root/'previous-session-backup.blend'),copy=True)
bpy.ops.wm.open_mainfile(filepath=str(root/'dash_2d.blend'))
bpy.context.scene.frame_set(373)
for a in [a for w in bpy.context.window_manager.windows for a in w.screen.areas]:
 if a.type=='VIEW_3D':
  a.spaces.active.region_3d.view_perspective='CAMERA';a.spaces.active.shading.type='MATERIAL';a.spaces.active.overlay.show_overlays=False
result={'file':bpy.data.filepath,'scene':bpy.context.scene.name,'frame':bpy.context.scene.frame_current}
