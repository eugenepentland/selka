"""Reject altered private copies of an actually qualified seed without touching it."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('builder', 'root', 'zig', 'receipt', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    receipt_bytes = args.receipt.read_bytes()
    qualification = json.loads(receipt_bytes)
    key = args.receipt.parent.name
    results = []
    expected = {'corrupt-binary': 'qualified seed digest mismatch',
                'missing-binary': 'qualified seed digest mismatch',
                'malformed-receipt': 'malformed or unreadable receipt',
                'changed-recipe': 'qualified seed digest mismatch',
                'wrong-archive': 'seed archive digest differs'}
    for case, reason in expected.items():
        with tempfile.TemporaryDirectory(prefix='s09-seed-rejection-') as temporary:
            work = Path(temporary)
            cache = work / 'cache'
            selected = cache / 'seeds' / key
            if case != 'wrong-archive':
                selected.mkdir(parents=True)
                metadata = receipt_bytes
                if case == 'malformed-receipt':
                    metadata = b'{'
                elif case == 'changed-recipe':
                    changed = json.loads(receipt_bytes)
                    changed['recipe']['target'] = 'unqualified-target'
                    metadata = json.dumps(changed).encode()
                (selected / 'receipt.json').write_bytes(metadata)
                if case != 'missing-binary':
                    executable = selected / 'source/zig-out/focus/mylang'
                    executable.parent.mkdir(parents=True)
                    executable.write_bytes(b'corrupted qualified binary')
            command = [str(args.builder), '--root', str(args.root), '--zig', str(args.zig),
                       '--cache-dir', str(cache), '--seed-only']
            if case == 'wrong-archive':
                wrong = work / 'wrong.tar'
                wrong.write_bytes(b'wrong immutable source archive')
                command.extend(['--seed-source', str(wrong)])
            result = subprocess.run(command, capture_output=True, text=True, timeout=120)
            passed = result.returncode != 0 and reason in result.stderr and not result.stdout.strip()
            results.append({'case': case, 'command': command, 'status': result.returncode,
                            'stdout': result.stdout, 'stderr': result.stderr, 'rejected': passed})
    args.output.write_text(json.dumps({'scope': 'private negative copies; genuine qualified source/seed untouched',
                                      'genuine_seed_sha256': qualification['sha256'], 'results': results,
                                      'passed': all(row['rejected'] for row in results)}, indent=2) + '\n')
    if not all(row['rejected'] for row in results):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
