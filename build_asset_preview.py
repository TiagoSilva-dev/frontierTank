from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).parent
files = sorted(p for p in (ROOT / 'assets').rglob('*.png') if 'preview' not in p.name)
cards = []
for path in files:
    im = Image.open(path).convert('RGBA')
    if im.width > 1000 or im.height > 1000:
        continue
    card = Image.new('RGB', (260, 220), '#182342')
    scale = min(240 / im.width, 175 / im.height)
    im = im.resize((max(1, int(im.width*scale)), max(1, int(im.height*scale))), Image.NEAREST)
    card.paste(im, ((260-im.width)//2, (180-im.height)//2), im)
    draw = ImageDraw.Draw(card)
    draw.text((10, 184), path.stem[:36], fill='#FFF0C2')
    draw.text((10, 201), str(path.parent.relative_to(ROOT / 'assets')), fill='#63D6EF')
    cards.append(card)
cols = 4
rows = (len(cards)+cols-1)//cols
sheet = Image.new('RGB', (cols*270+10, rows*230+55), '#0C1326')
ImageDraw.Draw(sheet).text((18, 18), 'FRONTIER TANK: NOVA ERA | PIXELLAB ASSET PACK', fill='#EAB34D')
for i, card in enumerate(cards):
    sheet.paste(card, (10+(i%cols)*270, 45+(i//cols)*230))
sheet.save(ROOT / 'assets' / 'preview.png')
print(f'{len(cards)} PNGs in preview')
