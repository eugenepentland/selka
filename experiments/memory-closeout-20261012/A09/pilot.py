#!/usr/bin/env python3
"""One invocation per artifact to select workload sizes; no speedup conclusions."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import measure


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--builds', type=Path, nargs='+', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if os.environ.get('MYLANG_ADMISSION_KIND') != 'timing':
        parser.error('requires one enclosing timing admission')
    if args.output.exists():
        parser.error('refusing to overwrite pilot evidence')
    result = {'scope': __doc__, 'started_utc': datetime.now(timezone.utc).isoformat(),
              'host': measure.host(), 'cases': []}
    for path in args.builds:
        builds = json.loads(path.read_text())
        assert measure.digest(builds['compiler']) == builds['compiler_sha256']
        for case in builds['cases']:
            assert measure.digest(case['binary']) == case['binary_sha256']
            cpus = case.get('cpus', [10])
            if len(cpus) == 1:
                cpus = [10]
            row = measure.run_once([case['binary'], *case.get('args', [])], str(measure.ROOT),
                                   measure.clean_env(case.get('env')), cpus, case['expected'], 120)
            result['cases'].append({'id': case['id'], 'builds_path': str(path), 'cpus': cpus,
                                    'binary_sha256': case['binary_sha256'],
                                    'compiler_sha256': builds['compiler_sha256'],
                                    'args': case.get('args', []), **row})
            measure.save(args.output, result)
            print(case['id'], row['wall_ns'] / 1e6, 'ms', flush=True)
    result['finished_utc'] = datetime.now(timezone.utc).isoformat()
    measure.save(args.output, result)


if __name__ == '__main__':
    main()
