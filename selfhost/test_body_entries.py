#!/usr/bin/env python3
"""Mandatory normal and release B7 source-generation qualification."""
import argparse
import json
from pathlib import Path
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent/'tests'))
import generate_body_entry_requests as G
import run_body_entry_qualification as E
import run_body_entry_hostile as H


def require_complete(report):
    E.require(report.get('complete') is True and report.get('selected_admission') == 'passed',
              'B7 source admission did not complete')
    E.require((report.get('operations'), report.get('expected_operations'), report.get('cases')) ==
              (357, 357, 24), 'incomplete B7 source-operation selection')
    E.require(len(report.get('generations', [])) == 2, 'missing second source generation')
    E.require_capture_inventory(report.get('captures', []))
    records = report.get('resource_forged', [])
    E.require([row['name'] for row in records] == list(H.NAMES), 'incomplete resource attack selection')
    for row in records:
        H.J.require_rejection((row['status'], bytes.fromhex(row['stdout_hex']), bytes.fromhex(row['stderr_hex'])))
    E.require(report.get('failed') == report.get('skipped') == 0, 'B7 failed/skipped source work')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('compiler', 'builder', 'component-dir', 'zig', 'source-root', 'report-dir'):
        parser.add_argument('--'+name, type=Path, required=True)
    args = parser.parse_args()
    for name in vars(args):
        setattr(args, name, getattr(args, name).resolve())
    args.report_dir.mkdir(parents=True, exist_ok=True)
    # Outputs belong to this invocation; reports retain all fresh request/reply paths.
    # Build's declared output directory remains available after the driver exits.
    invocation = Path(tempfile.mkdtemp(prefix='fresh-', dir=args.report_dir))
    args.output_dir = invocation/'runtime-requests'
    G.generate(args)
    args.requests_dir = args.output_dir
    for release in (False, True):
        label = 'release' if release else 'normal'
        args.release = release
        args.work_dir = invocation/(label+'-work')
        args.report = args.report_dir/(label+'.json')
        E.Qualification(args).run()
        require_complete(json.loads(args.report.read_text()))
    print('body entry gate: normal and release 357 operations/35 captures/15 resource attacks each; 0 failed, 0 skipped')


if __name__ == '__main__':
    main()
