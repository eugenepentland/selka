#!/usr/bin/env python3
"""Preserve a superseded trial losslessly; move originals to owned scratch."""
import argparse
import hashlib
import json
from pathlib import Path
import tarfile

p=argparse.ArgumentParser()
p.add_argument("--area",type=Path,required=True)
p.add_argument("--destination",type=Path,required=True)
p.add_argument("--output",type=Path,required=True)
a=p.parse_args()
area=a.area.resolve();destination=a.destination.resolve();output=a.output.resolve()
assert area.is_dir() and not destination.exists()
files=sorted(p for p in area.rglob("*") if p.is_file())
manifest={"source_area":str(area),"originals_retained":str(destination),"members":{str(p.relative_to(area)):{"sha256":hashlib.sha256(p.read_bytes()).hexdigest(),"bytes":p.stat().st_size} for p in files}}
archive=output.with_suffix(".tar.gz")
assert not archive.exists()
with tarfile.open(archive,"w:gz",compresslevel=6) as tar:
 for file in files:tar.add(file,arcname=str(file.relative_to(area)))
with tarfile.open(archive,"r:gz") as tar:
 assert set(tar.getnames())==set(manifest["members"])
 for member in tar.getmembers():
  data=tar.extractfile(member).read();expected=manifest["members"][member.name]
  assert len(data)==expected["bytes"] and hashlib.sha256(data).hexdigest()==expected["sha256"]
manifest.update(archive_sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),verified_lossless=True)
output.with_suffix(".manifest.json").write_text(json.dumps(manifest,indent=2,sort_keys=True)+"\n")
destination.parent.mkdir(parents=True,exist_ok=True)
area.rename(destination)
print(json.dumps({"archive":str(archive),"members":len(files),"archive_bytes":archive.stat().st_size,"verified_lossless":True}))
