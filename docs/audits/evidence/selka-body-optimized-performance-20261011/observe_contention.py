"""Read-only external CPU activity evidence; never changes another process."""
import datetime
import json
import os
from pathlib import Path
import time

root = 3737877
reserved = {2, 3, 10, 11}
os.sched_setaffinity(0, os.sched_getaffinity(0) - reserved)
hz = os.sysconf('SC_CLK_TCK')

def snapshot():
    rows = {}
    for directory in Path('/proc').iterdir():
        if not directory.name.isdigit():
            continue
        try:
            stat = (directory / 'stat').read_text()
            end = stat.rindex(')')
            fields = stat[end + 2:].split()
            pid = int(directory.name)
            rows[pid] = {'comm': stat[stat.index('(') + 1:end], 'parent': int(fields[1]),
                         'start': int(fields[19]), 'ticks': int(fields[11]) + int(fields[12]),
                         'affinity': sorted(os.sched_getaffinity(pid))}
        except (OSError, ValueError):
            continue
    return rows

def descendant(pid, rows):
    visited = set()
    while pid in rows and pid not in visited:
        if pid == root:
            return True
        visited.add(pid)
        pid = rows[pid]['parent']
    return False

path = Path(__file__).with_name('external-cpu-activity.jsonl')
previous = snapshot()
started = previous.get(root, {}).get('start')
with path.open('x') as out:
    out.write(json.dumps({'scope': 'sampled process CPU deltas, not proof of complete machine isolation', 'reservation_root': root, 'reserved_cpus': sorted(reserved), 'root_start': started}) + '\n')
    out.flush()
    last = time.monotonic()
    while True:
        time.sleep(5)
        current = snapshot()
        now = time.monotonic()
        activity = []
        for pid, row in current.items():
            old = previous.get(pid)
            if not old or old['start'] != row['start'] or descendant(pid, current):
                continue
            seconds = (row['ticks'] - old['ticks']) / hz
            if seconds >= 0.05:
                activity.append(dict(pid=pid, comm=row['comm'], cpu_seconds=seconds,
                                     affinity_overlap=sorted(reserved.intersection(row['affinity']))))
        out.write(json.dumps({'utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'interval_seconds': now-last, 'external_process_activity': activity}) + '\n')
        out.flush()
        if current.get(root, {}).get('start') != started:
            break
        previous, last = current, now
print('CPU activity evidence retained at', path)
