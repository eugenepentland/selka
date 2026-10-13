#!/usr/bin/env python3
"""Bounded CPU sampling of the pinned baseline; diagnostic, not a timing cell."""
import hashlib
import json
import pathlib
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
    results = []
    for cell in ('rds3+flat', 'cyclops-digital-pcb'):
        command_file = HERE / f'profile-{cell}-command.json'
        command = json.loads(command_file.read_text())
        binary = pathlib.Path(command['argv'][0])
        argv = ['perf', 'record', '-q', '-e', 'cycles:u', '-F', '499',
                '--call-graph', 'dwarf,8192', '-o', str(HERE / f'{cell}.perf.data'),
                '--', sys.executable, str(__file__), str(command_file)]
        with (HERE / f'{cell}.perf.log').open('w') as output:
            result = subprocess.run(argv, stdout=output, stderr=subprocess.STDOUT,
                                    timeout=23)
        results.append({'cell': cell, 'argv': argv, 'returncode': result.returncode,
                        'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
                        'command_sha256': hashlib.sha256(command_file.read_bytes()).hexdigest()})
        if result.returncode == 0:
            with (HERE / f'{cell}.perf-report.txt').open('w') as output:
                subprocess.run(['perf', 'report', '--stdio', '--no-children',
                                '--sort', 'symbol', '-i', str(HERE / f'{cell}.perf.data')],
                               stdout=output, stderr=subprocess.STDOUT,
                               check=True, timeout=5)
    (HERE / 'profile-receipt.json').write_text(json.dumps(results, indent=2) + '\n')
