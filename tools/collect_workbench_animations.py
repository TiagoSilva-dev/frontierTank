"""Download exact PixelLab workbench sheets and export unchanged frame regions."""
import json, urllib.request
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'assets/expansion/animations'
entries=[('card_flip_effect','6503068b-d9ed-498c-a8e9-759ec00d036e','front',96,8,[70]*8,False,{'reveal':4}),('mask_king_idle','15c894d8-e5c2-4761-8feb-4c5b68c67786','left',144,4,[180]*4,True,{}),('mask_king_attack','e007a04b-3d93-44e2-aea4-1c945fecc89e','left',160,6,[100,100,140,80,80,140],False,{'cast':4})]
manifest={}
for name,uid,view,size,count,durations,loop,events in entries:
    folder=BASE/name;folder.mkdir(parents=True,exist_ok=True)
    base='https://api.pixellab.ai/mcp/pixel-tools/'+uid+'/'
    for source,target in [(f'assets/{view}/animation.gif','preview.gif'),(f'assets/{view}/full.png','spritesheet.png'),('recipe.json','recipe.json')]:
        if not (folder/target).exists(): urllib.request.urlretrieve(base+source,folder/target)
    sheet=Image.open(folder/'spritesheet.png').convert('RGBA')
    assert sheet.width%size==0 and sheet.height%size==0
    columns=sheet.width//size
    paths=[]
    for i in range(count):
        x=(i%columns)*size;y=(i//columns)*size
        target=folder/f'frame_{i:02d}.png'
        sheet.crop((x,y,x+size,y+size)).save(target)
        paths.append(str(target.relative_to(ROOT)).replace('\\','/'))
    manifest[name]={'provider':'PixelLab MCP pixelart_workbench','drawing_id':uid,'width':size,'height':size,'frames':paths,'durations_ms':durations,'loop':loop,'events_1_based':events,'sheet_columns':columns,'sheet_path':str((folder/'spritesheet.png').relative_to(ROOT)).replace('\\','/'),'method':'Exact sprite translation and authored VFX; not generative skeletal animation.'}
(BASE.parent/'animations_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print({name:len(data['frames']) for name,data in manifest.items()})
