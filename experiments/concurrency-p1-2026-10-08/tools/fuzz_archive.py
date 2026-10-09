#!/usr/bin/env python3
"""Restore P1's losslessly transformed fuzz archive to its original files.

Usage: fuzz_archive.py ARCHIVE DESTINATION
Only commands.jsonl members ending in .decoded are transformed. In those
members stdout_b64/stderr_b64 hold byte strings represented with Latin-1;
elapsed_seconds holds base64 of its exact little-endian IEEE-754 double.
The original JSON spelling is restored with json.dumps defaults and a newline.
Packing verifies every original line survives this round trip exactly.
The external manifest records SHA-256 of the original, restored bytes.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import struct
import tarfile


def command_bytes(data, restore=False):
    result = []
    for line in data.splitlines(keepends=True):
        value = json.loads(line)
        for key in ('stdout_b64', 'stderr_b64'):
            if key not in value:
                continue
            value[key] = (base64.b64encode(value[key].encode('latin1')).decode()
                          if restore else base64.b64decode(value[key]).decode('latin1'))
        if 'elapsed_seconds' in value:
            value['elapsed_seconds'] = (struct.unpack('<d', base64.b64decode(value['elapsed_seconds']))[0]
                                        if restore else base64.b64encode(struct.pack('<d', value['elapsed_seconds'])).decode())
        result.append((json.dumps(value) + '\n').encode())
    return b''.join(result)


def restored(name, data):
    if name.endswith('/commands.jsonl.decoded'):
        return name.removesuffix('.decoded'), command_bytes(data, restore=True)
    return name, data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    destination = args.destination.resolve()
    manifest = {}
    with tarfile.open(args.archive) as archive:
        for member in archive:
            if not member.isfile():
                raise ValueError('only regular evidence files are accepted')
            name, data = restored(member.name, archive.extractfile(member).read())
            target = (destination / name).resolve()
            if not target.is_relative_to(destination):
                raise ValueError('archive member escapes destination')
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open('xb') as output:
                output.write(data)
            manifest[name] = hashlib.sha256(data).hexdigest()
    print(json.dumps(manifest, sort_keys=True, indent=2))


if __name__ == '__main__':
    main()
