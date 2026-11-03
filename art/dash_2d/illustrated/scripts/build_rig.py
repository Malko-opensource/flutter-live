"""Coherent-pose 2D deformation rig. Preserves the finished illustration and prop contacts."""
import bpy, math, json
from pathlib import Path
from mathutils import Vector
r=Path(__file__).resolve().parents[1];meta=json.loads((r/'poses-manifest.json').read_text())
bpy.ops.wm.read_factory_settings(use_empty=True);s=bpy.context.scene;s.name='Dash_Illustrated';s.render.engine='BLENDER_EEVEE';s.render.resolution_x=s.render.resolution_y=512;s.render.resolution_percentage=100;s.render.film_transparent=True;s.render.image_settings.file_format='PNG';s.render.image_settings.color_mode='RGBA';s.render.fps=24;s.view_settings.view_transform='Standard';s.view_settings.look='None'
world=bpy.data.worlds.new('Studio');s.world=world
camdata=bpy.data.cameras.new('Orthographic');cam=bpy.data.objects.new('Camera',camdata);s.collection.objects.link(cam);cam.location=(0,-8,1.65);cam.rotation_euler=(Vector((0,0,1.65))-cam.location).to_track_quat('-Z','Y').to_euler();camdata.type='ORTHO';camdata.ortho_scale=3.9;s.camera=cam
arm=bpy.data.armatures.new('Illustration_Deform_Bones');rig=bpy.data.objects.new('Dash2D_Rig',arm);s.collection.objects.link(rig);bpy.context.view_layer.objects.active=rig;rig.select_set(True);rig.show_in_front=True;bpy.ops.object.mode_set(mode='EDIT');bones={}
def bone(n,x,z,parent=None):
 b=arm.edit_bones.new(n);b.head=(x,0,z);b.tail=(x,.15,z)
 if parent:b.parent=bones[parent]
 bones[n]=b
bone('Root',0,0)
pivots={'neutral':[(-.62,1.35),(.65,1.0)],'sing':[(-.55,1.35),(.62,1.5)],'megaphone':[(-.60,.95),(.62,1.5)]}
for pose in pivots:
 bone(pose,0,1.4,'Root')
 for side,(x,z) in zip(['L','R'],pivots[pose]):bone(pose+'.'+side,x,z,pose)
 bone(pose+'.Jaw',.06,1.65,pose)
for n,x,z in [('Note.L',-1.25,2.1),('Note.R',1.28,2.35),('Star.L',-1.25,2.5),('Star.R',1.22,.9),('Wave.1',1.3,1.65),('Wave.2',1.5,1.65),('Wave.3',1.7,1.65)]:bone(n,x,z,'Root')
bpy.ops.object.mode_set(mode='OBJECT');rig['rig_type']='2D coherent-pose mesh deformation';rig['instructions']='Three illustrated poses per costume. Eight NLA clips. Weighted wing and mouth motion preserves original illustration. No independent eye layers or phoneme lip sync.'
collections={}
for skin in ['hanbok','gat','dancheong']:
 co=bpy.data.collections.new('Skin_'+skin);s.collection.children.link(co);collections[skin]=co
shared=bpy.data.collections.new('Shared_Props_FX');s.collection.children.link(shared)
def material(path):
 name=str(path);m=bpy.data.materials.get(name)
 if m:return m
 m=bpy.data.materials.new(name);m.use_nodes=True;ns=m.node_tree.nodes;ns.clear();links=m.node_tree.links
 tex=ns.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(name,check_existing=True);tex.interpolation='Linear';em=ns.new('ShaderNodeEmission');tr=ns.new('ShaderNodeBsdfTransparent');mix=ns.new('ShaderNodeMixShader');out=ns.new('ShaderNodeOutputMaterial');links.new(tex.outputs['Color'],em.inputs[0]);links.new(tex.outputs['Alpha'],mix.inputs[0]);links.new(tr.outputs[0],mix.inputs[1]);links.new(em.outputs[0],mix.inputs[2]);links.new(mix.outputs[0],out.inputs[0]);m.surface_render_method='DITHERED';m.use_transparency_overlap=False
 return m
def deform(obj):
 obj.parent=rig;mod=obj.modifiers.new('Illustration deformation','ARMATURE');mod.object=rig

def fall(x,z,cx,cz,rx,rz):
 v=max(0,1-((x-cx)/rx)**2-((z-cz)/rz)**2);return v*v*(3-2*v)
for skin,co in collections.items():
 for pose in pivots:
  info=meta[skin+'/'+pose];w,h=info['size'];unit=info['unit'];anchor=info['anchorX'];offset=-.25 if pose=='megaphone' else 0;nx,ny=64,80;verts=[];uvs=[];faces=[]
  for j in range(ny+1):
   for i in range(nx+1):
    u=i/nx;v=j/ny;verts.append(((u*w-anchor)*unit+offset,0,v*h*unit+.17));uvs.append((u,v))
  for j in range(ny):
   for i in range(nx):
    a=j*(nx+1)+i;faces.append((a,a+1,a+nx+2,a+nx+1))
  mesh=bpy.data.meshes.new(skin+'_'+pose);mesh.from_pydata(verts,[],faces);mesh.update();uv=mesh.uv_layers.new(name='UVMap')
  for loop in mesh.loops:uv.data[loop.index].uv=uvs[loop.vertex_index]
  obj=bpy.data.objects.new(skin+'_'+pose,mesh);co.objects.link(obj);obj.data.materials.append(material(r/'poses'/skin/f'{pose}.png'));deform(obj)
  groups={n:obj.vertex_groups.new(name=n) for n in [pose,pose+'.L',pose+'.R',pose+'.Jaw']}
  for i,(x,y,z) in enumerate(verts):
   # Broad soft falloff, small rotations: no hard seams through the artwork.
   left=fall(x,z,-.86,1.45 if pose=='neutral' else 1.38,.48,.52)*.92
   right=fall(x,z,.91,1.60 if pose=='sing' else .95,.55,.52)*.92
   jaw=fall(x,z,.06,1.65,.22,.24)*.65 if pose=='sing' else 0
   if pose=='megaphone':left=right=jaw=0 # preserve mouthpiece / grip / horn alignment as one illustrated gesture
   total=left+right+jaw;denom=max(1,total)
   for name,weight in [(pose,max(0,1-total/denom)),(pose+'.L',left/denom),(pose+'.R',right/denom),(pose+'.Jaw',jaw/denom)]:
    if weight>0:groups[name].add([i],weight,'REPLACE')
# Independent note/star effects use the existing generated illustrations.
def fx(name,x,z,width,file):
 path=r/'effects'/file;mat=material(path);img=mat.node_tree.nodes.get('Image Texture').image;height=width*img.size[1]/img.size[0]
 mesh=bpy.data.meshes.new(name);mesh.from_pydata([(x-width/2,-.1,z-height/2),(x+width/2,-.1,z-height/2),(x+width/2,-.1,z+height/2),(x-width/2,-.1,z+height/2)],[],[(0,1,2,3)]);mesh.update();uv=mesh.uv_layers.new(name='UVMap')
 for loop,coord in zip(mesh.loops,[(0,0),(1,0),(1,1),(0,1)]):uv.data[loop.index].uv=coord
 obj=bpy.data.objects.new(name,mesh);shared.objects.link(obj);obj.data.materials.append(mat);obj.vertex_groups.new(name=name).add([0,1,2,3],1,'REPLACE');deform(obj)
for name,x,z,file in [('Note.L',-1.25,2.1,'note.png'),('Note.R',1.28,2.35,'note.png'),('Star.L',-1.25,2.5,'star.png'),('Star.R',1.22,.9,'star.png')]:fx(name,x,z,.16,file)
mat=bpy.data.materials.new('Sound cyan');mat.use_nodes=True;ns=mat.node_tree.nodes;ns.clear();em=ns.new('ShaderNodeEmission');em.inputs[0].default_value=(.03,.8,1,1);out=ns.new('ShaderNodeOutputMaterial');mat.node_tree.links.new(em.outputs[0],out.inputs[0])
for k in range(3):
 x=1.3+k*.2;radius=.14+k*.09;verts=[]
 for j in range(17):
  a=-.95+j/16*1.9
  for rr in [radius-.012,radius+.012]:verts.append((x+rr*(math.cos(a)-1),-.1,1.65+rr*math.sin(a)))
 mesh=bpy.data.meshes.new('Sound_Ray');mesh.from_pydata(verts,[],[(2*j,2*j+1,2*j+3,2*j+2) for j in range(16)]);mesh.update();obj=bpy.data.objects.new('Sound_Ray_'+str(k+1),mesh);shared.objects.link(obj);obj.data.materials.append(mat);obj.vertex_groups.new(name='Wave.'+str(k+1)).add(list(range(len(verts))),1,'REPLACE');deform(obj)
rig.animation_data_create();manifest=[]
for idx,clip in enumerate(['idle','listen','speak','wave','celebrate','reconnect','sing','megaphone']):
 start=1+idx*60;act=bpy.data.actions.new('Dash_'+clip);rig.animation_data.action=act
 pose='megaphone' if clip=='megaphone' else 'sing' if clip in ['sing','speak','celebrate'] else 'neutral'
 for f in range(49):
  t=f/48;a=math.tau*t;ss=math.sin(a);cc=math.cos(a);pb=rig.pose.bones
  for b in pb:b.location=(0,0,0);b.rotation_mode='XYZ';b.rotation_euler=(0,0,0);b.scale=(1,1,1)
  def show(n,on):pb[n].scale=(1,1,1) if on else (.00001,)*3
  for n in pivots:show(n,n==pose)
  for n in ['Note.L','Note.R']:show(n,clip in ['sing','speak'])
  for n in ['Star.L','Star.R']:show(n,clip in ['wave','celebrate'])
  for k in range(3):show('Wave.'+str(k+1),clip=='megaphone')
  b=pb[pose];b.location.z=.016*(1-cc);b.rotation_euler.y=.018*ss if clip!='idle' else 0
  if clip=='wave':pb['neutral.L'].rotation_euler.y=.13*math.sin(a*2)
  if clip=='listen':b.rotation_euler.y=.035*ss;pb['neutral.L'].rotation_euler.y=.035*ss
  if clip=='reconnect':b.rotation_euler.y=.04*ss;b.location.x=.025*ss
  if clip in ['sing','speak','celebrate']:
   pb['sing.L'].rotation_euler.y=.025*ss;pb['sing.R'].rotation_euler.y=.08*math.sin(a*2);pb['sing.Jaw'].scale.z=1-.07*(1-math.cos(a*3))
  if clip=='celebrate':b.location.z=.09*(1-cc);pb['sing.R'].rotation_euler.y=.14*math.sin(a*2)
  for k,n in enumerate(['Note.L','Note.R','Star.L','Star.R']):
   if pb[n].scale.x>.5:pb[n].location.z=.08*math.sin(a+k);pb[n].rotation_euler.y=.12*math.sin(a+k)
  for k in range(3):
   n='Wave.'+str(k+1)
   if clip=='megaphone':pb[n].scale=(.85+.15*math.sin(a*2-k),1,.85+.15*math.sin(a*2-k));pb[n].location.x=.03*math.sin(a*2-k)
  for p in pb:
   for path in ['location','rotation_euler','scale']:p.keyframe_insert(data_path=path,frame=start+f,group=p.name)
 for layer in act.layers:
  for strip in layer.strips:
   for bag in strip.channelbags:
    for fc in bag.fcurves:
     for key in fc.keyframe_points:key.interpolation='LINEAR'
 rig.animation_data.action=None;track=rig.animation_data.nla_tracks.new();track.name=clip;strip=track.strips.new(clip,start,act);strip.extrapolation='NOTHING';s.timeline_markers.new(clip,frame=start);manifest.append({'name':clip,'start':start,'end':start+48,'fps':24,'renderFrames':24})
s.frame_start=1;s.frame_end=469;s.frame_set(1)
for skin,co in collections.items():co.hide_render=co.hide_viewport=(skin!='hanbok')
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(r/'dash_2d.blend'));(r/'animation-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
s.render.resolution_x=s.render.resolution_y=512
for skin in collections:
 for name,co in collections.items():co.hide_render=name!=skin
 for clip,frame in [('idle',1),('sing',373),('megaphone',433)]:s.frame_set(frame);s.render.filepath=str(r/'renders'/f'{skin}-{clip}.png');bpy.ops.render.render(write_still=True)
result={'bones':len(arm.bones),'meshes':len([o for o in bpy.data.objects if o.type=='MESH']),'clips':8,'source':str(r/'dash_2d.blend')}
