import json, urllib.request, gzip
from pathlib import Path
query = '''[out:json][timeout:90][maxsize:134217728];(
way["highway"]["highway"!~"^(construction|proposed|steps)$"](-31.55,-64.35,-31.25,-64.05);
way["waterway"~"^(river|stream|canal)$"](-31.55,-64.35,-31.25,-64.05);
way["leisure"~"^(park|garden)$"](-31.55,-64.35,-31.25,-64.05);
);out tags geom;'''
request = urllib.request.Request('https://overpass-api.de/api/interpreter', data=query.encode(), headers={'User-Agent':'Subite-map-build/1.0 (+https://github.com/nicolaschiabrandozanotti/Subite)', 'Content-Type':'text/plain'})
with urllib.request.urlopen(request, timeout=120) as response:
    raw = response.read(32 * 1024 * 1024 + 1)
if len(raw) > 32 * 1024 * 1024:
    raise ValueError('Map response exceeds 32 MiB')
data = json.loads(raw)
if data.get('remark'):
    raise ValueError(data['remark'])
features = []
for item in data['elements']:
    points = [[round(p['lat'], 5), round(p['lon'], 5)] for p in item.get('geometry', [])]
    if len(points) < 2:
        continue
    tags = item.get('tags', {})
    kind = tags.get('highway') or ('water' if 'waterway' in tags else 'park')
    features.append([kind, tags.get('name', ''), points])
assert len(features) > 1000, 'Unexpectedly incomplete Cordoba map'
result = {'version':1, 'source':'OpenStreetMap', 'license':'ODbL-1.0', 'attribution':'© OpenStreetMap contributors', 'dataDate':data['osm3s']['timestamp_osm_base'], 'bounds':[-31.55,-64.35,-31.25,-64.05], 'features':features}
output = Path(__file__).resolve().parents[1] / 'assets/maps/cordoba.json.gz'
output.parent.mkdir(parents=True, exist_ok=True)
output.write_bytes(gzip.compress(json.dumps(result, ensure_ascii=False, separators=(',', ':')).encode(), mtime=0))
print(json.dumps({'features':len(features), 'bytes':output.stat().st_size, 'date':result['dataDate']}))
