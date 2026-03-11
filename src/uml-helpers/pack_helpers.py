#!/usr/bin/env python3
"""
pack_helpers.py — Create .uml_helpers binary bundle for embedding in kernel ELF.

Usage:
    python3 pack_helpers.py -o helpers.bin port-helper uml_switch

Bundle format:
    magic[4]  = "UMLH"
    count[4]  = number of entries (little-endian u32)
    entries[]:
        name (NUL-terminated string)
        size[4] = compressed data size (little-endian u32)
        data    = gzip-compressed binary
"""

import sys
import os
import gzip
import struct
import argparse


def pack(output, helpers):
    entries = []
    for path in helpers:
        name = os.path.basename(path)
        with open(path, "rb") as f:
            raw = f.read()
        compressed = gzip.compress(raw, compresslevel=9)
        entries.append((name, compressed))
        print(f"  {name}: {len(raw):,} → {len(compressed):,} bytes "
              f"({100*len(compressed)//len(raw)}%)")

    with open(output, "wb") as f:
        f.write(b"UMLH")
        f.write(struct.pack("<I", len(entries)))
        for name, data in entries:
            f.write(name.encode() + b"\x00")
            f.write(struct.pack("<I", len(data)))
            f.write(data)

    total = os.path.getsize(output)
    print(f"Bundle: {output} ({total:,} bytes, {len(entries)} helpers)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("-o", required=True, metavar="OUTPUT")
    parser.add_argument("helpers", nargs="+")
    args = parser.parse_args()
    pack(args.o, args.helpers)
