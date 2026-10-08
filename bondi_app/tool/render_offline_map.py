"""Build Subite's raster tiles from its OSM dataset. Requires Pillow.

No network requests. The PNG stream and JSON index form one versioned package.
"""
import gzip
import hashlib
import io
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/maps'
SIZE = 256
SCALE = 2
MAJOR = {'motorway', 'trunk', 'primary', 'secondary', 'tertiary',
         'motorway_link', 'trunk_link', 'primary_link', 'secondary_link'}


def project(lat, lon, zoom):
    n = 2 ** zoom
    return ((lon + 180) / 360 * n,
            (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n)


def main():
    data = json.loads(gzip.decompress((OUT / 'cordoba.json.gz').read_bytes()))
    south, west, north, east = data['bounds']
    # The same selected local font is used for every tile.
    font = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 20)
    index = {}
    with (OUT / 'cordoba.tiles').open('wb') as package:
        for zoom in range(10, 17):
            left, top = project(north, west, zoom)
            right, bottom = project(south, east, zoom)
            tiles = {}
            candidates = []
            for kind, name, coords in data['features']:
                if zoom < 13 and kind not in MAJOR | {'park', 'water'}:
                    continue
                points = [project(lat, lon, zoom) for lat, lon in coords]
                if name and zoom >= 14 and (kind in MAJOR or zoom >= 16):
                    candidates.append((kind, name, points))
                xs, ys = zip(*points)
                # Include a gutter so strokes and names join across tile edges.
                for x in range(max(math.floor(left), math.floor(min(xs) - .3)),
                               min(math.floor(right), math.floor(max(xs) + .3)) + 1):
                    for y in range(max(math.floor(top), math.floor(min(ys) - .3)),
                                   min(math.floor(bottom), math.floor(max(ys) + .3)) + 1):
                        tiles.setdefault((x, y), []).append((kind, name, points))
            # Choose labels once in world coordinates, then draw every fragment
            # on all intersecting tiles. Local collision tests cause clipped names.
            labels, occupied, names = {}, {}, set()
            for kind, name, points in sorted(candidates, key=lambda f: (f[0] not in MAJOR, -len(f[2]))):
                if name in names:
                    continue
                px, py = points[len(points) // 2]
                px, py = round(px * SIZE * SCALE), round(py * SIZE * SCALE)
                b = font.getbbox(name, anchor='mm', stroke_width=2)
                box = (px+b[0], py+b[1], px+b[2], py+b[3])
                cells = [(x, y) for x in range((box[0]-12)//128, (box[2]+12)//128+1)
                         for y in range((box[1]-12)//64, (box[3]+12)//64+1)]
                neighbors = [b for c in cells for b in occupied.get(c, [])]
                if any(box[0] < b[2]+12 and box[2] > b[0]-12 and
                       box[1] < b[3]+12 and box[3] > b[1]-12 for b in neighbors):
                    continue
                for c in cells:
                    occupied.setdefault(c, []).append(box)
                names.add(name)
                for x in range(box[0]//(SIZE*SCALE), box[2]//(SIZE*SCALE)+1):
                    for y in range(box[1]//(SIZE*SCALE), box[3]//(SIZE*SCALE)+1):
                        labels.setdefault((x,y), []).append((name,px,py))
            for x in range(math.floor(left), math.floor(right) + 1):
                for y in range(math.floor(top), math.floor(bottom) + 1):
                    image = Image.new('RGB', (SIZE * SCALE, SIZE * SCALE), '#edebe4')
                    draw = ImageDraw.Draw(image)
                    features = tiles.get((x, y), [])
                    def pixels(points):
                        return [((px - x) * SIZE * SCALE, (py - y) * SIZE * SCALE)
                                for px, py in points]
                    for kind, _, points in features:
                        if kind == 'park' and len(points) >= 3:
                            draw.polygon(pixels(points), fill='#d7e6cd')
                    for kind, _, points in sorted(features, key=lambda f: f[0] in MAJOR):
                        if kind == 'park':
                            continue
                        width = (3.5 if kind in MAJOR else 3 if kind == 'water' else 1.5) * SCALE
                        draw.line(pixels(points), fill=('#9acedb' if kind == 'water' else
                                  '#ffe4ad' if kind in MAJOR else 'white'),
                                  width=round(width), joint='curve')
                    for name, px, py in labels.get((x,y), []):
                        draw.text((px-x*SIZE*SCALE, py-y*SIZE*SCALE), name,
                                  font=font, anchor='mm', fill='#655f53',
                                  stroke_width=2, stroke_fill='white')
                    buffer = io.BytesIO()
                    image.save(buffer, format='PNG', optimize=True)
                    tile = buffer.getvalue()
                    index[f'{zoom}/{x}/{y}'] = [package.tell(), len(tile)]
                    package.write(tile)
            print(f'zoom {zoom}: {len(index)} total tiles', flush=True)
    manifest = {'version': 1, 'bounds': data['bounds'], 'minZoom': 10, 'maxZoom': 16,
                'tileSize': SIZE, 'dataDate': data['dataDate'],
                'attribution': data['attribution'], 'license': data['license'],
                'sha256': hashlib.sha256((OUT / 'cordoba.tiles').read_bytes()).hexdigest(),
                'tiles': index}
    (OUT / 'cordoba.tiles.json').write_text(json.dumps(manifest, separators=(',', ':')), encoding='utf8')
    print(f'package: {(OUT / "cordoba.tiles").stat().st_size} bytes', flush=True)


if __name__ == '__main__':
    main()
