#!/usr/bin/env python3
"""Copy the LLVM adapter and patch it for the frame-map experiment arm A1:
guest functions keep a frame pointer (non-leaf), never tail call, are not
inlined unless the unit makes no call at all, and every call is `nomerge`."""
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "experiments/llvm-backend"
DST = Path(sys.argv[1])
DST.mkdir(parents=True, exist_ok=True)
for p in SRC.glob("*.py"):
    shutil.copy(p, DST / p.name)
emit = DST / "llvm_emit.py"
text = emit.read_text()
anchor = '        attributes = " #0" if self.attributes or not self.function.export else ""\n'
assert anchor in text
patch = (
    '        if os.environ.get("MYL_FM_EXP", "1") == "1":\n'
    '            has_calls = any(i.opcode == "call" for b in self.function.blocks for i in b.instructions)\n'
    '            self.attributes.add(\'"frame-pointer"="non-leaf"\')\n'
    '            self.attributes.add(\'"disable-tail-calls"="true"\')\n'
    '            if has_calls and os.environ.get("MYL_FM_NOINLINE", "1") == "1":\n'
    '                self.attributes.add("noinline")\n'
)
text = text.replace(anchor, patch + anchor)
old_on_call = '    def on_call(self, instruction):\n        """A call whose result is the instruction\'s destination."""\n        lines = []\n'
assert old_on_call in text
text = text.replace(old_on_call, old_on_call.replace('        lines = []\n', '        lines = _NomergeLines()\n'))
helper = '''

class _NomergeLines(list):
    """Collects an instruction's lines, marking every non-intrinsic call nomerge."""
    def append(self, line):
        if (os.environ.get("MYL_FM_EXP", "1") == "1" and ("= call " in line or line.startswith("  call "))
                and "@llvm." not in line and line.rstrip().endswith(")")):
            line = line + " nomerge"
        super().append(line)
'''
text = text.replace("\ndef translate(unit, signatures=None):", helper + "\n\ndef translate(unit, signatures=None):")
emit.write_text(text)
print("patched", emit)
