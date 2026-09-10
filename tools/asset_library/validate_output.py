"""Validate generated human and machine views; never silently accept missing photos. MIT."""
from __future__ import annotations
import copy
import json
import re
from pathlib import Path
from jsonschema import Draft202012Validator
from catalogue import ROOT, REPO, need, png_info, digest, blob


def main():
    data=json.loads((ROOT/'docs/asset_library.json').read_text())
    schema=json.loads((ROOT/'docs/asset_library/schema.json').read_text())
    Draft202012Validator.check_schema(schema)
    validator=Draft202012Validator(schema)
    validator.validate(data)
    assets=data['assets'];ids={a['id'] for a in assets}
    need(len(ids)==len(assets),'Duplicate asset IDs')
    listed=[ident for pack in data['packs'] for ident in pack['asset_ids']]
    need(len(listed)==len(set(listed)) and set(listed)==ids,'Pack index mismatch')
    photos=set();links_checked=0
    for a in assets:
        preview=a['preview']
        identity=(preview['revision'],preview['path'])
        need(identity not in photos,'One photo reused for different model cards')
        photos.add(identity)
        raw=blob(preview['revision'],preview['path']) if preview['revision'] else (ROOT/preview['path']).read_bytes()
        need(digest(raw)==preview['sha256'] and png_info(raw)==preview['size_px'],'Photo proof mismatch')
        card=(ROOT/a['card']).read_text()
        need('<img ' in card and a['id'] in card,'Card missing model image or ID')
        if a['habitable']:need('HABITABLE' in card and a['representation'] in card,'Planet contract missing')
    # Check only our generated documents, not historical or unrelated repository docs.
    documents=[ROOT/'docs/ASSET_LIBRARY.md',* (ROOT/'docs/asset_library').glob('*.md'),* (ROOT/'docs/asset_library/models').glob('*.md'),* (ROOT/'docs/asset_library/categories').glob('*.md')]
    for file in documents:
        if file.name=='LEGACY_INDEX.md':continue
        text=file.read_text()
        targets=re.findall(r'\]\(([^)]+)\)',text)+re.findall(r'(?:src|href)="([^"]+)"',text)
        for target in targets:
            if target.startswith(('https://','http://','#','mailto:')):continue
            relative=target.split('#',1)[0]
            if not relative:continue
            resolved=(file.parent/relative).resolve()
            need(resolved.is_relative_to(ROOT) and resolved.is_file(),'Broken local link '+str(file.relative_to(ROOT))+': '+target)
            links_checked+=1
    negatives=0
    for modify in (
        lambda d:d['assets'][0].pop('preview'),
        lambda d:d['assets'][0].update(source='missing.blend'),
        lambda d:d['assets'][0]['availability'].update(gameplay_integration='complete'),
        lambda d:d['assets'][0]['preview'].update(size_px=[0,640]),
        lambda d:d['assets'][0].update(revision='main'),
        lambda d:d['assets'][0].update(runtime_sha256='wrong'),
        lambda d:d.update(version=1),
    ):
        broken=copy.deepcopy(data);modify(broken)
        need(not validator.is_valid(broken),'Schema accepted a corrupt catalogue')
        negatives+=1
    report={'assets':len(assets),'packs':len(data['packs']),'unique_photos':len(photos),'local_links':links_checked,'schema_negative_cases':negatives}
    output=ROOT/'build/asset_library';output.mkdir(parents=True,exist_ok=True)
    (output/'output-validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print('ASSET_LIBRARY_OUTPUT_PASS',json.dumps(report))

if __name__=='__main__':main()
