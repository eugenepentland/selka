#!/usr/bin/env python3
"""Prepare, but never apply, the coordinated C3 counter-source patch."""
import difflib
import hashlib
import json
from pathlib import Path
import subprocess

BASE = 'bed11cf3bf3102ffec44487e431a1573fdf02ad5'
ROOT = Path(__file__).resolve().parents[5]
HERE = Path(__file__).resolve().parent
SCRATCH = ROOT / '.tmp/memory-closeout/A09/c3-counter-runtime'
FILES = ['src/core/emit_count.zig', 'src/core/count_runtime.zig',
         'src/core/runtime/core_count.h', 'src/core/runtime/core_count.c']


def once(text, old, new):
    if text.count(old) != 1:
        raise ValueError('nonunique draft anchor: ' + old[:80])
    return text.replace(old, new)


def transform(name, text):
    if name.endswith('emit_count.zig'):
        text = once(text, '//! uniqueness tests, copies and element traffic its emitted code executes, each at',
                    '//! direct destruction, copies and element traffic its emitted code executes, each at')
        text = once(text, '//! emitter adds to a unit so the program records, at run time, the count updates,',
                    '//! emitter adds to a unit so the program records allocations, checks,')
        text = once(text, '    /// An inline count increment of one block (`c0` executions).',
                    '    /// Historical v1 slot: no producer after RC retirement; always zero.')
        text = once(text, '    /// An inline count decrement of one block (`c0` executions).',
                    '    /// Historical v1 slot: no producer after RC retirement; always zero.')
        text = once(text, '    /// The release of a block ownership proved unique: a free with no count test.',
                    '    /// Direct destruction of an owned block; this remains an active counter.')
        text = once(text, '    /// An `is_unique` test: `c0` tests, `c2` of them found the block unique.',
                    '    /// Historical v1 slot: no producer after RC retirement; always zero.')
        text = once(text, '    /// A `str_from_view` (a text copy-on-write copy or a view materialized): `c0`, `c1` bytes.',
                    '    /// Text materialized from a view: `c0` copies, `c1` bytes.')
        for line in [r'    \\@myl_core_free_lists = external thread_local(localexec) global [33 x ptr]',
                     r'    \\declare preserve_mostcc void @myl_core_retain_slow(ptr) nounwind cold',
                     r'    \\declare preserve_mostcc void @myl_core_release_slow(ptr) nounwind cold',
                     r'    \\declare void @myl_core_free_block(ptr) nounwind cold']:
            text = once(text, line + '\n', '')
        text = once(text, '\n'.join([r'    \\define internal void @myl_core_free(ptr %block) alwaysinline nounwind {',
                    r'    \\entry:', r'    \\  call void @myl_core_free_block(ptr %block)',
                    r'    \\  ret void', r'    \\}', '']), '')
    elif name.endswith('count_runtime.zig'):
        start = text.index('    .{\n        .anchor = "static void count_retain(')
        end = text.index('    .{ .anchor = "    memcpy(other->hashes', start)
        removed = text[start:end]
        if removed.count('.anchor =') != 5:
            raise ValueError('expected exactly five obsolete RC hooks')
        text = text[:start] + text[end:]
    elif name.endswith('core_count.h'):
        lines = text.splitlines(keepends=True)
        old = ['MYL_COUNT_RUNTIME_RETAINS', 'MYL_COUNT_RUNTIME_RELEASES',
               'MYL_COUNT_SHARED_RETAINS', 'MYL_COUNT_SHARED_RELEASES', 'MYL_COUNT_SHARE_MARKS']
        if sum(any(word in line for word in old) for line in lines) != 5:
            raise ValueError('expected five retired slot constants')
        text = ''.join(line for line in lines if not any(word in line for word in old))
        text = once(text, '    MYL_COUNT_DICT_GROWS = 24,',
                    '    /* Slots 20..23 are reserved zero-valued v1 RC telemetry. */\n    MYL_COUNT_DICT_GROWS = 24,')
        text = once(text, '    MYL_COUNT_SLOTS = 42',
                    '    /* Slots 36..41 are reserved zero-valued v1 sharing telemetry. */\n    MYL_COUNT_SLOTS = 42')
    else:
        text = once(text, ' * Nothing is printed on the program\'s own streams unless the file cannot be',
                    ' * RC event fields remain explicit zero-valued historical v1 telemetry.\n * Their hooks are retired; they are not observations of count operations.\n * release_unique still records direct destruction. Slot/kind ordinals remain\n * stable, and consumers must require every field rather than default omissions.\n * Nothing is printed on the program\'s own streams unless the file cannot be')
        text = once(text, '/* Site kinds, in `emit_count.Kind` order. */',
                    '/* Site kinds, in `emit_count.Kind` order. Indices 0, 1 and 3 are\n   reserved historical zero fields; index 2 is active direct destruction. */')
        text = once(text, '/* Function slot names (core_count.h), one per used slot; null marks an unused one. */',
                    '/* Function slot names (core_count.h), including historical zero fields\n   at slots 20/22/36/38/40/41. No active hook writes those slots.\n   A null name marks a slot omitted from the v1 JSON schema. */')
    return text


def main():
    patch, records = [], {}
    for name in FILES:
        before = subprocess.check_output(['git', 'show', f'{BASE}:{name}'], cwd=ROOT).decode()
        after = transform(name, before)
        for label, data in [('before', before), ('prepared', after)]:
            path = SCRATCH / label / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(data)
        patch.extend(difflib.unified_diff(before.splitlines(keepends=True), after.splitlines(keepends=True),
                                        fromfile='a/' + name, tofile='b/' + name))
        records[name] = {label + '_sha256': hashlib.sha256(data.encode()).hexdigest()
                         for label, data in [('before', before), ('prepared', after)]}
    output = HERE / 'counters.patch'
    output.write_text(''.join(patch))
    (HERE / 'manifest.json').write_text(json.dumps({'base': BASE, 'status': 'unapplied C3 patch request',
        'files': records, 'patch_sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
        'counter_schema': 'mylang-counters-v1 unchanged; required historical RC fields explicitly zero',
        'shared_contract': 'Apply with A02 runtime RC removal and A07 direct owned LLVM templates; preserve allocation/copy/live/task synchronization.'}, indent=2) + '\n')


if __name__ == '__main__':
    main()
