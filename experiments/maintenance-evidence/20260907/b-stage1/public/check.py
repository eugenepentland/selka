"""Public deterministic application checks; no private grading inputs are included."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

STAGE = 1
EXTRA_ARGUMENT = False
FILES = ('ledger.my', 'model.my', 'report.my')


def observe(compiler, directory, extra_argument, case, field=None):
    values = ','.join(str(n) for n in case['input'])
    arguments = f"heap,new [4]i64[{values}],{case['floor']}"
    if field:
        fields = 'cast<i64>(reply.' + field + ')'
        body = ('match ledger::summarize(' + arguments + ') {' +
                'model::Answer.ok(reply)=>{return ' + fields + ';},' +
                'model::Answer.err(code)=>{return -9000000+code;}}')
    else:
        body = 'return report::score(' + arguments + ');'
    driver = ('module main;import report;import ledger;import model;' +
              'fn main(heap:allocator)->i64{' + body + '}')
    with tempfile.TemporaryDirectory(prefix='ledger-check-', dir=directory.parent) as temporary:
        root = Path(temporary)
        for name in FILES:
            source = directory / name
            if source.is_symlink() or not source.is_file() or source.stat().st_size > 65536:
                raise ValueError('expected bounded ordinary source file: ' + name)
            (root / name).write_bytes(source.read_bytes())
        (root / 'main.my').write_text(driver)
        command = [str(compiler), 'run-project', str(root / 'main.my'),
                   '--max-steps=100000', '--max-frames=64', '--diagnostics=json']
        result = subprocess.run(command, capture_output=True, timeout=10)
        return {'returncode': result.returncode, 'stdout': result.stdout.decode(errors='replace'),
                'stderr': result.stderr.decode(errors='replace')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--source', type=Path, default=Path(__file__).parent / 'work')
    parser.add_argument('--stage', type=int, default=STAGE)
    args = parser.parse_args()
    if args.stage != STAGE:
        parser.error('checker belongs to a different stage')
    cases = json.loads(Path(__file__).with_name('cases.json').read_text())
    results = []
    for index, case in enumerate(cases):
        for field, expected in case['expected'].items():
            actual = observe(args.compiler.resolve(), args.source.resolve(), EXTRA_ARGUMENT, case, None if field == 'report' else field)
            wanted = str(expected) + '\n'
            results.append({'case': index, 'field': field, 'expected': wanted,
                            'passed': actual['returncode'] == 0 and actual['stdout'] == wanted, **actual})
    print(json.dumps({'stage': args.stage, 'checks': results}))
    raise SystemExit(0 if all(item['passed'] for item in results) else 1)


if __name__ == '__main__':
    main()
