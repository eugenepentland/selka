"""Reconstruct and authenticate one archived B7 protocol frame."""
import gzip
import hashlib
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parent
if len(sys.argv) != 3:
    raise SystemExit('usage: reconstruct_frame.py ORIGINAL_PATH OUTPUT_FILE')
record = json.loads((root/'retained-paths.json').read_text())[sys.argv[1]]
compressed = (root/record['archive']).read_bytes()
assert hashlib.sha256(compressed).hexdigest() == record['archive_sha256']
frame = bytes.fromhex(record['header_hex']) + gzip.decompress(compressed)
assert len(frame) == record['frame_bytes']
assert hashlib.sha256(frame).hexdigest() == record['frame_sha256']
with Path(sys.argv[2]).open('xb') as output:
    output.write(frame)
