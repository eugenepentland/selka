#!/usr/bin/env python3
"""Bounded CPU sampling of the pinned baseline; diagnostic, not a timing cell."""
import hashlib
import json
import pathlib
import os
import signal
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent

if len(sys.argv) > 1:
    command = json.loads(pathlib.Path(sys.argv[1]).read_text())
    for _ in range(12):
        subprocess.run(command['argv'], cwd=command['cwd'], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                       timeout=3)
else:
    availability_path = HERE / 'profile-availability.json'
    availability = json.loads(availability_path.read_text())
    availability['admitted_cpu_affinity'] = sorted(os.sched_getaffinity(0))
    availability['driver_sha256'] = hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest()
    availability_path.write_text(json.dumps(availability, indent=2) + '\n')
    results = []
    for cell in ('rds3+flat', 'cyclops-digital-pcb'):
        command_file = HERE / f'profile-{cell}-command.json'
        command = json.loads(command_file.read_text())
        binary = pathlib.Path(command['argv'][0])
        argv = ['perf', 'record', '-q', '-e', 'cycles:u', '-F', '499',
                '--call-graph', 'dwarf,8192', '-o', str(HERE / f'{cell}.perf.data'),
                '--', sys.executable, str(__file__), str(command_file)]
        with (HERE / f'{cell}.perf.log').open('w') as output:
            process = subprocess.Popen(argv, stdout=output, stderr=subprocess.STDOUT,
                                       start_new_session=True)
            try:
                status = process.wait(timeout=23)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                status = 124
        results.append({'cell': cell, 'argv': argv, 'returncode': status,
                        'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
                        'command_sha256': hashlib.sha256(command_file.read_bytes()).hexdigest()})
        if status == 0:
            with (HERE / f'{cell}.perf-report.txt').open('w') as output:
                subprocess.run(['perf', 'report', '--stdio', '--no-children',
                                '--comms', binary.name, '--sort', 'symbol',
                                '-i', str(HERE / f'{cell}.perf.data')],
                               stdout=output, stderr=subprocess.STDOUT,
                               check=True, timeout=5)
    (HERE / 'profile-receipt.json').write_text(json.dumps(results, indent=2) + '\n')
