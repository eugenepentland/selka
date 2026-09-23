#!/usr/bin/env python3
"""Copy the stock (base) adapter and add exactly the chosen frame-map features:
   fp      "frame-pointer"="non-leaf"
   tail    "disable-tail-calls"="true"
   nomerge every non-intrinsic call nomerge
usage: make_adapter_feat.py DEST feat[,feat...]"""
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = HERE / "adapter-a0"
DST = Path(sys.argv[1])
feats = set(f for f in sys.argv[2].split(",") if f)
DST.mkdir(parents=True, exist_ok=True)
for p in SRC.glob("*.py"):
    shutil.copy(p, DST / p.name)
emit = DST / "llvm_emit.py"
text = emit.read_text()
anchor = '        attributes = " #0" if self.attributes or not self.function.export else ""\n'
assert anchor in text
patch = f"        # frame-map experiment features: {sorted(feats)}\n"
if "fp" in feats:
    patch += '        self.attributes.add(\'"frame-pointer"="non-leaf"\')\n'
if "tail" in feats:
    patch += '        self.attributes.add(\'"disable-tail-calls"="true"\')\n'
text = text.replace(anchor, patch + anchor)
if "nomerge" in feats:
    old = '    def on_call(self, instruction):\n        """A call whose result is the instruction\'s destination."""\n        lines = []\n'
    assert old in text
    text = text.replace(old, old.replace('        lines = []\n', '        lines = _NomergeLines()\n'))
    helper = '''

class _NomergeLines(list):
    def append(self, line):
        if ("= call " in line or line.startswith("  call ")) and "@llvm." not in line and line.rstrip().endswith(")"):
            line = line + " nomerge"
        super().append(line)
'''
    text = text.replace("\ndef translate(unit, signatures=None):", helper + "\n\ndef translate(unit, signatures=None):")
emit.write_text(text)
print("made", DST, sorted(feats))
