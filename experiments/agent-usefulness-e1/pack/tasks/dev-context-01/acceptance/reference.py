#!/usr/bin/env python3
"""The independent CPython oracle for dev-context-01 (rank_in_place).

The expected line for each scenario is computed here with Python's own stable
sort over plain ``(name, value)`` pairs - a different implementation of the
brief's rule from the candidate's mylang source. ``tie`` and ``alias`` are the
two bindings of the same list, so a candidate that sorts a copy and returns it
without mutating the caller's list fails both lines even though a fresh sorted
list would look correct.

The rule (brief.md): rank by descending value, in place, stable for equal
values, and the caller's list holds the result afterwards. ``show`` formats one
scenario as ``"<label> n<count> <name>:<value> ... "``.
"""
from __future__ import annotations

SCENARIOS = (
    ('tie', (('a', 3), ('b', 9), ('c', 3))),
    ('alias', (('a', 3), ('b', 9), ('c', 3))),
    ('single', (('solo', 5),)),
    ('ordered', (('p', 9), ('q', 7))),
    ('empty', ()),
    ('equal', (('e1', 4), ('e2', 4), ('e3', 4))),
    ('negative', (('x', -3), ('y', -9))),
)


def ranked(readings: tuple[tuple[str, int], ...]) -> list[tuple[str, int]]:
    """The rule, spelled with Python's stable sort over descending value."""
    return sorted(readings, key=lambda reading: -reading[1])


def show(label: str, readings) -> str:
    """One probe line, byte for byte as probe.my composes it."""
    text = ''.join(f'{name}:{value} ' for name, value in readings)
    return f'{label} n{len(readings)} {text}'


def expected_lines() -> list[str]:
    """Every line the hidden probe must print, in order."""
    return [show(label, ranked(readings)) for label, readings in SCENARIOS]


if __name__ == '__main__':
    for expected in expected_lines():
        print(expected)
