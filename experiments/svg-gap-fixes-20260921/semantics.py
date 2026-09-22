#!/usr/bin/env python3
"""LLVM O3/LTO checks for aggregate reads and schematic output boundaries."""
import json
import subprocess

import run


def build(source, name, host=False):
    binary = run.WORK / name
    command = [str(run.COMPILER), 'build', str(source), '--backend', 'llvm',
               '--llvm-adapter', str(run.ROOT/'experiments/llvm-backend/qbe_llvm.py'),
               '--zig', '/home/epentland/.local/bin/zig', '--llvm-opt', '3', '--lto',
               '--cache-dir', str(run.WORK/'semantic-cache'), '-o', str(binary)]
    if host:
        command += ['--project','--provider',str(run.ROOT/'src/schematic/native_schematic.c')]
    result = subprocess.run(command, cwd=run.ROOT, env=run.environment(), capture_output=True, timeout=600)
    (run.OUT/f'{name}-build.log').write_bytes(result.stdout+result.stderr)
    assert result.returncode == 0, (name,result.stderr.decode())
    return binary


def main():
    qbe = (run.ROOT/'src/qbe_test.zig').read_text()
    part = qbe.split('const aggregate_projection_program =\n',1)[1].split('\n;',1)[0]
    source = '\n'.join(line.split('\\\\',1)[1] for line in part.splitlines())+'\n'
    path = run.WORK/'projection.my'; path.write_text(source)
    cases = {'projection': (path,b'42\n',None)}
    for index in (-2,1):
        name = f'projection-bounds-{index}'
        path = run.WORK/f'{name}.my'
        path.write_text(f'record Pair:\n    left: int\n    right: int\ndef read(items: list[Pair], index: int) -> int:\n    return items[index].left\ndef main() -> int:\n    return read([Pair(left=3, right=4)], {index})\n')
        cases[name] = (path,b'',b'R_LIST_BOUNDS')
    evidence = {}
    for name,(source,expected,trap) in cases.items():
        binary = build(source,name)
        observations = []
        for stress in (False,True):
            command = [str(binary),'--print-result']+(['--gc-stress'] if stress else [])
            result = subprocess.run(command,cwd=run.ROOT,env=run.environment(),capture_output=True,timeout=90)
            if trap:
                assert result.returncode != 0 and trap in result.stderr, (name,result)
                assert b':5:' in result.stderr, (name,result.stderr)
            else:
                assert result.returncode == int(expected) and result.stdout == expected and not result.stderr, (name,result)
            observations.append({'gc_stress':stress,'exit':result.returncode,'stdout':result.stdout.decode(),'stderr':result.stderr.decode()})
        evidence[name] = {'binary_sha256':run.sha(binary),'runs':observations}
    checks = ('test_minimum_integer_decimal','test_negative_decimal_width_boundaries',
              'test_output_limit_fails_without_oversized_buffer','test_decimal_uses_exact_remaining_capacity')
    source = run.WORK/'guest-gc/bulk_main.my'
    source.write_text('module bulk_main\nimport bulk_io_test as checks\ndef main() -> int:\n'+
                      ''.join(f'    assert checks.{name}()\n' for name in checks)+'    return 0\n')
    binary = build(source,'bulk-boundaries',host=True)
    # All declarations in this io module are the same ones frozen by the SVG build.
    (run.WORK/'bulk-boundaries.declared').write_text((run.WORK/'gc-lto.declared').read_text())
    for stress in (False,True):
        actual = run.invoke(binary,run.BASE/'projects/fixture',stress=stress)
        assert actual == (0,b'0\n',b'',b'',b''), actual[:3]
    evidence['bulk_boundaries'] = {'checks':checks,'normal_and_gc_stress':True,'binary_sha256':run.sha(binary)}
    # The provider must surface buffered write failures at write_block or finish.
    env = run.environment()
    env.update(MYLANG_SCHEMATIC_DECLARED=(run.WORK/'gc-lto.declared').read_text(),
               MYLANG_SCHEMATIC_OUTPUT='/dev/full',MYLANG_SCHEMATIC_ISSUE=str(run.WORK/'full.issue'))
    env.update({f'MYLANG_SCHEMATIC_INPUT_{i}':str(run.BASE/'projects/fixture'/p) for i,p in enumerate(run.DOCS)})
    result = subprocess.run([str(run.WORK/'gc-lto'),'--print-result'],cwd=run.ROOT,env=env,capture_output=True,timeout=90)
    assert result.returncode != 0 and b'R_HOST_FAILURE' in result.stderr, result
    evidence['write_failure'] = {'exit':result.returncode,'stderr':result.stderr.decode()}
    (run.OUT/'llvm-semantics.json').write_text(json.dumps(evidence,indent=2)+'\n')
    print('LLVM aggregate/GC/bounds checks and buffered write-failure check passed.',flush=True)


if __name__ == '__main__':
    main()
