#!/usr/bin/env python3
"""Continue A02 policy timings with longer, explicit workloads and frozen binaries."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--harness', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--case', required=True)
    parser.add_argument('--repetitions', type=int, required=True)
    parser.add_argument('--cpu', type=int, default=10)
    args = parser.parse_args()
    if os.environ.get('MYLANG_ADMISSION_KIND') != 'timing':
        parser.error('requires one enclosing timing admission')
    if args.repetitions <= 0:
        parser.error('repetitions must be positive')
    for key in ('MYLANG_COUNTERS', 'MYLANG_OPTIONS', 'MYLANG_CORE_SANITIZE', 'MYL_CORE_LEAKCHECK'):
        os.environ.pop(key, None)
    args.output = args.output.resolve()
    path = args.output / ('timing-' + args.case + '.json')
    if path.exists():
        parser.error('refusing to overwrite completed timing evidence')
    artifacts = json.loads((args.output / 'artifacts.json').read_text())
    args.cases, args.policies = [args.case], ['baseline', 'start_one']
    for policy in args.policies:
        binary = args.output / policy / 'plain/program'
        assert digest(binary) == artifacts['policies'][policy]['plain']['binary_sha256']
    spec = importlib.util.spec_from_file_location('capacity_policy', args.harness)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.CASES[args.case] = args.repetitions
    module.timing(args)
    result = json.loads(path.read_text())
    result['continuation_wrapper_sha256'] = digest(__file__)
    result['continuation_note'] = 'A09 explicit repetitions lengthen A02 native policy workloads; same frozen binaries. No final compiler or guest-program claim.'
    for policy in args.policies:
        binary = args.output / policy / 'plain/program'
        assert digest(binary) == artifacts['policies'][policy]['plain']['binary_sha256']
    path.write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
