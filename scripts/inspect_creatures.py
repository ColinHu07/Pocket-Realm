from pathlib import Path
from pxr import Usd, UsdGeom
from math import isfinite
root=Path(__file__).resolve().parents[1]
for name in ('Mosskip','Glimlo','Pebblin'):
    stage=Usd.Stage.Open(str(root/'PocketRealm'/'Resources'/'Creatures'/f'{name}.usdz'))
    cache=UsdGeom.BBoxCache(0,[UsdGeom.Tokens.default_])
    bound=cache.ComputeWorldBound(stage.GetPseudoRoot()).ComputeAlignedRange()
    meshes=[p for p in stage.Traverse() if p.IsA(UsdGeom.Mesh)]
    print(name,'up',UsdGeom.GetStageUpAxis(stage),'units',UsdGeom.GetStageMetersPerUnit(stage),'bounds',bound,'meshes',len(meshes))
    print('mesh_names', [p.GetName() for p in meshes])
    size=bound.GetSize()
    assert len(meshes)>20, f'Missing meshes: {name}'
    assert UsdGeom.GetStageUpAxis(stage)=='Y'
    assert all(isfinite(x) and .1<x<.8 for x in size)
    assert .3<size[1]<.6
print('ALL_USDZ_ASSETS_VALID')
