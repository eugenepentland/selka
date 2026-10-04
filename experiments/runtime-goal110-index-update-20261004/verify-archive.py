"""Verify copied bytes and every deterministic pack member, without execution."""
from pathlib import Path
import gzip, hashlib, json, tarfile
root=Path(__file__).resolve().parent
h=lambda data:hashlib.sha256(data).hexdigest()
j=json.loads((root/'index.json').read_text());count=0
for row in j['files']:
 data=(root/row['path']).read_bytes();assert h(data)==row['sha256'];assert len(data)==row['bytes']
 raw=gzip.decompress(data) if row['encoding']=='gzip' else data
 if 'source_sha256' in row:assert h(raw)==row['source_sha256'];assert len(raw)==row['source_bytes']
 count+=1
for pack in j['packs']:
 path=root/pack['path'];assert h(path.read_bytes())==pack['sha256'];assert path.stat().st_size==pack['bytes']
 with tarfile.open(path,'r:gz') as tar:
  assert tar.getnames()==[row['path'] for row in pack['entries']]
  for row in pack['entries']:
   raw=tar.extractfile(row['path']).read();assert h(raw)==row['sha256'];assert len(raw)==row['bytes'];count+=1
print(json.dumps({'schema':'mylang-index-update-archive-verification-v1','status':'pass','index_sha256':h((root/'index.json').read_bytes()),'verified_file_or_member_bindings':count,'timing':False}))
