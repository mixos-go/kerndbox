#!/usr/bin/env python3
"""
pack_helpers.py — Bundle multiple binaries into a single .uml_helpers file.

Format: simple concatenation with a header table:
  magic[8]    = "UMLHlp\0\0"
  count[4]    = number of entries
  entries[]:
    name[64]  = binary name (null-padded)
    offset[8] = byte offset in file
    size[8]   = byte size
  data[]:     = raw binary data

Usage:
  pack_helpers.py -o output.bin binary1 binary2 ...
"""
import struct, sys, os, argparse

MAGIC = b"UMLHlp\x00\x00"
HEADER_ENTRY = struct.Struct("<64sQQ")  # name(64), offset(8), size(8)

def pack(output, binaries):
    entries = []
    for b in binaries:
        name = os.path.basename(b).encode()[:63]
        size = os.path.getsize(b)
        entries.append((name, size, b))

    # Calculate offsets
    header_size = 8 + 4 + len(entries) * HEADER_ENTRY.size
    offset = header_size
    for i, (name, size, path) in enumerate(entries):
        entries[i] = (name, offset, size, path)
        offset += size

    with open(output, 'wb') as f:
        f.write(MAGIC)
        f.write(struct.pack("<I", len(entries)))
        for name, off, size, path in entries:
            f.write(HEADER_ENTRY.pack(name.ljust(64, b'\x00')[:64], off, size))
        for name, off, size, path in entries:
            with open(path, 'rb') as src:
                f.write(src.read())

    total = sum(e[2] for e in entries)
    print(f"Packed {len(entries)} helpers → {output} ({total} bytes)")

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("-o", required=True, help="output file")
    p.add_argument("binaries", nargs="+")
    a = p.parse_args()
    pack(a.o, a.binaries)
