#!/usr/bin/env python3
"""Read-only host snapshot inside the lease, before the unchanged measurement."""
import datetime
import json
import os
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent


def snapshot(cpu):
    base = Path('/sys/devices/system/cpu') / f'cpu{cpu}'
    names = ('topology/thread_siblings_list', 'topology/core_id', 'topology/physical_package_id',
             'cpufreq/scaling_governor', 'cpufreq/scaling_cur_freq', 'cpufreq/scaling_min_freq',
             'cpufreq/scaling_max_freq', 'cpufreq/cpuinfo_max_freq')
    values = {}
    for name in names:
        try:
            values[name] = (base / name).read_text().strip()
        except OSError as error:
            values[name] = {'unavailable': type(error).__name__}
    try:
        process_names = '\n'.join(subprocess.check_output(
            ['ps', '-eo', 'pid,ppid,psr,pcpu,comm', '--sort=-pcpu'], text=True, timeout=5).splitlines()[:25])
    except (OSError, subprocess.SubprocessError) as error:
        process_names = {'unavailable': type(error).__name__}
    return dict(schema='text-gap-host-before-v1', utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                cpu=cpu, allowed_cpus=sorted(os.sched_getaffinity(0)), loadavg=list(os.getloadavg()),
                topology_frequency=values, process_names_cpu=process_names,
                limitation='Single read-only snapshot before cell calibration/warmup. ps CPU is a process-lifetime average. No arguments inspected, no processes/affinity/governor altered. Observation does not prove causal interference during samples.')


def main():
    # Preserve the existing measure.py argument contract.
    spec_path, output = map(Path, sys.argv[1:3])
    cpu = int(sys.argv[sys.argv.index('--cpu') + 1]) if '--cpu' in sys.argv else 8
    spec = json.loads(spec_path.read_text())
    before = output.with_suffix('.host-before.json').resolve()
    assert str(before) in spec['files'], 'snapshot must be pinned in the frozen spec'
    assert not output.exists(), 'never overwrite measured evidence'
    with before.open('x') as stream:
        json.dump(snapshot(cpu), stream, indent=2)
        stream.write('\n')
    subprocess.run([sys.executable, '-B', str(HERE / 'measure.py'), *sys.argv[1:]], check=True)


if __name__ == '__main__':
    main()
