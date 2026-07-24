import struct, zlib, os, sys

def create_png(w, h):
    raw = b''
    for y in range(h):
        raw += b'\x00'
        for x in range(w):
            t = y / max(h - 1, 1)
            r = int(30 + t * 60)
            g = int(10 + t * 20)
            b = int(140 - t * 40)
            a = 255
            raw += struct.pack('BBBB', r, g, b, a)

    def chunk(ctype, data):
        c = ctype + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)

    ihdr = struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    iconset = os.path.join(script_dir, '..', 'GameHub', 'Resources', 'Assets.xcassets', 'AppIcon.appiconset')
    if not os.path.isdir(iconset):
        iconset = os.environ.get('ICONSET', '')
    if not iconset or not os.path.isdir(iconset):
        alt = os.path.join(script_dir, '..', '..', 'GameHub', 'Resources', 'Assets.xcassets', 'AppIcon.appiconset')
        if os.path.isdir(alt):
            iconset = alt
    if not os.path.isdir(iconset):
        print(f'ERROR: Iconset not found at {iconset}')
        sys.exit(1)

    os.makedirs(iconset, exist_ok=True)

    sizes = {
        'icon-20.png': 20, 'icon-20@2x.png': 40, 'icon-20@3x.png': 60,
        'icon-29.png': 29, 'icon-29@2x.png': 58, 'icon-29@3x.png': 87,
        'icon-40.png': 40, 'icon-40@2x.png': 80, 'icon-40@3x.png': 120,
        'icon-60.png': 60, 'icon-60@2x.png': 120, 'icon-60@3x.png': 180,
        'icon-76.png': 76, 'icon-76@2x.png': 152,
        'icon-83.5@2x.png': 167, 'icon-1024.png': 1024,
    }
    for name, size in sizes.items():
        path = os.path.join(iconset, name)
        with open(path, 'wb') as f:
            f.write(create_png(size, size))
        print(f'  {name} ({size}x{size}) -> {os.path.getsize(path)} bytes')

    print(f'Generated {len(sizes)} icons in {iconset}')

if __name__ == '__main__':
    main()
