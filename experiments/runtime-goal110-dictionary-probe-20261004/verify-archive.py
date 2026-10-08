"""Verify stored bytes and every decoded gzip/tar member without executing guests."""
from pathlib import Path
import gzip,hashlib,json,tarfile
root=Path(__file__).resolve().parent;index=json.loads((root/'index.json').read_text());h=lambda b:hashlib.sha256(b).hexdigest();count=0
for row in index['files']:
 raw=(root/row['path']).read_bytes();assert len(raw)==row['bytes'] and h(raw)==row['sha256'];decoded=gzip.decompress(raw) if row['encoding']=='gzip' else raw
 if 'source_sha256' in row:assert len(decoded)==row['source_bytes'] and h(decoded)==row['source_sha256']
 count+=1
for pack in index['packs']:
 p=root/pack['path'];raw=p.read_bytes();assert len(raw)==pack['bytes'] and h(raw)==pack['sha256']
 with tarfile.open(p,'r:gz') as tar:
  assert set(tar.getnames())=={r['path'] for r in pack['entries']}
  for row in pack['entries']:
   data=tar.extractfile(row['path']).read();assert len(data)==row['bytes'] and h(data)==row['sha256'];count+=1
print(f'PASS {count} exact archive bindings; no guests executed')
