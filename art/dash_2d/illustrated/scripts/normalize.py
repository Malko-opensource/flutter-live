"""Separate complete illustrated poses by alpha connectivity, preserving authored art."""
from PIL import Image, ImageChops, ImageFilter, ImageDraw, ImageOps
from pathlib import Path
from collections import deque
import json,shutil
r=Path(__file__).resolve().parents[1];spec=json.loads((r/'generation-prompts.json').read_text());meta={}
for entry in spec['poses']:
 skin=entry['skin'];im=Image.open(r/entry['path']).convert('RGBA');w,h=im.size;a=im.getchannel('A');core=a.point(lambda v:255 if v>=235 else 0).filter(ImageFilter.MedianFilter(3));data=bytearray(core.tobytes());components=[]
 for idx in range(len(data)):
  if not data[idx]:continue
  data[idx]=0;q=deque([idx]);comp=[]
  while q:
   p=q.popleft();comp.append(p);x=p%w
   for n in ([p-1] if x else [])+([p+1] if x<w-1 else [])+([p-w] if p>=w else [])+([p+w] if p<len(data)-w else []):
    if data[n]:data[n]=0;q.append(n)
  if len(comp)>5000:components.append(comp)
 components=sorted(components,key=len,reverse=True)[:3];assert len(components)==3,(skin,len(components))
 components.sort(key=lambda c:sum(p%w for p in c)/len(c))
 dest=r/'poses'/skin;dest.mkdir(parents=True,exist_ok=True)
 for pose,comp in zip(['neutral','sing','megaphone'],components):
  pixels=bytearray(w*h)
  for p in comp:pixels[p]=255
  core=Image.frombytes('L',(w,h),bytes(pixels));pad=ImageOps.expand(core,border=1);ImageDraw.floodfill(pad,(0,0),255);holes=ImageChops.invert(pad).crop((1,1,w+1,h+1));core=ImageChops.lighter(core,holes)
  alpha=ImageChops.multiply(ImageChops.lighter(a,core),core.filter(ImageFilter.MaxFilter(3)));box=alpha.getbbox()
  assert box[0]>0 and box[2]<w and box[1]>0 and box[3]<h,(skin,pose,'source clipping',box)
  feet=[p%w for p in comp if p//w>box[3]-(box[3]-box[1])*.06];anchor=sum(feet)/len(feet)-box[0]+4
  sprite=im.copy();sprite.putalpha(alpha);sprite=sprite.crop(box);out=Image.new('RGBA',(sprite.width+8,sprite.height+8));out.paste(sprite,(4,4));out.save(dest/f'{pose}.png')
  meta[f'{skin}/{pose}']={'size':out.size,'anchorX':anchor,'unit':2.8/(h*.78),'sourceBox':box}
(r/'poses-manifest.json').write_text(json.dumps(meta,indent=2)+'\n');print(meta)
