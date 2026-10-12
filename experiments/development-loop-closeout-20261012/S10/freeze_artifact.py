#!/usr/bin/env python3
"""Hash and pin a compiler artifact without asserting cache or compiler validity."""
import hashlib
import json
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'scripts'))
from fuzz_campaign_store import Store
path = Path(sys.argv[1]).resolve()
mode = sys.argv[2]
data = path.read_bytes()
store = Store(ROOT / '.mylang-cache/s10-frozen-artifacts-v1')
pin = hashlib.sha256(('C0-frozen-' + mode).encode()).hexdigest()
with store.lease():
    digest = hashlib.sha256(data).hexdigest()
    chunks = [store.put_blob(data[index:index + 8*1024*1024]) for index in range(0, len(data), 8*1024*1024)]
    store.pin(pin, blobs=sorted(set(chunks)))
record = {'source': 'fbfcaa7a923186a8e773c3760f81c10aa345a432', 'mode': mode,
          'path': str(path), 'sha256': digest, 'bytes': len(data),
          'evidence_store': str(store.root), 'pin': pin, 'ordered_chunks': chunks,
          'prune_protection': str(ROOT / '.prune-keep'),
          'validity': 'artifact identity only; complete verification separately reported'}
out = Path(__file__).resolve().parent / 'raw' / ('C0-' + mode + '-artifact.json')
out.write_text(json.dumps(record, indent=2) + '\n')
print(json.dumps(record))
