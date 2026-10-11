"""Private FIFO reservation runner. Invoke through scripts/build-slot.sh gate."""
import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile
import time

root = Path('/home/epentland/.codex/worktrees/selka-selfhost-pilots/mylang')
if '/gate' not in os.readlink('/proc/self/fd/9'):
    raise RuntimeError('outer FIFO gate reservation required')
os.dup2(9, 30, inheritable=True)
gate_fd = 30
# FD30+ survives nested wrappers that reuse 7/8/9; the launcher retains both.
os.set_inheritable(gate_fd, True)
children, streams = [], []
try:
    for index in range(3):
        errors = tempfile.TemporaryFile()
        streams.append(errors)
        children.append(subprocess.Popen([
            root / 'scripts/build-slot.sh', 'build', sys.executable, '-u', '-c',
            "import os; print('READY '+os.readlink('/proc/self/fd/9'),flush=True); input()"], cwd=root,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=errors, text=True, pass_fds=(gate_fd,)))
    waiting = set(range(len(children)))
    started = last = time.monotonic()
    while waiting:
        ready, _, _ = select.select([children[i].stdout for i in waiting], [], [], 1)
        for stream in ready:
            index = next(i for i in waiting if children[i].stdout is stream)
            receipt = stream.readline().strip()
            if not receipt.startswith('READY ') or '/build' not in receipt:
                raise RuntimeError('FIFO reservation child failed')
            waiting.remove(index)
            print(f'build reservation {index + 1} admitted: PID {children[index].pid}, FD9 {receipt[6:]}', flush=True)
        if time.monotonic() - last >= 40:
            print(f'waiting for {len(waiting)} build reservations; {int(time.monotonic() - started)} seconds', flush=True)
            last = time.monotonic()
        if time.monotonic() - started > 900:
            raise RuntimeError('FIFO isolation admission deadline exceeded')
    print('outer gate and all FIFO build reservations held; timing isolated', flush=True)
    result = subprocess.run(sys.argv[1:], cwd=root, pass_fds=(gate_fd,))
    if result.returncode:
        raise RuntimeError(f'isolated measurement failed: {result.returncode}')
finally:
    for child in children:
        if child.poll() is None:
            try:
                child.communicate('\n', timeout=10)
            except Exception:
                child.terminate()
                child.wait(timeout=10)
    holder_failures = []
    for index, (child, stream) in enumerate(zip(children, streams)):
        stream.seek(0)
        admission = stream.read()
        receipt_path = Path('/home/epentland/.cache/mylang-tmp/selka-selfhost-pilots') / f'record-performance/build-slot-{index + 1}.log'
        receipt_path.write_bytes(admission)
        print(f'build reservation {index + 1} exit {child.returncode}; admission receipt {receipt_path}', flush=True)
        print(admission.decode(errors='replace'), flush=True)
        stream.close()
        if child.returncode != 0:
            holder_failures.append(f'holder {index + 1} exited {child.returncode}')
    os.close(gate_fd)
    print('all FIFO build reservations released', flush=True)
    if holder_failures:
        raise RuntimeError('; '.join(holder_failures))
