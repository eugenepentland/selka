#!/usr/bin/env python3
"""Check all isolated helpers against integer oracles and retain each outcome."""
import argparse
import ctypes
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import random

spec = importlib.util.spec_from_file_location('fixtures', Path(__file__).with_name('generate-ir.py'))
fixtures = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixtures)
MIN, MAX = -(1 << 63), (1 << 63) - 1


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def oracle(shape, divisor, seed, values):
    total = seed if shape == 'seeded_bool' else 0
    for value in values:
        increment = value if shape == 'signed_updates' else int(value != 0)
        addition = total + increment
        if addition < MIN or addition > MAX:
            return 0, 1
        total = addition % divisor
        assert 0 <= total < divisor
    return total, 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('library', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    before_hash = digest(args.library)
    library = ctypes.CDLL(str(args.library.resolve()))
    rng = random.Random(20261004)
    outcomes, summaries = [], {}
    started = datetime.now(timezone.utc).isoformat()
    for divisor in fixtures.DIVISORS:
        values = {MIN, MIN + 1, MAX, MAX - 1, -1, 0, 1}
        for multiple in (1, 2, 3, 7, 31, 1024):
            for sign in (-1, 1):
                for offset in (-1, 0, 1):
                    candidate = sign * divisor * multiple + offset
                    if MIN <= candidate <= MAX:
                        values.add(candidate)
        values.update(rng.randrange(MIN, MAX + 1) for _ in range(1024))
        for variant in fixtures.VARIANTS:
            name = f'scalar_{variant}_d{divisor}'
            function = getattr(library, name)
            function.argtypes, function.restype = [ctypes.c_int64], ctypes.c_int64
            begin = len(outcomes)
            for value in sorted(values):
                result, expected = function(value), value % divisor
                assert result == expected, (name, value, result, expected)
                outcomes.append({'function': name, 'value': value, 'expected': expected, 'result': result})
            summaries[name] = len(outcomes) - begin
    for divisor in fixtures.LOOP_DIVISORS:
        for shape in ('zero_bool', 'seeded_bool', 'signed_updates'):
            if shape == 'signed_updates':
                cases = [(0, values) for values in ([], [MIN], [MAX], [-1], [1],
                         [MAX, MAX], [1, MAX], [MAX, 1], [MIN, MIN],
                         [-1, MIN], [MIN, 1], [1, -1] * 20,
                         [divisor - 1, 1], [-divisor, -1, 1], [MIN, MAX, 0, -1, 1])]
                for _ in range(128):
                    values = [rng.choice((MIN, MAX, -1, 0, 1, divisor - 1,
                                          -divisor + 1, rng.randrange(MIN, MAX + 1)))
                              for _ in range(rng.randrange(65))]
                    cases.append((rng.randrange(MIN, MAX + 1), values))
            else:
                cases = [(seed, values) for seed in (MIN, -divisor, -1, 0, 1,
                         divisor - 1, divisor, MAX) for values in ([], [0], [1], [255],
                         [1, 0, 1], [1] * 67, [0] * 67, [1, 0] * 31)]
                for _ in range(128):
                    seed = rng.randrange(MIN, MAX + 1)
                    values = [rng.choice((0, 1, 2, 128, 255)) for _ in range(rng.randrange(129))]
                    cases.append((seed, values))
            for variant in fixtures.VARIANTS:
                name = f'loop_{shape}_{variant}_d{divisor}'
                function = getattr(library, name)
                function.argtypes = [ctypes.c_void_p, ctypes.c_uint64, ctypes.c_int64,
                                     ctypes.POINTER(ctypes.c_int32)]
                function.restype = ctypes.c_int64
                begin = len(outcomes)
                for seed, values in cases:
                    element = ctypes.c_int64 if shape == 'signed_updates' else ctypes.c_uint8
                    data = (element * len(values))(*values)
                    status = ctypes.c_int32(-73)
                    result = function(data, len(values), seed, ctypes.byref(status))
                    expected, expected_status = oracle(shape, divisor, seed, values)
                    assert (result, status.value) == (expected, expected_status), (
                        name, seed, values, result, status.value, expected, expected_status)
                    outcomes.append({'function': name, 'seed': seed, 'values': values,
                                     'expected': expected, 'result': result,
                                     'expected_status': expected_status, 'status': status.value})
                summaries[name] = len(outcomes) - begin
    assert digest(args.library) == before_hash
    document = {'status': 'passed', 'started_utc': started,
                'finished_utc': datetime.now(timezone.utc).isoformat(),
                'library_path': str(args.library.resolve()), 'library_sha256': before_hash,
                'functions': summaries, 'outcomes': outcomes, 'count': len(outcomes),
                'overflow_outcomes': sum(row.get('status') == 1 for row in outcomes),
                'driver_sha256': digest(Path(__file__)),
                'scope': 'Isolated IR semantics and assembly only; no runtime/benchmark/backend edits or timing.'}
    args.output.write_text(json.dumps(document, indent=2) + '\n')
    print('PASS', len(summaries), 'functions;', len(outcomes), 'individual oracle outcomes;',
          document['overflow_outcomes'], 'preserved overflow statuses')


if __name__ == '__main__':
    main()
