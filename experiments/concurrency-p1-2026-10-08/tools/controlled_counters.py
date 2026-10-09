#!/usr/bin/env python3
"""Run two existing counted/plain builds through identical executable/output paths.

Both source tags must already have ce.py build all binaries. Use fresh namespace
and snapshot tags; raw streams and summaries are moved to the snapshots after
each arm. This records work counts only, never a runtime-overhead ratio.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

import ce


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', required=True)
    parser.add_argument('--package', required=True)
    parser.add_argument('--namespace', required=True)
    parser.add_argument('--base-snapshot', required=True)
    parser.add_argument('--package-snapshot', required=True)
    args = parser.parse_args()
    target = ce.CACHE / 'bin' / args.namespace
    target.mkdir(exist_ok=False)
    report = {'common_binary_and_output_namespace': args.namespace, 'comparisons': [], 'complete': False}
    metadata = ce.AREA / 'r3/results' / (args.namespace + '-counter-runs.json')
    for original, snapshot in [(args.base, args.base_snapshot), (args.package, args.package_snapshot)]:
        source = ce.CACHE / 'bin' / original
        files = list(source.glob('*'))
        assert len(files) == 104 and all(p.is_file() for p in files)
        assert not (ce.CACHE / 'bin' / snapshot).exists()
        for directory in ['raw', 'results']:
            assert not (ce.AREA / directory / snapshot).exists()
        for path in files:
            shutil.copy2(path, target / path.name)
        command = ['python3', str(Path(ce.__file__)), '--tag', args.namespace, 'run', 'all']
        log = ce.AREA / 'r3/logs' / (snapshot + '-count-run.log')
        with log.open('w') as output:
            output.write(json.dumps(command) + '\n')
            output.flush()
            status = subprocess.run(command, cwd=ce.ROOT, env=ce.env(), stdout=output, stderr=subprocess.STDOUT).returncode
        report['comparisons'].append({'binary_source_tag': original, 'snapshot_tag': snapshot,
                                      'status': status, 'log': str(log.relative_to(ce.AREA))})
        metadata.write_text(json.dumps(report, indent=2) + '\n')
        assert status == 0
        for directory in ['raw', 'results']:
            shutil.move(ce.AREA / directory / args.namespace, ce.AREA / directory / snapshot)
        (ce.CACHE / 'bin' / snapshot).symlink_to(source, target_is_directory=True)
    report['complete'] = True
    metadata.write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
