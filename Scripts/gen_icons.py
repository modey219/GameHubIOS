import struct, zlib, os, sys

def create_png(w, h, r, g, b):
    raw = b''
    for y in range(h):
        raw += b'\x00'
        for x in range(w):
            cr = max(0, min(255, r + (y * 80 // h)))
            cg = max(0, min(255, g - (y * 40 // h)))
            cb = max(0, min(255, b - (y * 60 // h)))
            raw += struct.pack('BBBB', cr, cg, cb, 255)

    def chunk(ctype, data):
        c = ctype + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)

    ihdr = struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')

def main():
    iconset = os.environ.get('ICONSET', 'GameHub/Resources/Assets.xcassets/AppIcon.appiconset')
    sizes = {
        'icon-20.png': 20, 'icon-20@2x.png': 40, 'icon-20@3x.png': 60,
        'icon-29.png': 29, 'icon-29@2x.png': 58, 'icon-29@3x.png': 87,
        'icon-40.png': 40, 'icon-40@2x.png': 80, 'icon-40@3x.png': 120,
        'icon-60.png': 60, 'icon-60@2x.png': 120, 'icon-60@3x.png': 180,
        'icon-76.png': 76, 'icon-76@2x.png': 152,
        'icon-83.5@2x.png': 167, 'icon-1024.png': 1024,
    }
    for name, size in sizes.items():
        with open(f'{iconset}/{name}', 'wb') as f:
            f.write(create_png(size, size, 58, 28, 113))
    print(f'Generated {len(sizes)} icons')

if __name__ == '__main__':
    main()
