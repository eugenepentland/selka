#!/usr/bin/env python3
"""Diagnostic only: expose oversized frame storage to LLVM as stack allocations.

This is NOT a production fix: existing native stack admission accounts for the
old ABI frame, not these enlarged frames. It prices scalarization/liveness work.
Zero initialization, value snapshots, roots and ordinary language checks remain.
"""
import json
import os
from pathlib import Path
import re
import subprocess

from audit import ROOT, OUT, WORK, sha, invoke

def main():
    folder = WORK / 'frames'
    folder.mkdir(exist_ok=True)
    compiler = WORK / 'mylang-audit-compiler'
    entry = ROOT / '.tmp/svg-arenas-20260921/guest-gc/main.my'
    records = {}
    for mode in ('none', 'both'):
        source = WORK / f'codegen/emitted-{mode}.json'
        manifest = json.loads(source.read_text())
        changes = []
        for function in manifest['functions']:
            il = function['il']
            match = re.search(r' %frame_memory =l call \$myl_qbe_frame_allocate\(l %ctx, l (\d+)\)', il)
            if not match:
                continue
            size = int(match.group(1))
            # Fixed stack storage starts at entry so LLVM can reason about it;
            # initialization stays at the original allocation point.
            assert il.count('@entry\n') == 1
            il = il.replace('@entry\n', f'@entry\n %frame_memory =l alloc16 {size}\n')
            il = il.replace(match.group(0), f' call $memset(l %frame_memory, w 0, l {size})')
            releases = il.count(' call $myl_qbe_frame_release(l %ctx, l %frame_memory)\n')
            assert releases > 0
            il = il.replace(' call $myl_qbe_frame_release(l %ctx, l %frame_memory)\n', '')
            function['il'] = il
            changes.append({'function': function['name'], 'bytes': size, 'removed_release_sites': releases})
        target = folder / f'{mode}.json'
        target.write_text(json.dumps(manifest, separators=(',', ':')))
        binary = folder / f'gc-lto-{mode}-stack-ceiling'
        command = [str(compiler), 'build', str(entry), '--project', '--provider', 'src/schematic/native_schematic.c',
                   '--backend', 'llvm', '--llvm-adapter', str(ROOT / 'experiments/llvm-backend/qbe_llvm.py'),
                   '--llvm-opt', '3', '--lto', '--keep-symbols', f'--manifest-file={target}',
                   '--cache-dir', str(folder / f'cache-{mode}'), '--report', '-o', str(binary)]
        env = dict(os.environ)
        for key in list(env):
            if key.startswith('MYLANG_QBE_LLVM_') or key == 'LD_PRELOAD':
                del env[key]
        env['MYLANG_MEMORY_LIMIT'] = '268435456'
        env['MYLANG_HOST_COMPILER'] = str(compiler)
        result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, timeout=1200)
        (folder / f'{mode}-build.stdout').write_bytes(result.stdout)
        (folder / f'{mode}-build.stderr').write_bytes(result.stderr)
        assert result.returncode == 0, result.stderr.decode()
        qualification = {}
        for case in ('fixture', 'changed-net', 'changed-value'):
            normal = invoke(binary, case, bounded=mode == 'both')[2]
            stress = invoke(binary, case, bounded=mode == 'both', extra=('--gc-stress',))[2]
            assert normal == stress
            qualification[case] = {'svg_sha256': normal, 'gc_stress': True}
        records[mode] = {'command': command, 'source_manifest_sha256': sha(source), 'manifest_sha256': sha(target),
                         'binary': str(binary.relative_to(ROOT)), 'binary_sha256': sha(binary),
                         'functions': changes, 'qualification': qualification}
    (OUT / 'frame-ceiling-builds.json').write_text(json.dumps({
        'contract': __doc__, 'compiler_sha256': sha(compiler), 'builds': records}, indent=2) + '\n')


if __name__ == '__main__':
    main()
