#!/usr/bin/env python3
"""Aggregate ELF section sizes and relocation counts over objects or one executable.

usage: elfsizes.py FILE_OR_DIR [--by-kind]

For a directory, every `*.o` is read. Sections are grouped by name prefix
(`.text.<sym>` -> `.text.*`). `--by-kind` also splits objects into code batches
(objects with `.text.*` sections), metadata batches and the rest.
Output: a JSON document with bytes and relocation counts per section group.
"""
import json
import struct
import sys
from pathlib import Path


def sections(path):
    b = Path(path).read_bytes()
    if b[:4] != b"\x7fELF" or b[4] != 2:
        return []
    shoff, = struct.unpack_from("<Q", b, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", b, 0x3A)
    hdrs = []
    for i in range(shnum):
        o = shoff + i * shentsize
        name, typ, flags, addr, off, size, link, info, align, entsize = struct.unpack_from("<IIQQQQIIQQ", b, o)
        hdrs.append((name, typ, flags, off, size, info, entsize))
    stro = hdrs[shstrndx][3]

    def nm(n):
        e = b.index(b"\0", stro + n)
        return b[stro + n:e].decode()
    out = []
    for (name, typ, flags, off, size, info, entsize) in hdrs:
        out.append({"name": nm(name), "type": typ, "size": size if typ != 8 else size, "nobits": typ == 8,
                    "relocs": size // entsize if typ == 4 and entsize else 0, "info": info})
    return out


def group(name):
    for p in (".text.", ".rela.text.", ".data.rel.ro.", ".rela.data.rel.ro.", ".rodata.", ".data.", ".rela.data."):
        if name.startswith(p):
            return p + "*"
    return name


def main():
    target = Path(sys.argv[1])
    by_kind = "--by-kind" in sys.argv
    files = sorted(target.glob("*.o")) if target.is_dir() else [target]
    agg = {}
    kinds = {}
    for f in files:
        secs = sections(f)
        kind = "other"
        if any(s["name"].startswith(".text.") for s in secs):
            kind = "code"
        elif any("rel.ro" in s["name"] for s in secs) or any(s["name"] in (".data.rel.ro", ".rodata") for s in secs):
            kind = "meta"
        k = kinds.setdefault(kind, {"objects": 0, "file_bytes": 0, "sections": {}})
        k["objects"] += 1
        k["file_bytes"] += f.stat().st_size
        for s in secs:
            if not s["name"]:
                continue
            g = group(s["name"])
            for dst in (agg, k["sections"]):
                e = dst.setdefault(g, {"bytes": 0, "relocs": 0, "count": 0})
                e["bytes"] += s["size"]
                e["relocs"] += s["relocs"]
                e["count"] += 1
    res = {"files": len(files), "file_bytes": sum(f.stat().st_size for f in files),
           "sections": dict(sorted(agg.items(), key=lambda kv: -kv[1]["bytes"])[:25])}
    if by_kind:
        for k in kinds.values():
            k["sections"] = dict(sorted(k["sections"].items(), key=lambda kv: -kv[1]["bytes"])[:12])
        res["kinds"] = kinds
    print(json.dumps(res, indent=1))


if __name__ == "__main__":
    main()
