"""Render fixed-anchor 24-frame clips. Replace SKIN before official MCP execution."""
import bpy,json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
skin='dancheong'
scene=bpy.context.scene
scene.render.resolution_x=scene.render.resolution_y=512
for name in ['hanbok','gat','dancheong']:bpy.data.collections['Skin_'+name].hide_render=(name!=skin)
for entry in json.loads((root/'animation-manifest.json').read_text()):
 out=root/'renders/frames'/skin/entry['name'];out.mkdir(parents=True,exist_ok=True)
 for i in range(24):
  scene.frame_set(entry['start']+i*2);scene.render.filepath=str(out/f'{i:03}.png');bpy.ops.render.render(write_still=True)
result={'skin':skin,'frames':192,'size':512}
