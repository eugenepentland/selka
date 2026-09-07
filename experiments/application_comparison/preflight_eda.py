"""Run the valid high-output EDA fixture before choosing common adapter budgets.

This is baseline feasibility, never a timed participant trial. Uses an independent
oracle and isolated CLI execution; source, input and adapter identities are retained.
"""
import argparse
import json
import shutil
from pathlib import Path
import tempfile
from .eda_oracle import board_result
from .execution import correct, evaluate, freeze_adapter
from .isolation import Limits
from .storage import canonical, snapshot


def fixture():
    components = [dict(id='c' + str(i).zfill(31), x=0, y=0, width=1, height=1, pins=[])
                  for i in range(128)]
    board = dict(version=1, unit='um', width=10, height=10, clearance=0,
                 components=components, nets=[])
    result = board_result(board)
    return {'cases': [board] * 64}, {'results': [result] * 64}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--language', choices=('python', 'zig', 'my'), default='python')
    language = parser.parse_args().language
    repository = Path(__file__).resolve().parents[2]
    baseline = Path(__file__).parent / 'baselines/eda' / language
    request, expected = fixture()
    tools, commands = {}, [{'phase': 'run', 'argv': ['/usr/bin/python3', '-S', '-B', 'inspector.py']}]
    if language == 'my':
        tools = {'byte_io': repository / 'zig-out/bin/mylang-io'}
        commands = [{'phase': 'run', 'argv': ['/tools/byte_io', '--project', '/work']}]
    elif language == 'zig':
        tools = {'zig': Path(shutil.which('zig')).resolve().parent}
        commands = [{'phase': 'build', 'argv': ['/tools/zig/zig', 'build-exe', 'main.zig',
                                               '-OReleaseSafe', '-femit-bin=/cache/app']},
                    {'phase': 'run', 'argv': ['/cache/app']}]
    adapter = freeze_adapter(language, tools, commands,
        limits=Limits(wall_seconds=180, cpu_seconds=180, output_bytes=128 * 1024 * 1024,
                      memory_bytes=4 * 1024**3))
    with tempfile.TemporaryDirectory(prefix='eda-feasibility-') as temporary:
        root = Path(temporary)
        receipt = snapshot(baseline, root / 'source')
        record = evaluate(root / 'source', receipt, adapter, request, root / 'execution')
        passed = correct(record['outcome'], expected)
        report = {'version': 'eda-output-feasibility-v1', 'record_kind': 'fixture',
                  'comparative_claim': False, 'language': language, 'passed': passed,
                  'input_bytes': len(canonical(request)), 'expected_output_bytes': len(canonical(expected)),
                  'source_sha256': receipt['sha256'], 'adapter_sha256': adapter['sha256'],
                  'request_sha256': record['request_sha256'], 'limits': adapter['limits'],
                  'steps': record['steps'], 'failure': None if passed else record['outcome']['phase'],
                  'diagnostics': [{"phase": step['phase'], "stderr_tail":
                      (root / 'execution' / f'{index:02}.stderr').read_bytes()[-8192:].decode('utf-8', errors='replace')}
                      for index, step in enumerate(record['steps'])]}
    print(json.dumps(report, indent=2))
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
