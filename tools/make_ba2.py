"""Pack loose files into an uncompressed Fallout 4 general (GNRL) BA2.

The game loads "<plugin> - Main.ba2" on its own, and files in an archive
load without the loose-file ini settings, so the mod works in any setup.
Layout and hashes match vanilla archives (version 1, which both 1.10.163
and 1.11.240 read). Usage: python make_ba2.py <out.ba2> <root> <relpath>...
"""
import os
import struct
import sys


def bethesda_crc(text):
    # CRC32 (reflected 0xEDB88320) started from 0 and without the final xor.
    crc = 0
    for byte in text.lower().encode('latin1'):
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ (0xEDB88320 if crc & 1 else 0)
    return crc


def pack(out, root, paths):
    entries = []
    for rel in paths:
        rel = rel.replace('/', '\\')
        with open(os.path.join(root, rel), 'rb') as f:
            entries.append((rel, f.read()))
    data_start = 24 + 36 * len(entries)
    records, blobs, offset = [], [], data_start
    for rel, data in entries:
        folder, name = rel.rsplit('\\', 1)
        stem, ext = name.rsplit('.', 1)
        records.append(struct.pack('<I4sIIQIII', bethesda_crc(stem), ext.lower().encode().ljust(4, b'\0'),
                                   bethesda_crc(folder), 0x00100100, offset, 0, len(data), 0xBAADF00D))
        blobs.append(data)
        offset += len(data)
    names = b''.join(struct.pack('<H', len(rel)) + rel.encode('latin1') for rel, _ in entries)
    header = b'BTDX' + struct.pack('<I', 1) + b'GNRL' + struct.pack('<IQ', len(entries), offset)
    with open(out, 'wb') as f:
        f.write(header + b''.join(records) + b''.join(blobs) + names)


if __name__ == '__main__':
    pack(sys.argv[1], sys.argv[2], sys.argv[3:])
