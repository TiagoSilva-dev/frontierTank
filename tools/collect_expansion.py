"""Download PixelLab jobs, verify PNGs and build a browsable asset catalog."""
import json, urllib.request, zipfile, io, hashlib, html
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'assets/expansion'

def main():
    manifest = json.loads((BASE/'generation_manifest.json').read_text(encoding='utf-8-sig'))
    inventory = []
    for job in manifest['jobs']:
        if not job.get('download'):
            continue
        target = BASE / (job['path'] + '.png')
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists():
            req = urllib.request.Request(job['download'], headers={'User-Agent':'FrontierTankAssetCollector/1.0'})
            data = urllib.request.urlopen(req, timeout=90).read()
            if zipfile.is_zipfile(io.BytesIO(data)):
                with zipfile.ZipFile(io.BytesIO(data)) as z:
                    names = sorted(n for n in z.namelist() if n.lower().endswith('.png'))
                    if len(names) != 1:
                        raise ValueError(f'Expected single PNG: {job["path"]}, {names}')
                    data = z.read(names[0])
            Image.open(io.BytesIO(data)).verify()
            target.write_bytes(data)
        with Image.open(target) as im:
            im.load()
            rgba = im.convert('RGBA')
            inventory.append({'id':job['path'].replace('/','_'), 'path':str(target.relative_to(ROOT)).replace('\\','/'), 'width':im.width, 'height':im.height, 'alpha_extrema':rgba.getchannel('A').getextrema(), 'sha256':hashlib.sha256(target.read_bytes()).hexdigest(), 'job_id':job['job_id']})
    (BASE/'file_inventory.json').write_text(json.dumps(inventory,indent=2),encoding='utf-8')
    cards=[]
    for item in inventory:
        im=Image.open(ROOT/item['path']).convert('RGBA')
        factor=max(1,min(3,224//im.width,144//im.height))
        im=im.resize((im.width*factor,im.height*factor),Image.NEAREST)
        card=Image.new('RGB',(280,208),'#182342')
        card.paste(im,((280-im.width)//2,max(0,(160-im.height)//2)),im)
        d=ImageDraw.Draw(card)
        d.text((8,166),item['id'],fill='#fff0c2')
        d.text((8,187),f'{item["width"]} x {item["height"]} | PixelLab',fill='#63d6ef')
        cards.append(card)
    sheet=Image.new('RGB',(1120,((len(cards)+3)//4)*208),'#0c1326')
    for i,c in enumerate(cards): sheet.paste(c,((i%4)*280,(i//4)*208))
    sheet.save(BASE/'catalog.png')
    for page in range((len(cards)+15)//16):
        sheet.crop((0,page*832,1120,min(sheet.height,(page+1)*832))).save(BASE/f'catalog_{page+1}.png')
    tiles=''.join(f'<article><a href="{html.escape(j["path"])}.png"><img src="{html.escape(j["path"])}.png"></a><p>{html.escape(j["path"])}</p></article>' for j in manifest['jobs'] if j.get('download'))
    (BASE/'index.html').write_text('<!doctype html><meta charset="utf-8"><title>Frontier Tank — PixelLab</title><style>body{background:#0c1326;color:#fff0c2;font:16px system-ui;padding:32px}main{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:16px}article{background:#182342;padding:16px;text-align:center}img{image-rendering:pixelated;max-width:100%;height:144px;object-fit:contain}a{color:#63d6ef}</style><h1>Frontier Tank · PixelLab</h1><p>Assets originais. Textos, valores e estados devem ser renderizados pelo jogo.</p><main>'+tiles+'</main>',encoding='utf-8')
    print(f'{len(inventory)} PNGs downloaded and verified')

if __name__=='__main__': main()
