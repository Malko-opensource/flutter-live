"""Package the official Blender renders; preserve a shared canvas/anchor for every clip."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json,hashlib,shutil,sys
root=Path(__file__).resolve().parents[1];art=root/(sys.argv[1] if len(sys.argv)>1 else 'art/dash_2d/illustrated')
clips=json.loads((art/'animation-manifest.json').read_text());skins=['hanbok','gat','dancheong']
font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',18)
tile=Image.open(art/'renders/frames/hanbok/idle/000.png').width
frames={};report=[]
contact=Image.new('RGB',(256*8,288*3),'#eff4f8');draw=ImageDraw.Draw(contact)
for row,skin in enumerate(skins):
 dest=root/'assets/dash'/skin;dest.mkdir(parents=True,exist_ok=True)
 for col,clip in enumerate(clips):
  name=clip['name'];images=[Image.open(art/'renders/frames'/skin/name/f'{f:03}.png').convert('RGBA') for f in range(24)]
  hashes=set();bounds=[]
  atlas=Image.new('RGBA',(tile*6,tile*4))
  for i,img in enumerate(images):
   assert img.size==(tile,tile)
   a=img.getchannel('A');box=a.point(lambda v:255 if v>64 else 0).getbbox()
   assert box and min(box[0],box[1])>1 and max(box[2],box[3])<tile-1,(skin,name,i,box)
   assert a.getextrema()==(0,255),(skin,name,'not RGBA')
   hashes.add(hashlib.sha256(img.tobytes()).hexdigest());bounds.append(box)
   atlas.paste(img,((i%6)*tile,(i//6)*tile))
  assert len(hashes)>8,(skin,name,'animation missing')
  atlas.save(dest/f'{name}.png',optimize=True);frames[skin,name]=images
  img=images[6].resize((256,256),Image.Resampling.LANCZOS);contact.paste(img,(col*256,row*288),img);draw.text((col*256+16,row*288+261),f'{skin} / {name}',font=font,fill='#173451')
  report.append({'skin':skin,'clip':name,'frames':24,'uniqueFrames':len(hashes),'bounds':[min(b[0] for b in bounds),min(b[1] for b in bounds),max(b[2] for b in bounds),max(b[3] for b in bounds)]})
 frames[skin,'idle'][0].save(dest/'poster.png')
contact.save(art/'renders/contact-sheet.jpg',quality=94)
preview=[]
for i in range(24):
 im=Image.new('RGB',(900,960),'#eff4f8');d=ImageDraw.Draw(im)
 for row,skin in enumerate(skins):
  for col,clip in enumerate(['wave','sing','megaphone']):
   pose_image=frames[skin,clip][i].resize((300,300),Image.Resampling.LANCZOS);im.paste(pose_image,(col*300,row*320),pose_image)
   d.text((col*300+18,row*320+298),f'{skin} / {clip}',fill='#173451',font=font)
 preview.append(im)
preview[0].save(art/'renders/motion-preview.webp',save_all=True,append_images=preview[1:],duration=83,loop=0,quality=88,method=4)
preview[6].save(art/'renders/preview.png')
shutil.copyfile(root/'assets/dash/hanbok/poster.png',root/'assets/images/dash.png')
manifest={'source':str(art.relative_to(root)/'dash_2d.blend'),'type':'2d-weighted-cutout','defaultSkin':'hanbok','skins':skins,'columns':6,'rows':4,'tile':tile,'fps':12,'frameCount':24,'clips':[c['name'] for c in clips]}
(root/'assets/dash/manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
(art/'render-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print({'atlases':len(report),'frames':len(report)*24,'allAnimationsPresent':True,'clipping':False,'bytes':sum(p.stat().st_size for skin in skins for p in (root/'assets/dash'/skin).glob('*.png'))})

# Compact art-direction review: three costumes, same greeting loop.
style=[]
label_font=ImageFont.truetype('/System/Library/Fonts/AppleSDGothicNeo.ttc',22)
for i in range(24):
 im=Image.new('RGB',(900,340),'#f4f8fd');d=ImageDraw.Draw(im)
 for col,(skin,label) in enumerate(zip(skins,['한복','갓 · 두루마기','단청 무대'])):
  pose_image=frames[skin,'wave'][i].resize((300,300),Image.Resampling.LANCZOS);im.paste(pose_image,(col*300,0),pose_image)
  d.text((col*300+150,308),label,font=label_font,fill='#16304e',anchor='mm')
 style.append(im)
style[0].save(art/'renders/style-preview.webp',save_all=True,append_images=style[1:],duration=83,loop=0,quality=92,method=4)
