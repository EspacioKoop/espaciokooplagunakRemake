"""Verify actual delivered terrain topology, not just a spherical bounding box. MIT."""
import collections
import importlib.util
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('asset_validation',ROOT/'tests/itsasargi_pack/validate.py')
v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)


def geometry(path,prefix):
    doc,binary=v.unpack(path.read_bytes());faces=[];points=set()
    for mesh in doc['meshes']:
        if not mesh.get('name','').startswith(prefix):continue
        for primitive in mesh['primitives']:
            positions=v.accessor(doc,binary,primitive['attributes']['POSITION'])
            indices=[x[0] for x in v.accessor(doc,binary,primitive['indices'])]
            for i in range(0,len(indices),3):
                face=tuple(tuple(round(c,4) for c in positions[indices[i+j]]) for j in range(3))
                faces.append(face);points.update(face)
    v.require(faces,'missing terrain mesh '+prefix)
    return faces,points


def main():
    report=[]
    for ident in ('ametz','uharte'):
        directory=ROOT/'game/assets/models/bizi_planets'
        faces,vertices=geometry(directory/(ident+'_surface.glb'),'terrain_chunk')
        edges=collections.Counter()
        adjacency=collections.defaultdict(set)
        for face in faces:
            v.require(len(set(face))==3,'degenerate terrain face')
            for i in range(3):
                a,b=face[i],face[(i+1)%3]
                edges[tuple(sorted((a,b)))]+=1
                adjacency[a].add(b);adjacency[b].add(a)
        v.require(all(n==2 for n in edges.values()),'terrain has boundary/crack or non-manifold edge')
        v.require(len(vertices)-len(edges)+len(faces)==2,'terrain is not genus-zero closed sphere')
        remaining=set(vertices);todo=[remaining.pop()]
        while todo:
            for neighbor in adjacency[todo.pop()]:
                if neighbor in remaining:remaining.remove(neighbor);todo.append(neighbor)
        v.require(not remaining,'disconnected terrain shells')
        _,orbital=geometry(directory/(ident+'_orbit.glb'),'orbit_terrain')
        # Coarse vertices are inherited by the finer icosphere and share terrain sampling.
        coarse_key={tuple(round(x,2) for x in p) for p in vertices}
        shared=sum(tuple(round(x,2) for x in p) in coarse_key for p in orbital)
        v.require(shared>=len(orbital)*.98,'orbit and ground diverge in planet-local frame')
        report.append({'planet':ident,'closed_sphere':True,'vertices':len(vertices),'edges':len(edges),'terrain_triangles':len(faces),'euler':2,'orbital_vertices_shared':shared,'orbital_vertices':len(orbital)})
    output=ROOT/'build/itsasargi/spheres.json';output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(report,indent=2)+'\n')
    print('BIZI_SPHERES_PASS',json.dumps(report))

if __name__=='__main__':main()
