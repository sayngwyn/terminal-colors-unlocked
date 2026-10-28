"""Write an empty AS3 SWF whose document class is `Tint`.

FFDec can only edit an existing SWF, so the build starts from this skeleton
(no third-party content) and imports Tint.as into it.
Usage: python make_swf_skeleton.py <out.swf> [ClassName]
"""
import struct
import sys


def tag(code, body):
    if len(body) < 0x3F:
        return struct.pack('<H', (code << 6) | len(body)) + body
    return struct.pack('<HI', (code << 6) | 0x3F, len(body)) + body


def u30(n):
    out = b''
    while True:
        byte = n & 0x7F
        n >>= 7
        if n:
            out += bytes([byte | 0x80])
        else:
            return out + bytes([byte])


def string(s):
    data = s.encode()
    return u30(len(data)) + data


def body(method, max_stack, code):
    # method, max_stack, locals 1, scope depth 0..1, code, no exceptions/traits
    return (u30(method) + u30(max_stack) + u30(1) + u30(0) + u30(1)
            + u30(len(code)) + code + u30(0) + u30(0))


def stub_abc(class_name):
    # An empty `class <name> extends flash.display.MovieClip`, just enough
    # for FFDec to find the class and replace it with the real source.
    pool = (u30(0) + u30(0) + u30(0)                           # int, uint, double
            + u30(4) + string(class_name) + string('flash.display') + string('MovieClip')
            + u30(3) + b'\x16' + u30(0) + b'\x16' + u30(2)       # ns: package "", flash.display
            + u30(0)                                             # ns sets
            + u30(3) + b'\x07' + u30(1) + u30(1)                 # mn1 <name>
            + b'\x07' + u30(2) + u30(3))                         # mn2 flash.display::MovieClip
    methods = u30(3) + (u30(0) + u30(0) + u30(0) + b'\x00') * 3
    instance = u30(1) + u30(2) + b'\x01' + u30(0) + u30(0) + u30(0)
    klass = u30(1) + u30(0)
    script = u30(1) + u30(2) + u30(1) + u30(1) + b'\x04' + u30(1) + u30(0)
    bodies = (u30(3)
              + body(0, 1, b'\xd0\x30\xd0\x49\x00\x47')            # iinit: super()
              + body(1, 1, b'\xd0\x30\x47')                        # cinit
              + body(2, 2, b'\xd0\x30\x65\x00\x60\x02\x58\x00\x68\x01\x47'))  # script init
    return (struct.pack('<HH', 16, 46) + pool + methods + u30(0)
            + u30(1) + instance + klass + script + bodies)


def skeleton(class_name):
    tags = b''.join([
        tag(69, struct.pack('<I', 0x08)),                      # FileAttributes: AS3
        tag(82, struct.pack('<I', 1) + b'\0' + stub_abc(class_name)),  # DoABC2, lazy
        tag(76, struct.pack('<HH', 1, 0) + class_name.encode() + b'\0'),  # SymbolClass
        tag(1, b''),                                           # ShowFrame
        tag(0, b''),                                           # End
    ])
    rect = b'\x00'                                             # 0-bit RECT
    header_rest = rect + struct.pack('<HH', 30 << 8, 1)        # 30 fps, 1 frame
    body = header_rest + tags
    return b'FWS' + bytes([15]) + struct.pack('<I', 8 + len(body)) + body


if __name__ == '__main__':
    name = sys.argv[2] if len(sys.argv) > 2 else 'Tint'
    with open(sys.argv[1], 'wb') as f:
        f.write(skeleton(name))
