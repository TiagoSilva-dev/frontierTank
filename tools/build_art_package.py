"""Build Godot registry and portable art/research archive without caches."""
import json, zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'assets/expansion'
files=json.loads((BASE/'file_inventory.json').read_text(encoding='utf-8'))
registry={item['id']:{'texture':'res://'+item['path'],'size':[item['width'],item['height']]} for item in files}
registry.update({'combat_tool_shield':{'texture':'res://assets/ui/icone_escudo.png'},'items_gold':{'texture':'res://assets/items/moeda.png'},'items_strength_stone_i':{'texture':'res://assets/items/pedra_fortalecimento.png'}})
animations=json.loads((BASE/'animations_manifest.json').read_text(encoding='utf-8'))
for name,animation in animations.items():
    registry['animation_'+name]={'frames':['res://'+p for p in animation['frames']], 'durations_ms':animation['durations_ms'], 'loop':animation['loop'], 'events_1_based':animation['events_1_based']}
(BASE/'godot_asset_registry.json').write_text(json.dumps(registry,indent=2),encoding='utf-8')
docs=['docs/DDTANK_RESEARCH.md','docs/ddtank_references.html','docs/ddtank_references.json','docs/frontier_visual_preview.html','docs/ART_DELIVERY_0_3.md','ART_BIBLE.md']
with zipfile.ZipFile(ROOT/'frontier_tank_art_research_0_3.zip','w',zipfile.ZIP_DEFLATED) as z:
    for p in (ROOT/'assets').rglob('*'):
        if p.is_file() and p.suffix not in ('.import',) and p.name!='original.zip' and 'superseded' not in p.parts: z.write(p,p.relative_to(ROOT))
    for f in docs: z.write(ROOT/f,f)
print(f'{len(registry)} resource mappings; archive ready')
