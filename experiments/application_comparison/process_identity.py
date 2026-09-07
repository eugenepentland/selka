"""Read-only Linux process observations; never signals a PID or authorizes retry."""
import os
from pathlib import Path
import re


def stat_fields(data, pid):
    # comm may contain spaces and parentheses; fields after its final ')' start at 3.
    prefix, separator, tail = data.rpartition(')')
    fields = tail.split()
    if not separator or not prefix.startswith(str(pid) + ' (') or len(fields) < 20:
        raise ValueError('invalid process stat record')
    if not fields[19].isdigit() or len(fields[0]) != 1:
        raise ValueError('invalid process start time or state')
    return int(fields[19]), fields[0]


def capture(pid):
    if type(pid) is not int or pid <= 0:
        raise ValueError('positive process ID required')
    ticks, state = stat_fields(Path(f'/proc/{pid}/stat').read_text(), pid)
    boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    namespace = os.readlink('/proc/self/ns/pid')
    return {'version': 'linux-process-identity-v1', 'pid': pid, 'boot_id': boot,
            'pid_namespace': namespace, 'start_ticks': ticks}, state


def observe(identity):
    required = {'version', 'pid', 'boot_id', 'pid_namespace', 'start_ticks'}
    if (not isinstance(identity, dict) or set(identity) != required or
            identity['version'] != 'linux-process-identity-v1' or
            type(identity['pid']) is not int or identity['pid'] <= 0 or
            type(identity['start_ticks']) is not int or identity['start_ticks'] < 0 or
            not isinstance(identity['boot_id'], str) or
            re.fullmatch(r'[0-9a-f-]{36}', identity['boot_id']) is None or
            not isinstance(identity['pid_namespace'], str)):
        return {'status': 'unknown', 'reason': 'missing-or-invalid-process-identity'}
    try:
        boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
        namespace = os.readlink('/proc/self/ns/pid')
        if (boot, namespace) != (identity['boot_id'], identity['pid_namespace']):
            return {'status': 'unknown', 'reason': 'different-boot-or-pid-namespace'}
    except OSError:
        return {'status': 'unknown', 'reason': 'process-context-unavailable'}
    try:
        current, state = capture(identity['pid'])
    except FileNotFoundError:
        if Path(f'/proc/{identity["pid"]}').exists():
            return {'status': 'unknown', 'reason': 'process-observation-unavailable'}
        return {'status': 'not-running', 'reason': 'process-no-longer-present'}
    except (OSError, ValueError):
        return {'status': 'unknown', 'reason': 'process-observation-unavailable'}
    if current != identity:
        return {'status': 'different-process', 'reason': 'process-identity-mismatch'}
    if state in ('Z', 'X', 'x'):
        return {'status': 'not-running', 'reason': 'terminal-process-state', 'state': state}
    return {'status': 'live', 'state': state}


def main():
    import argparse
    import json
    from .storage import read_json
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--record', type=Path, required=True)
    args = parser.parse_args()
    result = observe(read_json(args.record).get('identity'))
    print(json.dumps(result))
    return 2 if result['status'] == 'unknown' else 0


if __name__ == '__main__':
    raise SystemExit(main())
