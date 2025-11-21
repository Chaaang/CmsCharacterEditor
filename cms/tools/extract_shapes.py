import cv2
from pathlib import Path

CHARACTERS = {
    0: ('gingerbread', 'assets/gingerbreadman2.png'),
    1: ('nutcracker', 'assets/nutcracker2.png'),
    2: ('santa', 'assets/santa2.png'),
    3: ('elf', 'assets/elf2.png'),
}

def extract_polygons(image_path):
    img = cv2.imread(str(image_path), cv2.IMREAD_GRAYSCALE)
    if img is None:
        raise FileNotFoundError(image_path)
    h, w = img.shape
    _, thresh = cv2.threshold(img, 127, 255, cv2.THRESH_BINARY)
    contours, _ = cv2.findContours(thresh, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
    polygons = []
    for cnt in sorted(contours, key=cv2.contourArea, reverse=True):
        area = cv2.contourArea(cnt)
        if area < 50:
            continue
        epsilon = 0.8
        approx = cv2.approxPolyDP(cnt, epsilon, True)
        poly = [(float(pt[0][0]) / w, float(pt[0][1]) / h) for pt in approx]
        polygons.append(poly)
    return polygons

def format_polygons(name, polygons):
    lines = []
    const_name = f'_{name}Polygons'
    lines.append(f'const List<List<Offset>> {const_name} = [')
    for poly in polygons:
        lines.append('  [')
        for x, y in poly:
            lines.append(f'    Offset({x:.6f}, {y:.6f}),')
        lines.append('  ],')
    lines.append('];\n')
    return '\n'.join(lines)

def main():
    base = Path('.')
    const_sections = []
    mapping_lines = []
    for char_id, (name, rel) in CHARACTERS.items():
        polygons = extract_polygons(base / rel)
        const_sections.append(format_polygons(name, polygons))
        mapping_lines.append(f'    {char_id}: _{name}Polygons,')
    header = """// GENERATED CODE - DO NOT MODIFY BY HAND
// Generated via tools/extract_shapes.py from mask assets.

import 'dart:ui';

class CharacterShapeLibrary {
  static const Map<int, List<List<Offset>>> _data = {
"""
    footer = """  };

  static List<List<Offset>> polygonsFor(int characterId) {
    return _data[characterId] ?? _gingerbreadPolygons;
  }
}

"""
    content = header + '\n'.join(mapping_lines) + '\n' + footer + '\n'.join(const_sections)
    out_path = base / 'lib' / 'widgets' / 'character_shapes.dart'
    out_path.write_text(content)
    print(f'Wrote {out_path} with polygon data')

if __name__ == '__main__':
    main()
