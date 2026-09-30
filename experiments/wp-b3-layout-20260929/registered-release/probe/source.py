#!/usr/bin/env python3
"""Prove exact walker extraction and the single canonical collection call."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[4]
control = subprocess.check_output(['git', '-C', str(root), 'show',
    '5535e5a3f0b67e23d0fc9f92f594d7b3feb12a3f:src/native_rc_walk.c'], text=True)
start = control.index('void myl_rc_edges_release(')
stop = control.index('void myl_rc_flat_edges_release(', start)
expected = control[start:stop].replace(
    'void myl_rc_edges_release(myl_native_heap *heap, const myl_rc_shape *source,',
    'void myl_rc_registered_edges_release(myl_native_heap *heap, const myl_rc_shape *shape,').replace(
    '    const myl_rc_shape *shape = myl_rc_shape_find(heap, source);\n', '')
candidate = (root / 'src/native_rc_walk.c').read_text()
start = candidate.index('void myl_rc_registered_edges_release(')
stop = candidate.index('void myl_rc_flat_edges_release(', start)
assert candidate[start:stop] == expected
control = subprocess.check_output(['git', '-C', str(root), 'show',
    '5535e5a3f0b67e23d0fc9f92f594d7b3feb12a3f:src/native_collections.c'], text=True)
assert control.replace('else myl_rc_edges_release(heap,binding->descriptor.shape,storage,length);',
    'else myl_rc_registered_edges_release(heap,binding->descriptor.shape,storage,length);') == (
    root / 'src/native_collections.c').read_text()
print('PASS: exact old walker minus shape lookup; one trusted collection caller')
