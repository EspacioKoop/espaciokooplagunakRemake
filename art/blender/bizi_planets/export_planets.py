"""Export Bizi planet pairs from saved .blend sources, preserving manual edits. MIT."""
from __future__ import annotations
import argparse
import json
import math
import sys
from pathlib import Path
import bpy
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
sys.path.insert(0,str(HERE.parent/'itsasargi_pack'))
from export import export_model,render_exported,sha
sys.path.insert(0,str(HERE))
from generate import PLANETS


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--render',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:])
    entries=[];planets=[]
    for ident,title,radius,seed in PLANETS:
        source=HERE/(ident+'.blend');before=sha(source);planet=None
        for mode in ('orbit','surface'):
            target=ROOT/'game/assets/models/bizi_planets'/(ident+'_'+mode+'.glb')
            entry=export_model(source,ident+'_'+mode,target,'bizi/'+ident+'/'+mode)
            cat=json.loads(bpy.context.scene['planet_catalogue'])
            if cat['id']!=ident or cat['habitable'] is not True:raise ValueError('Wrong habitable planet source')
            # Read source-authored POI and arrival transforms, never regenerate their placement.
            if mode=='surface':
                sockets={s['name']:s for s in entry['sockets']}
                for poi in cat['pois']:
                    poi['position']=sockets[poi['entry_socket']]['position']
                    poi['links']=[cat['pois'][(cat['pois'].index(poi)+offset)%14]['id'] for offset in (-1,1)]
                cat['arrival_socket']='socket_landing';cat['return_socket']='socket_return'
                cat['arrival_position']=sockets['socket_landing']['position']
                cat['arrival_clearance_m']=1.85
                cat['resources']=[{'socket':s['name'],'position':s['position'],
                    'kind':'mineral' if s['name'].endswith('_0') else 'botanical'}
                    for s in entry['sockets'] if s['name'].startswith('socket_resource_')]
                cat['radius_m']=float(bpy.data.objects[ident+'_surface']['radius_m'])
                cat['sea_level_m']=float(bpy.data.objects[ident+'_surface']['sea_level_m'])
                cat['gravity']='radial planet-local';cat['surface_path']=str(target.relative_to(ROOT))
                cat['orbit_path']='game/assets/models/bizi_planets/'+ident+'_orbit.glb'
                cat['circumference_reference_m']=round(2*math.pi*cat['radius_m'],3)
                cat['habitable_definition']='Fictional breathable, temperate, vegetated world with settlements and water; not an astrophysical claim.'
                cat['status']='exported; see PR for real Godot validation'
                cat['future_consumers']=['campaign resources','missions','encounters','ship landing','host-authoritative persistence']
                planets.append(cat)
            entry.update(category='habitable_planets',title=title+' / '+mode,habitable=True,representation=mode,
                radius_m=cat['radius_m'],pivot='planet centre; same unscaled metres in both representations',
                preview='docs/images/bizi_planets/'+ident+'_'+mode+'.png')
            if args.render:render_exported(target,ident+'_'+mode,ROOT/entry['preview'],640)
            entries.append(entry)
            print('EXPORTED HABITABLE',entry['id'],entry['triangles'],flush=True)
        if before!=sha(source):raise AssertionError('Source changed during reexport')
    result={'schema':'espaciokoop-habitable-planets','schema_version':1,'pack':'bizi','version':1,
        'library_issue':52,'habitable':True,'units':'metres','axes':'+X right / +Y up / -Z forward',
        'coordinate_contract':'Both representations use the SAME planet-centred reference frame, metre scale and terrain field. No arbitrary surface scaling.',
        'assets':entries,'planets':planets,
        'limits':['No seamless ship flight implemented','No campaign missions, battles or inventory integration',
            'Water is visual; no swimming or survival simulation','Arrival positions are local to the planet',
            'Surface meshes are finite closed shells, not flat maps; props are separate','Orbital silhouette is approximate at lower detail']}
    path=ROOT/'game/assets/models/bizi_planets/manifest.json'
    path.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

if __name__=='__main__':main()
