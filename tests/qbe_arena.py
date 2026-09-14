#!/usr/bin/env python3
"""Native managed-arena parity: regions, the store barrier, escape and unwinding."""
import argparse
from pathlib import Path
import sys
import tempfile

import golden

from qbe_parity import ROOT, run, signature


def cases():
    # Dynamic extent: a helper with no idea an arena exists allocates into it.
    yield '''def squares(limit: int) -> list[int]:
    values: list[int] = []
    for index in range(limit):
        values.append(index * index)
    return values

def main() -> int:
    total = 0
    with arena() as scratch:
        values = squares(9)
        for value in values:
            total = total + value
    return total
'''
    # Nesting: the innermost arena wins and the outer allocation survives it.
    yield '''def sized(limit: int) -> list[int]:
    values: list[int] = []
    for index in range(limit):
        values.append(index)
    return values

def main() -> int:
    total = 0
    with arena() as outer:
        first = sized(3)
        with arena() as inner:
            second = sized(4)
            total = total + len(second)
        total = total + len(first)
    return total
'''
    # Escape preserves sharing inside the copied part.
    yield '''def main() -> int:
    kept: list[list[int]] = []
    with arena() as scratch:
        shared: list[int] = [7]
        holder: list[list[int]] = [shared, shared]
        kept = scratch.escape(holder)
    kept[0].append(9)
    return len(kept) * 10 + kept[0][0] + kept[1][1]
'''
    # Escape shares objects that already live in an older region.
    yield '''def main() -> int:
    older: list[int] = [5]
    kept: list[list[int]] = []
    with arena() as scratch:
        holder: list[list[int]] = [older]
        kept = scratch.escape(holder)
    older.append(6)
    return len(kept[0]) * 10 + kept[0][0]
'''
    # Escaping a nested field of a record graph built by a helper.
    yield '''class Reading:
    sensor: int
    samples: list[int]

def collect(sensors: int, per_sensor: int) -> list[Reading]:
    readings: list[Reading] = []
    for sensor in range(sensors):
        samples: list[int] = []
        for index in range(per_sensor):
            samples.append(sensor * per_sensor + index)
        readings.append(Reading(sensor=sensor, samples=samples))
    return readings

def main() -> int:
    kept: list[int] = []
    with arena() as scratch:
        readings = collect(3, 4)
        kept = scratch.escape(readings[2].samples)
    total = 0
    for sample in kept:
        total = total + sample
    return total
'''
    # Scalars leave an arena freely, so accumulation in an outer binding works.
    yield '''def main() -> int:
    total = 0
    with arena() as scratch:
        words: list[str] = ["alpha", "beta", "gamma"]
        for word in words:
            total = total + len(word)
    return total
'''
    # Dictionaries, text and byte strings are ordinary arena residents.
    yield '''def main() -> int:
    kept: dict[str, bytes] = {}
    with arena() as scratch:
        table: dict[str, bytes] = {}
        table["a"] = b"\\x01\\x02"
        table["b"] = ("x" + "y").encode()
        kept = scratch.escape(table)
    total = 0
    for value in kept["a"]:
        total += value
    return total + len(kept["b"]) + len(kept)
'''
    # Escape copies a cyclic managed graph once.
    yield '''def main() -> int:
    kept: list[list[int]] = []
    with arena() as scratch:
        cycle: list[list[int]] = []
        cycle.append([1, 2])
        kept = scratch.escape(cycle)
    return len(kept) + len(kept[0])
'''
    # Escaping a record value copies its managed fields and shares older ones.
    yield '''class Holder:
    label: str
    samples: list[int]
    flag: bool

def main() -> int:
    kept = Holder(label="", samples=[], flag=False)
    older: list[int] = [5]
    with arena() as scratch:
        inner: list[int] = [1, 2]
        kept = scratch.escape(Holder(label="deep", samples=inner, flag=True))
    older.append(6)
    kept.samples.append(3)
    return len(kept.label) + len(kept.samples) * 10 + len(older)
'''
    # Escaping an option payload keeps the variant tag and its copied graph.
    yield '''def main() -> int:
    kept: Option[list[int]] = None
    with arena() as scratch:
        found: Option[list[int]] = Some([4, 5, 6])
        kept = scratch.escape(found)
    match kept:
        case Some(values):
            values.append(7)
            return len(values)
        case None:
            return 0
'''
    # Loop exits out of a block release the arena exactly once.
    yield '''def main() -> int:
    total = 0
    for round in range(6):
        with arena() as scratch:
            values: list[int] = [round, round]
            if round == 2:
                continue
            if round == 4:
                break
            total = total + len(values) + round
    return total
'''
    # `?` propagation out of a block unwinds the arena.
    yield '''def build(limit: int) -> Result[int, int]:
    total = 0
    with arena() as scratch:
        values: list[int] = []
        for index in range(limit):
            values.append(index)
        if limit > 3:
            return Err(len(values))
        total = len(values)
    return Ok(total)

def chain(limit: int) -> Result[int, int]:
    answer = 0
    with arena() as outer:
        noise: list[int] = [limit]
        answer = build(limit)? + len(noise)
    return Ok(answer * 2)

def main() -> int:
    match chain(3):
        case Ok(value):
            match chain(9):
                case Ok(other):
                    return other
                case Err(code):
                    return value * 10 + code
        case Err(code):
            return 0 - code
'''
    # Returning a scalar from inside a block leaves no arena open.
    yield '''def inner(limit: int) -> int:
    with arena() as scratch:
        values: list[int] = []
        for index in range(limit):
            values.append(index)
        return len(values)

def main() -> int:
    total = 0
    for round in range(20):
        total = total + inner(round)
    return total
'''
    # A trap unwinding through a block still releases it.
    yield '''def main() -> int:
    with arena() as scratch:
        values: list[int] = [1]
        return values[5]
'''
    # The store barrier traps when a helper stores arena storage outward.
    yield '''def stash(outer: list[list[int]], inner: list[int]) -> None:
    outer.append(inner)

def main() -> int:
    keeper: list[list[int]] = []
    with arena() as scratch:
        temp: list[int] = [1]
        stash(keeper, temp)
    return len(keeper)
'''
    # The barrier covers dictionary values written through a helper.
    yield '''def stash(outer: dict[str, list[int]], inner: list[int]) -> None:
    outer["kept"] = inner

def main() -> int:
    keeper: dict[str, list[int]] = {}
    with arena() as scratch:
        temp: list[int] = [1]
        stash(keeper, temp)
    return len(keeper)
'''
    # The barrier covers an indexed slot write and a record-shaped value.
    yield '''class Holder:
    samples: list[int]

def stash(outer: list[Holder], inner: Holder) -> None:
    outer[0] = inner

def main() -> int:
    keeper: list[Holder] = [Holder(samples=[0])]
    with arena() as scratch:
        temp = Holder(samples=[1])
        stash(keeper, temp)
    return len(keeper)
'''
    # An older container accepts an older reference from inside an arena.
    yield '''def stash(outer: list[list[int]], inner: list[int]) -> None:
    outer.append(inner)

def main() -> int:
    keeper: list[list[int]] = []
    older: list[int] = [3]
    with arena() as scratch:
        stash(keeper, older)
        temp: list[int] = [1]
    return len(keeper) + keeper[0][0]
'''
    # Growth of an older list from inside an arena keeps its backing alive.
    yield '''def grow(outer: list[int], count: int) -> None:
    for index in range(count):
        outer.append(index)

def main() -> int:
    keeper: list[int] = []
    with arena() as scratch:
        grow(keeper, 40)
        noise: list[int] = []
        for index in range(40):
            noise.append(index)
    total = 0
    for value in keeper:
        total = total + value
    return total
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--qbe', default='qbe')
    parser.add_argument('--zig', default='zig')
    golden.argument(parser)
    args = parser.parse_args()
    reference = golden.Reference('qbe_arena', args.record)
    compiler = args.compiler.resolve()
    with tempfile.TemporaryDirectory(prefix='mylang-qbe-arena-') as directory:
        temp = Path(directory)
        reference.scrub = [(str(temp).encode(), b'<corpus>')]
        source, output = temp / 'case.my', temp / 'program'
        count = 0
        for text in cases():
            source.write_text(text)
            vm = reference.expect([text, []], [compiler, 'run', source, '--print-result'])
            built = run([sys.executable, ROOT / 'scripts/qbe.py', source, '-o', output,
                         '--compiler', compiler, '--qbe', args.qbe, '--zig', args.zig,
                         '--cache-dir', temp / 'cache'])
            assert built.returncode == 0, (text, built.stderr.decode())
            for options in ([], ['--gc-stress']):
                native = run([output, *options])
                assert signature(vm) == signature(native), (text, options, vm, native)
            count += 1
        reference.save()
    print(f'QBE managed arena parity: {count} cases passed')


if __name__ == '__main__':
    main()
