"""Download completed image jobs recorded in the local MCP manifest."""
import json
import urllib.request
from pathlib import Path

ROOT = Path(__file__).parent
manifest = json.loads((ROOT/'assets/pixellab_manifest.json').read_text(encoding='utf-8-sig'))
for entry in manifest['images']:
    if not entry.get('download'):
        continue
    path = ROOT/'assets'/(entry['path']+'.png')
    if path.exists():
        continue
    path.parent.mkdir(parents=True, exist_ok=True)
    urllib.request.urlretrieve(entry['download'], path)
    print(path.relative_to(ROOT))
