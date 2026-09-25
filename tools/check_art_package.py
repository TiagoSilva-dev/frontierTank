"""Validate requested asset coverage, image integrity and preview references."""
import json,re
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT/'assets/expansion'
requests=json.loads((BASE/'asset_requests.json').read_text(encoding='utf-8-sig'))
inventory=json.loads((BASE/'file_inventory.json').read_text(encoding='utf-8'))
assert len(inventory)==len(requests),(len(inventory),len(requests))
for path,w,h,_ in requests:
    p=BASE/(path+'.png');im=Image.open(p);im.load()
    assert im.size==(w,h),(path,im.size)
    assert im.convert('RGBA').getchannel('A').getextrema()[1]>0,path
    if not path.startswith(('maps/','screens/')) and 'preview' not in path:
        assert im.convert('RGBA').getchannel('A').getextrema()[0]==0,('Missing transparency',path)
    else:
        assert im.convert('RGBA').getchannel('A').getextrema()[0]==255,('Background must be opaque',path)
for doc in ['frontier_visual_preview.html']:
    text=(ROOT/'docs'/doc).read_text(encoding='utf-8')
    for ref in re.findall(r'(?:src=\"|url\(\x27)(\.\./assets/[^\"\x27]+)',text):
        assert (ROOT/'docs'/ref).resolve().is_file(),ref
effect=BASE/'animations/card_flip_effect/preview.gif'
im=Image.open(effect);assert im.n_frames==8,im.n_frames
print(f'PASS: {len(requests)} requested static assets, dimensions, alpha, local HTML image paths, 8-frame reveal effect.')
