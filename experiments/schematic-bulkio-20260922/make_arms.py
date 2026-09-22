#!/usr/bin/env python3
"""Write the bench_svg.py arms file for this lane's before/after comparison.

usage: make_arms.py <lane-worktree> <out.json>

The `after` arm is the lane's freshly built `gc-lto`; its `.declared` list is
read from the file `build_arms.py` wrote beside the binary, so a new host
declaration reaches the provider registration without being retyped here.
"""
import json
import sys
from pathlib import Path

BEFORE = Path('/home/epentland/ai/canopy/mylang/.tmp/perf-audit-20260922/arms')
PORTS = Path('/home/epentland/ai/canopy/mylang/.tmp/full-svg-benchmark-20260921')


def main() -> None:
    tree, out = Path(sys.argv[1]).resolve(), Path(sys.argv[2])
    after = tree / '.tmp/audit/arms/gc-lto'
    arms = {
        'zig-o3': {'binary': str(PORTS / 'zig-o3'), 'kind': 'native'},
        'rust-o3': {'binary': str(PORTS / 'rust-o3'), 'kind': 'native'},
        'before-gc-lto': {'binary': str(BEFORE / 'gc-lto'), 'kind': 'mylang', 'bounded': False,
                          'declared': (BEFORE / 'gc-lto.declared').read_text().strip()},
        'after-gc-lto': {'binary': str(after), 'kind': 'mylang', 'bounded': False,
                         'declared': after.with_suffix('.declared').read_text().strip()},
    }
    out.write_text(json.dumps(arms, indent=1) + '\n')
    print(json.dumps(arms, indent=1))


if __name__ == '__main__':
    main()
