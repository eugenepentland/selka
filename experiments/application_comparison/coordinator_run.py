"""Durable, bounded fresh-coordinator launches and unscored calibration."""
import math
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import time
from . import coordinator_receipt, process_identity
from .storage import canonical, digest, locked, read_json, write_json

ROOT = Path(__file__).resolve().parent


def execute(command, directory, *, wall_seconds, output_bytes, pass_fds=()):
    """Run a trusted command with bounded output; callers own configuration checks."""
    started = time.monotonic()
    reason, total = None, 0
    with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          stdin=subprocess.DEVNULL, start_new_session=True, pass_fds=pass_fds,
                          env={'PATH': '/usr/bin:/bin', 'LANG': 'C.UTF-8'}) as process:
        try:
            try:
                identity, _ = process_identity.capture(process.pid)
            except (OSError, ValueError):
                identity = None
            write_json(directory / 'process.json', {'pid': process.pid, 'started_utc_ns': time.time_ns(),
                                                  'identity': identity})
            with (directory / 'stdout').open('wb') as stdout, (directory / 'stderr').open('wb') as stderr:
                with selectors.DefaultSelector() as selector:
                    for stream, target in ((process.stdout, stdout), (process.stderr, stderr)):
                        os.set_blocking(stream.fileno(), False)
                        selector.register(stream, selectors.EVENT_READ, target)
                    while selector.get_map():
                        remaining = wall_seconds - (time.monotonic() - started)
                        if remaining <= 0:
                            reason = 'timeout'
                            break
                        for key, _ in selector.select(min(remaining, .1)):
                            chunk = os.read(key.fileobj.fileno(), 65536)
                            if not chunk:
                                selector.unregister(key.fileobj)
                                continue
                            capacity = max(0, output_bytes - total)
                            key.data.write(chunk[:capacity])
                            key.data.flush()
                            total += min(capacity, len(chunk))
                            if len(chunk) > capacity:
                                reason = 'output-limit'
                                break
                        if reason:
                            break
                for target in (stdout, stderr):
                    target.flush()
                    os.fsync(target.fileno())
            if reason is None:
                try:
                    process.wait(timeout=max(.001, wall_seconds - (time.monotonic() - started)))
                except subprocess.TimeoutExpired:
                    reason = 'timeout'
        finally:
            # Kill the session group even if the main worker already exited.
            # Namespace children also inherit their own parent-death chain.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=5)
    return {'outcome': reason or ('completed' if process.returncode == 0 else 'failed'),
            'returncode': process.returncode, 'elapsed_seconds': time.monotonic() - started,
            'captured_bytes': total}


def run(request, directory, *, wall_seconds=2400, output_bytes=4 * 1024**2, api_key=None):
    if not math.isfinite(wall_seconds) or not 0 < wall_seconds <= 7200:
        raise ValueError('invalid coordinator wall limit')
    if type(output_bytes) is not int or not 0 < output_bytes <= 64 * 1024**2:
        raise ValueError('invalid coordinator output limit')
    if not isinstance(request, dict) or request.get('operation') not in ('probe', 'fixture', 'calibration', 'grade-fixture', 'grade-calibration'):
        raise ValueError('unsupported coordinator operation; scored launches are disabled')
    calibration = request['operation'] == 'calibration'
    credential = None
    if calibration:
        if not isinstance(api_key, str) or not api_key or any(c in api_key for c in '\r\n\0'):
            raise ValueError('calibration requires an API key supplied separately from the request')
        credential = api_key.encode('utf-8')
        if len(credential) > 4096:
            raise ValueError('API key exceeds credential limit')
        allowed = {'operation', 'coordinator', 'transport_identity', 'cohort', 'envelope', 'endpoint'}
        if set(request) - allowed:
            raise ValueError('unsupported calibration request fields')
    elif api_key is not None:
        raise ValueError('credentials are only accepted for calibration execution')
    if len(canonical(request)) > 16 * 1024**2:
        raise ValueError('coordinator request exceeds size limit')
    directory = Path(directory).resolve()
    directory.mkdir(exist_ok=False)
    with locked(directory):
        write_json(directory / 'request.json', request)
        request = read_json(directory / 'request.json')
        launch = {'version': 'coordinator-launch-v1', 'request_sha256': digest(request),
                  'wall_seconds': wall_seconds, 'output_bytes': output_bytes, 'record_kind': 'calibration' if request['operation'] in ('calibration', 'grade-calibration') else 'fixture'}
        write_json(directory / 'launch.json', launch)
        try:
            coordinator_receipt.verify(request['coordinator'], transport_identity=request['transport_identity'])
            command = [sys.executable, '-I', '-S', '-B', str(ROOT / 'isolation_launcher.py'), str(os.getpid()),
                       sys.executable, '-I', '-S', '-B', str(ROOT / 'fresh_coordinator.py'), str(directory / 'request.json')]
            if credential is None:
                result = execute(command, directory, wall_seconds=wall_seconds, output_bytes=output_bytes)
            else:
                read_fd, write_fd = os.pipe()
                try:
                    try:
                        # At most PIPE_BUF bytes, with an empty pipe; no reader needed yet.
                        if os.write(write_fd, credential) != len(credential):
                            raise OSError('incomplete credential handoff')
                    finally:
                        os.close(write_fd)
                    result = execute(command + [str(read_fd)], directory, wall_seconds=wall_seconds,
                                     output_bytes=output_bytes, pass_fds=(read_fd,))
                finally:
                    os.close(read_fd)
            model_calls = None if calibration else 0
            if result['outcome'] == 'completed':
                report = read_json(directory / 'stdout')
                if (report.get('version') != 'fresh-coordinator-result-v1' or
                        report.get('operation') != request['operation'] or
                        report.get('coordinator_sha256') != request['coordinator']['sha256'] or
                        type(report.get('model_calls')) is not int or report['model_calls'] < 0 or
                        (not calibration and report['model_calls'] != 0)):
                    raise ValueError('fresh coordinator result identity mismatch')
                result['worker_report_sha256'] = digest(report)
                model_calls = report['model_calls']
            result.update(version='coordinator-launch-result-v1', launch_sha256=digest(launch), model_calls=model_calls)
            write_json(directory / 'result.json', result)
            return result
        except Exception as error:
            write_json(directory / 'interrupted.json', {'type': type(error).__name__, 'message': str(error),
                       'recovery': 'inspect retained records; never silently restart this directory'})
            raise


def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request', type=Path, required=True)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--wall-seconds', type=float, default=2400)
    parser.add_argument('--output-bytes', type=int, default=4 * 1024**2)
    args = parser.parse_args()
    request = read_json(args.request)
    # Never accept credentials in command-line arguments or the request artifact.
    key = os.environ.get('OPENAI_API_KEY') if request.get('operation') == 'calibration' else None
    result = run(request, args.directory, wall_seconds=args.wall_seconds,
                 output_bytes=args.output_bytes, api_key=key)
    print(result['outcome'], 'records:', args.directory)
    return 0 if result['outcome'] == 'completed' else 1


if __name__ == '__main__':
    sys.exit(main())
