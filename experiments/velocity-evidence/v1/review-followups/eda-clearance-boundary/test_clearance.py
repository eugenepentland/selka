#!/usr/bin/env python3
"""Exact clearance boundaries through the application JSON interface."""
from test_cli import board, component, invoke


def tests():
    cases, expected = [], []
    # Explicit boundary triples, not an implementation of the geometry predicate.
    placements = [
        (15, 0, 5, False), (0, 15, 5, False), (13, 14, 5, False),
        (15, 0, 6, True), (0, 15, 6, True), (13, 14, 6, True),
        (15, 0, 4, False), (13, 14, 4, False),
        (10, 0, 0, False), (0, 10, 0, False), (10, 10, 0, False),
        (9, 0, 0, True), (0, 9, 0, True), (9, 9, 0, True),
        (0, 0, 0, True), (10, 10, 1, True),
    ]
    for unit in ("um", "mm"):
        for x, y, clearance, fails in placements:
            for reverse in (False, True):
                components = [component("a", x=20, y=20),
                              component("z", x=20+x, y=20+y)]
                if reverse:
                    components.reverse()
                cases.append(board(unit=unit, clearance=clearance, components=components))
                expected.append([{"code": "clearance", "subjects": ["a", "z"]}] if fails else [])
    # Full allowed magnitude, exact 3-4-5 distance after unit conversion.
    for clearance, fails in ((999999, False), (1000000, False)):
        cases.append(board(unit="mm", width=1000000, height=1000000,
                           clearance=clearance,
                           components=[component("z", x=600001, y=800001, width=1, height=1),
                                       component("a", width=1, height=1)]))
        expected.append([])
    # Containment is positive-area overlap even at zero clearance.
    cases.append(board(components=[component("z", x=1, y=1, width=1, height=1),
                                   component("a")]))
    expected.append([{"code": "clearance", "subjects": ["a", "z"]}])
    for start in range(0, len(cases), 64):
        results = invoke({"cases": cases[start:start+64]})["results"]
        for b, findings, actual in zip(cases[start:start+64], expected[start:start+64], results, strict=True):
            scale = 1000 if b["unit"] == "mm" else 1
            width, height = b["width"]*scale, b["height"]*scale
            svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}">'
                   f'<rect x="0" y="0" width="{width}" height="{height}" fill="white" stroke="black"/>')
            for c in sorted(b["components"], key=lambda c: c["id"]):
                svg += (f'<rect id="{c["id"]}" x="{c["x"]*scale}" y="{c["y"]*scale}" '
                        f'width="{c["width"]*scale}" height="{c["height"]*scale}" fill="none" stroke="black"/>')
            assert actual == {"unit": "um", "findings": findings, "nets": [], "svg": svg+"</svg>"}, (b, actual)
    print("exact clearance boundary cases passed")


if __name__ == "__main__":
    tests()
