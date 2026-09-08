#!/usr/bin/env python3
"""Rotation contract regressions; Python is a fixture/assertion driver only."""
import copy
import json
import random
from pathlib import Path
from test_cli import board, component, invoke, result


def rotated(rotation, **kwargs):
    value = component(**kwargs)
    value["rotation"] = rotation
    return value


def tests():
    # Asymmetric footprints: a quarter turn removes overlap, fits the right
    # edge and reaches the bottom edge exactly. Centers retain half units.
    members = [{"component": "a", "pin": "p"}, {"component": "b", "pin": "p"}]
    base = board(width=8, height=9, clearance=3,
                 components=[component("b", x=6, y=1, width=2, height=1, pins=["p"]),
                             component("a", width=9, height=3, pins=["p"])],
                 nets=[{"id": "n", "members": list(reversed(members))}])
    before = result(base)
    assert before["findings"] == [
        {"code": "clearance", "subjects": ["a", "b"]},
        {"code": "outside-board", "subjects": ["a"]}]
    assert before["nets"][0]["span"] == 3
    expected_svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 8 9">'
                    '<rect x="0" y="0" width="8" height="9" fill="white" stroke="black"/>'
                    '<rect id="a" x="0" y="0" width="3" height="9" fill="none" stroke="black"/>'
                    '<rect id="b" x="6" y="1" width="2" height="1" fill="none" stroke="black"/>'
                    '</svg>')
    for angle in (0, 90, 180, 270):
        case = copy.deepcopy(base)
        case["components"][1]["rotation"] = angle
        actual = result(case)
        if angle in (0, 180):
            assert actual == before
        else:
            assert actual == {"unit": "um", "findings": [],
                              "nets": [{"id": "n", "members": members, "span": 9}],
                              "svg": expected_svg}
            # Unit conversion occurs before upward rounding, yielding 8500.
            case["unit"] = "mm"
            assert result(case)["nets"][0]["span"] == 8500
    outside = copy.deepcopy(base)
    outside["components"][1]["rotation"] = 90
    outside["components"][1]["y"] = 1
    assert result(outside)["findings"] == [{"code": "outside-board", "subjects": ["a"]}]

    invalid = []
    for angle in (True, False, 0.0, 90.0, 180.0, 270.0, None, "90", [], {},
                  -90, 45, 360, 9223372036854775807, -9223372036854775808):
        invalid.append(board(components=[rotated(angle, id="a")]))
    for field in ("id", "x", "y", "width", "height", "pins"):
        c = rotated(90, id="a")
        del c[field]
        invalid.append(board(components=[c]))
        c["unrelated"] = 0  # Same field count cannot mask missing fields.
        invalid.append(board(components=[c]))
    for c in (dict(component("a"), extra=1),
              dict(rotated(90, id="a"), extra=1),
              dict(rotated(90, id="a"), pins=["p", "p"])):
        invalid.append(board(components=[c]))
    # Rotation schema errors precede all duplicate/reference semantic errors.
    invalid.append(board(components=[component("a"), component("a"),
                                     rotated(45, id="z")],
                         nets=[{"id": "n", "members": [{"component": "missing", "pin": "p"}]}]))
    assert invoke({"cases": invalid}) == {"results": [{"error": "invalid-board"}] * len(invalid)}

    # All quarter turns must equal an ordinary occupied rectangle for every
    # output field. Include negative coordinates, mixed rotations, odd dimensions,
    # multiple nets, disconnected pins, units, and order variations.
    rng = random.Random(8371)
    fixtures = []
    equivalents = []
    for index in range(32):
        components = [rotated(rng.choice((0, 90, 180, 270)), id=chr(97+i),
                              x=rng.randint(-2, 25), y=rng.randint(-2, 25),
                              width=rng.randint(1, 13), height=rng.randint(1, 13),
                              pins=["p", "q"]) for i in range(4)]
        rng.shuffle(components)
        case = board(unit=("um" if index % 2 else "mm"), width=30, height=30,
                     clearance=rng.randint(0, 8), components=components,
                     nets=[{"id": "wire", "members": [{"component": c["id"], "pin": "p"}
                                                       for c in components]},
                           {"id": "empty", "members": []}])
        normalized = copy.deepcopy(case)
        for c in normalized["components"]:
            angle = c.pop("rotation")
            if angle in (90, 270):
                c["width"], c["height"] = c["height"], c["width"]
        fixtures.append(case)
        equivalents.append(normalized)
    assert invoke({"cases": fixtures}) == invoke({"cases": equivalents})
    # Decoded optional field names retain the transport's duplicate-key rule.
    raw = json.dumps({"cases": [board(components=[rotated(90, id="a")])]})
    escaped = raw.replace("rotation", "\\u0072otation")
    assert invoke(escaped.encode()) == invoke(raw.encode())
    duplicate = raw.replace('"rotation": 90', '"rotation": 90, "\\u0072otation": 0')
    assert invoke(duplicate.encode()) == {"error": "invalid-request"}
    print("rotation schema, geometry, exact SVG, precedence and equivalence cases passed")


if __name__ == "__main__":
    tests()
