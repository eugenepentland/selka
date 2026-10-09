"""Real typed-call worker applications, parallel processes and cancellation cleanup."""
import argparse
from dataclasses import replace
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from workers import Limits, Pool, canonical, schema_identity

SOURCE = b'''







public class Stats:
    sum: i64
    squares: i64


public result Time:
    ok: i64,
    err: i64


public func analyze(values: [4]i64) -> Stats:
    sum = 0
    squares = 0
    i = 0u64
    while i < 4u64:
        n = values[i]
        sum += n
        squares += n * n
        i += 1u64
    return Stats(sum=sum, squares=squares)


public func loop(n: i64) -> i64:
    i = n
    while True:
        i += 1
        if i == 1000000:
            i = 0
    return i


public func nodata():
    pass


public func clock(c: clock_cap) -> Time:
    return clock_now[Time](c)


func main() -> i64:
    return 0
'''


def request(schema, function='main::analyze', arguments=None):
    return canonical({'version': 'typed-call-v1', 'schema_sha256': schema,
                      'function': function, 'arguments': arguments or {'values': ['1', '2', '3', '4']}})


def rejects(function, kind):
    try:
        function()
    except kind:
        return
    raise AssertionError('expected rejection')


def application(compiler, directory):
    sources = {'main.selka': bytearray(SOURCE)}
    limits = Limits(workers=2, pending=3, steps=1000000000, seconds=5)
    with Pool(compiler, limits, directory=directory) as pool:
        schema = pool.schema(sources)
        assert schema.state == 'succeeded', schema
        identity = schema_identity(schema.output)
        message = bytearray(request(identity))
        first = pool.submit(sources, message)
        second = pool.submit(sources, request(identity, arguments={'values': ['5', '6', '7', '8']}))
        # Both children have been started without waiting for either result.
        assert first.running and second.running
        assert first._process.pid != second._process.pid
        third = pool.submit(sources, message)
        assert not third.running
        rejects(lambda: pool.submit(sources, message), RuntimeError)
        sources['main.selka'][:] = b'invalid mutated caller storage'
        message[:] = b'invalid mutated caller message'
        assert pool.cancel(third).state == 'cancelled'
        assert not third._directory.exists()
        one, two = pool.wait(first), pool.wait(second)
        assert one.state == two.state == 'succeeded', (one, two)
        assert json.loads(one.output)['value'] == {'sum': '10', 'squares': '30'}
        assert json.loads(two.output)['value'] == {'sum': '26', 'squares': '174'}
        assert one.identity.source_sha256 == two.identity.source_sha256 == schema.identity.source_sha256
        assert one.identity.compiler_sha256 == pool.compiler_sha256
        assert one.identity.request_sha256 != two.identity.request_sha256
        assert not first._directory.exists() and not second._directory.exists()
        sources = {'main.selka': SOURCE}
        cancelled = pool.submit(sources, request(identity, 'main::loop', {'n': '0'}))
        pid = cancelled._process.pid
        started = time.monotonic()
        result = pool.cancel(cancelled)
        assert result.state == 'cancelled' and not result.output
        assert time.monotonic() - started < 2
        rejects(lambda: os.waitpid(pid, os.WNOHANG), ChildProcessError)
        assert pool.wait(pool.submit(sources, request(identity))).state == 'succeeded'
        failures = []
        def foreign_thread():
            try:
                pool.poll()
            except RuntimeError:
                failures.append(True)
        thread = threading.Thread(target=foreign_thread)
        thread.start()
        thread.join()
        assert failures == [True]
        for function, arguments in [('main::nodata', {}), ('main::clock', {'c': False})]:
            denied = pool.wait(pool.submit(sources, request(identity, function, arguments)))
            assert denied.state == 'failed' and not denied.output, denied
        stale = pool.wait(pool.submit(sources, request('0' * 64)))
        assert stale.state == 'failed' and not stale.output
        rejects(lambda: pool.submit({'../main.selka': SOURCE}, request(identity)), ValueError)
        rejects(lambda: pool.submit(sources, b'x' * (limits.message_bytes + 1)), ValueError)
        root = pool._root
        unfinished = pool.submit(sources, request(identity, 'main::loop', {'n': '0'}))
    assert unfinished.result.state == 'cancelled' and not root.exists()
    rejects(lambda: pool.submit(sources, request(identity)), RuntimeError)
    return identity


def limits_checks(compiler, directory, identity):
    sources = {'main.selka': SOURCE}
    with Pool(compiler, Limits(seconds=0.1, steps=1000000000), directory=directory) as pool:
        limited = pool.wait(pool.submit(sources, request(identity, 'main::loop', {'n': '0'})))
        assert limited.state == 'time_limit' and not limited.output, limited
    with Pool(compiler, Limits(output_bytes=8), directory=directory) as pool:
        limited = pool.wait(pool.submit(sources, request(identity)))
        assert limited.state == 'output_limit' and not limited.output, limited
    with Pool(compiler, Limits(steps=10), directory=directory) as pool:
        limited = pool.wait(pool.submit(sources, request(identity)))
        assert limited.state == 'failed' and not limited.output, limited
    with Pool(compiler, replace(Limits(), source_bytes=16), directory=directory) as pool:
        rejects(lambda: pool.submit(sources, request(identity)), ValueError)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix='worker-tests-', dir=root / '.zig-cache') as directory:
        identity = application(args.compiler, directory)
        limits_checks(args.compiler, directory, identity)
        assert not list(Path(directory).iterdir())
    print('workers: parallel typed applications, immutable snapshots, admission limits, cancellation/reaping, deadlines, publication and provider/reference denial pass')


if __name__ == '__main__':
    main()
