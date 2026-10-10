"""Validate shipped geometry, continuous bodies, UV paint, and packaged textures."""
from collections import Counter
from pathlib import Path
from math import isfinite
import json
import zipfile
from pxr import Usd, UsdGeom, UsdShade

root=Path(__file__).resolve().parents[1]
manifest=json.loads((root/'Art'/'Creatures'/'manifest.json').read_text())
for name in manifest:
    path=root/'PocketRealm'/'Resources'/'Creatures'/f'{name}.usdz'
    stage=Usd.Stage.Open(str(path))
    cache=UsdGeom.BBoxCache(0,[UsdGeom.Tokens.default_])
    bound=cache.ComputeWorldBound(stage.GetPseudoRoot()).ComputeAlignedRange()
    meshes=[p for p in stage.Traverse() if p.IsA(UsdGeom.Mesh)]
    size=bound.GetSize()
    assert len(meshes)==manifest[name]['meshes'], f'Missing meshes: {name}'
    assert UsdGeom.GetStageUpAxis(stage)=='Y'
    assert UsdGeom.GetStageMetersPerUnit(stage)==1
    assert all(isfinite(x) and .1<x<.8 for x in size)
    assert .3<size[1]<.6
    triangles=sum(sum(n-2 for n in UsdGeom.Mesh(p).GetFaceVertexCountsAttr().Get()) for p in meshes)
    assert triangles==manifest[name]['triangles'] and triangles<110_000
    bodies=[p for p in meshes if f'{name}_continuous_body' in str(p.GetPath())]
    assert len(bodies)==1, f'Missing continuous body: {name}'
    body=UsdGeom.Mesh(bodies[0])
    points=body.GetPointsAttr().Get()
    assert all(isfinite(c) for point in points for c in point)
    counts=body.GetFaceVertexCountsAttr().Get(); indices=body.GetFaceVertexIndicesAttr().Get()
    edges=Counter(); neighbors=[set() for _ in points]; offset=0
    for count in counts:
        polygon=list(indices[offset:offset+count]); offset+=count
        for a,b in zip(polygon,polygon[1:]+polygon[:1]):
            edges[tuple(sorted((a,b)))]+=1
            neighbors[a].add(b); neighbors[b].add(a)
    assert all(n==2 for n in edges.values()), f'Open/non-manifold body: {name}'
    reached={0}; pending=[0]
    while pending:
        for neighbor in neighbors[pending.pop()]-reached:
            reached.add(neighbor); pending.append(neighbor)
    assert len(reached)==len(points), f'Disconnected body volumes: {name}'
    uvs=UsdGeom.PrimvarsAPI(body).GetPrimvar('st')
    assert uvs and uvs.Get(), f'Missing painted UVs: {name}'
    material,_=UsdShade.MaterialBindingAPI(bodies[0]).ComputeBoundMaterial()
    assert material, f'Missing skin material: {name}'
    with zipfile.ZipFile(path) as package:
        textures=[p for p in stage.Traverse() if p.GetAttribute('inputs:file')]
        assert len(textures)==manifest[name]['textures']
        for shader in textures:
            asset=shader.GetAttribute('inputs:file').Get()
            texture=asset.path.removeprefix('./')
            assert texture in package.namelist(), f'External texture: {texture}'
            assert package.read(texture)[:8]==b'\x89PNG\r\n\x1a\n'
            assert asset.resolvedPath, f'Unresolved texture: {texture}'
    for control in manifest[name]['motionControls']:
        assert any(p.GetName()==control for p in stage.Traverse()), f'Missing motion control: {control}'
    print(f'{name}: {len(meshes)} meshes, {triangles} triangles, closed connected body, {len(textures)} embedded textures, Y-up, {size} meters')
print('ALL_USDZ_ASSETS_VALID')
