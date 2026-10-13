#!/usr/bin/env python3
"""Check all diagnostic identities before requesting timing admission."""
import hashlib
import json
from pathlib import Path

for name, expected in json.loads((Path(__file__).parent / 'pins.json').read_text()).items():
    assert hashlib.sha256(Path(name).read_bytes()).hexdigest() == expected, name
print('All diagnostic pins match; no guest executed.')
