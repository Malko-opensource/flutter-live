import bpy,json
from pathlib import Path
root=Path(__file__).resolve().parents[1];rig=bpy.data.objects['Dash2D_Rig'];scene=bpy.context.scene
manifest=json.loads((root/'animation-manifest.json').read_text());checks=[]
assert len(rig.animation_data.nla_tracks)==8
for clip in manifest:
 scene.frame_set(clip['start']);first={p.name:p.matrix.copy() for p in rig.pose.bones}
 scene.frame_set(clip['end']);end={p.name:p.matrix.copy() for p in rig.pose.bones}
 error=max(abs(first[n][i][j]-end[n][i][j]) for n in first for i in range(4) for j in range(4));assert error<1e-5,(clip,error)
 scene.frame_set(clip['start']+12);changed=[p.name for p in rig.pose.bones if max(abs(first[p.name][i][j]-p.matrix[i][j]) for i in range(4) for j in range(4))>1e-4];assert len(changed)>2
 checks.append({'clip':clip['name'],'loopError':error,'movingBones':changed})
meshes=[o for o in bpy.data.objects if o.type=='MESH']
assert all(any(m.type=='ARMATURE' and m.object==rig for m in o.modifiers) for o in meshes)
assert all(len(o.data.uv_layers)==1 for o in meshes if not o.name.startswith('Sound_Ray'))
images=[i for i in bpy.data.images if i.source=='FILE'];assert all(i.packed_file for i in images)
result={'bones':len(rig.data.bones),'weightedMeshes':len(meshes),'packedTextures':len(images),'actions':checks,'skins':['hanbok','gat','dancheong']}
(root/'rig-validation.json').write_text(json.dumps(result,indent=2)+'\n')
