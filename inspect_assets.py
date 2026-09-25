"""Record dimensions, transparency and SHA-256 for the delivered PNG files."""
import hashlib
import json
from pathlib import Path
from PIL import Image

root = Path(__file__).parent / 'assets'
records = []
for path in sorted(root.rglob('*.png')):
    if path.name == 'preview.png':
        continue
    with Image.open(path) as image:
        image.load()
        rgba = image.convert('RGBA')
        records.append({
            'file': path.relative_to(root).as_posix(),
            'width': image.width,
            'height': image.height,
            'alpha_range': rgba.getchannel('A').getextrema(),
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
        })
(root / 'file_inventory.json').write_text(json.dumps(records, indent=2), encoding='utf-8')
print(f'Validated {len(records)} readable PNG files')
