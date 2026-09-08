"""Opt-in process timing; application output remains on stdout."""
import json
import runpy
import sys
import time

started = time.perf_counter_ns()
exit_code = 0
try:
    sys.path.insert(0, '/work')
    runpy.run_path('/work/main.py', run_name='__main__')
except SystemExit as error:
    exit_code = error.code if type(error.code) is int else int(error.code is not None)
    raise
except BaseException:
    exit_code = 1
    raise
finally:
    print(json.dumps({'version': 'phase-timings-v1', 'kind': 'timing', 'tool': 'python',
                      'name': 'application_inclusive', 'inclusive': True,
                      'duration_ns': time.perf_counter_ns() - started, 'exit_code': exit_code}), file=sys.stderr)
