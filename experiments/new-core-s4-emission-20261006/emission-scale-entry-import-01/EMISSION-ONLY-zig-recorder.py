#!/usr/bin/env python3
"""Explicit placeholder for emission inspection; creates no executable code."""
import json
import os
from pathlib import Path
import sys
with Path(os.environ["S4_EMIT_COMMANDS"]).open("a") as log:
    log.write(json.dumps(sys.argv) + "\n")
args = sys.argv[1:]
if "-o" not in args:
    raise SystemExit("emission recorder expected a -o path")
Path(args[args.index("-o") + 1]).write_bytes(b"S4 emission placeholder, not native code\n")
