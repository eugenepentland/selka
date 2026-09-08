#!/usr/bin/env python3
"""Pin-role schema, electrical rules, ordering and v1 report preservation."""
from copy import deepcopy
from itertools import product
import json
from test_cli import board, component, invoke


def net(name, *pins):
    return {"id": name, "members": [{"component": c, "pin": p} for c, p in pins]}


def run(boards):
    results = []
    for start in range(0, len(boards), 64):
        results.extend(invoke({"cases": boards[start:start + 64]})["results"])
    return results


def tests():
    base = board(components=[component("a", pins=["p"]), component("b", x=20, pins=["p"]),
                             component("c", x=40, pins=["p"])],
                 nets=[net("n", ("c", "p"), ("a", "p"), ("b", "p"))])
    original = run([base])[0]
    variants, expected = [], []
    for roles in product(("passive", "input", "output"), repeat=3):
        b = deepcopy(base)
        for c, role in zip(b["components"], roles):
            c["pin_roles"] = [{"pin": "p", "role": role}]
        findings = []
        if roles.count("output") >= 2:
            findings.append({"code": "multiple-drivers", "subjects": ["n"]})
        if "input" in roles and "output" not in roles:
            findings.append({"code": "undriven-input-net", "subjects": ["n"]})
        want = deepcopy(original)
        want["findings"] = findings
        variants.append(b)
        expected.append(want)
    assert run(variants) == expected

    # Explicit passive, empty assignments, and omitted roles retain all v1 output.
    passive = deepcopy(base)
    passive["components"][0]["pin_roles"] = []
    passive["components"][2]["pin_roles"] = [{"pin": "p", "role": "passive"}]
    assert run([passive])[0] == original

    mixed = board(components=[component("z", x=-1, pins=["o", "p", "i", "unused"]),
                              component("a", pins=["o", "p", "i"])],
                  nets=[net("z", ("z", "o"), ("a", "o")),
                        net("a", ("z", "p"), ("a", "p")),
                        net("single", ("z", "i")), net("input", ("a", "i")),
                        net("empty")])
    baseline = run([mixed])[0]
    for c in mixed["components"]:
        c["pin_roles"] = [{"pin": "o", "role": "output"}, {"pin": "p", "role": "output"},
                          {"pin": "i", "role": "input"}]
    mixed["components"][0]["pin_roles"].append({"pin": "unused", "role": "input"})
    want = deepcopy(baseline)
    want["findings"] += [{"code": "multiple-drivers", "subjects": [n]} for n in ("a", "z")]
    want["findings"] += [{"code": "undriven-input-net", "subjects": [n]} for n in ("input", "single")]
    want["findings"].sort(key=lambda f: (f["code"], f["subjects"]))
    permuted = deepcopy(mixed)
    permuted["components"].reverse()
    permuted["nets"].reverse()
    for c in permuted["components"]:
        c["pins"].reverse()
        c["pin_roles"].reverse()
    for n in permuted["nets"]:
        n["members"].reverse()
    assert run([mixed, permuted]) == [want, want]

    invalid = []
    values = [None, {}, "input", 1, True,
              [None], [[]], ["input"], [{}],
              [{"pin": "p"}], [{"role": "input"}],
              [{"pin": "p", "role": "input", "extra": 1}],
              [{"pin": "p", "other": "input"}],
              [{"pin": "missing", "role": "input"}],
              [{"pin": "p", "role": "input"}, {"pin": "p", "role": "output"}],
              [{"pin": "p", "role": "passive"}] * 33]
    for role in (None, True, 1, [], {}, "INPUT", "driver", ""):
        values.append([{"pin": "p", "role": role}])
    for pin in (None, True, 1, [], {}, "P", ""):
        values.append([{"pin": pin, "role": "input"}])
    for value in values:
        b = deepcopy(base)
        b["components"][0]["pin_roles"] = value
        invalid.append(b)
    for field in ("id", "x", "y", "width", "height", "pins"):
        b = deepcopy(base)
        b["components"][0]["pin_roles"] = []
        del b["components"][0][field]
        invalid.append(b)
    for with_roles in (False, True):
        b = deepcopy(base)
        b["components"][0]["extra"] = 1
        if with_roles:
            b["components"][0]["pin_roles"] = []
        invalid.append(b)
    # Local role mistakes stay schema errors before every semantic error phase.
    for bad in ("duplicate", "unknown", "reused"):
        b = deepcopy(invalid[0])
        if bad == "duplicate":
            b["components"].append(deepcopy(b["components"][1]))
        elif bad == "unknown":
            b["nets"][0]["members"].append({"component": "absent", "pin": "p"})
        else:
            b["nets"][0]["members"].append(deepcopy(b["nets"][0]["members"][0]))
        invalid.append(b)
    assert run(invalid) == [{"error": "invalid-board"}] * len(invalid)

    # Valid roles do not bypass reference errors.
    semantic = deepcopy(base)
    for c in semantic["components"]:
        c["pin_roles"] = [{"pin": "p", "role": "output"}]
    semantic["nets"][0]["members"].append({"component": "absent", "pin": "p"})
    assert run([semantic]) == [{"error": "unknown-pin", "refs": [{"component": "absent", "pin": "p"}]}]
    semantic["nets"][0]["members"][-1] = {"component": "a", "pin": "p"}
    assert run([semantic]) == [{"error": "reused-pin", "refs": [{"component": "a", "pin": "p"}]}]

    pins = ["p" + str(i) for i in range(32)]
    full = board(components=[component("a", pins=pins)],
                 nets=[net("n", *(("a", p) for p in pins))])
    full["components"][0]["pin_roles"] = [{"pin": p, "role": "output"} for p in pins]
    assert run([full])[0]["findings"] == [{"code": "multiple-drivers", "subjects": ["n"]}]
    # Matching uses decoded identifiers and keys.
    encoded = json.dumps({"cases": [full]}).replace('"p0"', '"\\u00700"').replace('"pin_roles"', '"pin_\\u0072oles"')
    assert invoke(encoded.encode()) == {"results": run([full])}
    duplicate = deepcopy(base)
    duplicate["components"][0]["pin_roles"] = [{"pin": "p", "role": "input"},
                                              {"pin": "p", "role": "input"}]
    encoded = json.dumps({"cases": [duplicate]}).replace('"p"', '"\\u0070"')
    assert invoke(encoded.encode()) == {"results": [{"error": "invalid-board"}]}
    print("pin-role schema, rule combinations, ordering and preservation checks passed")


if __name__ == "__main__":
    tests()
