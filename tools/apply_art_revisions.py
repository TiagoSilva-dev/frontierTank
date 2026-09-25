"""Apply completed PixelLab revisions, preserving original PNGs and provenance."""
import json, shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'assets/expansion'
manifest=json.loads((BASE/'generation_manifest.json').read_text(encoding='utf-8-sig'))
revisions=json.loads((BASE/'revision_jobs.json').read_text(encoding='utf-8-sig'))
for revision in revisions:
    if not revision.get('download'): continue
    current=next(j for j in manifest['jobs'] if j['path']==revision['path'])
    if current['job_id']==revision['job_id']: continue
    source=BASE/(current['path']+'.png')
    backup=BASE/'superseded'/(current['path']+'_'+current['job_id']+'.png')
    backup.parent.mkdir(parents=True,exist_ok=True)
    if source.exists(): shutil.move(str(source),str(backup))
    previous=dict(current)
    current.clear(); current.update(revision); current['supersedes']=previous
(BASE/'generation_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('Completed revisions applied to manifest; collector will download replacements.')
