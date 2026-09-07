#!/usr/bin/env python3
"""Independent XML/netlist acceptance and source mutation tests for the VM schematic pilot."""
import argparse
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET

FIXTURES = Path(__file__).resolve().parents[1] / "experiments/schematic/fixtures"
NS = {"s": "http://www.w3.org/2000/svg"}


def parse_sexpr(text):
    """Small independent fixture reader; never used by the rendering pipeline."""
    stack = [[]]
    pattern = r';[^\n]*|"(?:\\.|[^"\\])*"|[()]|[^\s();]+'
    for match in re.finditer(pattern, text):
        token = match[0]
        if token.startswith(";"):
            continue
        if token == "(":
            child = []
            stack[-1].append(child)
            stack.append(child)
        elif token == ")":
            assert len(stack) > 1
            stack.pop()
        else:
            stack[-1].append(json.loads(token) if token.startswith('"') else token)
    assert len(stack) == 1
    return stack[0]


def fixture_model(source):
    module = next(x for x in parse_sexpr(source) if x[0] == "defmodule")
    block = next(x for x in module if isinstance(x, list) and x and x[0] == "design-block")
    components, aliases, pads, nc = {}, {}, {}, {}
    counts = Counter()
    for form in block[2:]:
        if form[0] != "instance":
            continue
        ref, spec = form[1:3]
        family, value = (spec[0], spec[1]) if isinstance(spec, list) else (spec, "")
        components[ref] = (family, value)
        prefix = {"cap": "C", "res": "R", "ind": "L"}.get(family[:3], "U")
        counts[prefix] += 1
        aliases[ref] = f"{prefix}{counts[prefix]}"
        for field in form[3:]:
            if field[0] == "pin":
                numbers = []
                for item in field[1:]:
                    if isinstance(item, str) and item.isdecimal():
                        numbers.append(item)
                    else:
                        net = item
                        break
                for number in numbers:
                    pads[(ref, number)] = net
            elif field[0] == "nc-ok":
                nc[(ref, field[1])] = field[2]
    return components, aliases, pads, nc


def inspect_svg(svg):
    root = ET.fromstring(svg)
    assert root.tag == f"{{{NS['s']}}}svg"
    components, pads, nc = {}, {}, {}
    for group in root.findall(".//s:g[@class='component']", NS):
        ref = group.attrib["data-ref"]
        assert ref not in components
        components[ref] = (group.attrib["data-family"], group.attrib["data-value"])
        for pin in group.findall(".//s:g[@data-pin]", NS):
            key = (ref, pin.attrib["data-pin"])
            assert key not in pads and key not in nc
            if "data-nc" in pin.attrib:
                nc[key] = pin.find("s:title", NS).text
            else:
                pads[key] = pin.attrib["data-net"]
    ports = {}
    for port in root.findall(".//s:g[@class='port']", NS):
        name = port.attrib["data-port"]
        assert name not in ports
        ports[name] = port.attrib["data-direction"]
    return root, components, pads, nc, ports


def execute(runner, docs):
    with tempfile.TemporaryDirectory(prefix="mylang-schematic-") as directory:
        paths = []
        for i, data in enumerate(docs):
            path = Path(directory) / f"source{i}.sexp"
            path.write_bytes(data if isinstance(data, bytes) else data.encode())
            paths.append(str(path))
        return subprocess.run([str(runner), *paths], capture_output=True, timeout=180)


def acceptance(runner, output):
    manifest = json.loads((FIXTURES / "manifest.json").read_text())
    docs = []
    for entry in manifest["files"]:
        data = (FIXTURES / entry["file"]).read_bytes()
        assert hashlib.sha256(data).hexdigest() == entry["sha256"]
        docs.append(data.decode())
    result = execute(runner, docs)
    assert result.returncode == 0, result.stderr.decode()
    root, parts, pads, nc, ports = inspect_svg(result.stdout)
    expected_parts, aliases, expected_pads, expected_nc = fixture_model(docs[0])
    assert parts == expected_parts and pads == expected_pads and nc == expected_nc
    assert (len(parts), len(pads), len(nc)) == (30, 95, 4)
    assert ports == {"REF_P": "in", "REF_N": "in", "LO_OUT": "out", "V_3V3": "in", "GND": "bidi", "SPI_SCK": "in", "SPI_SDI": "in", "SPI_SDO": "out", "SPI_CSN": "in"}
    actual_nets = defaultdict(set)
    for (ref, pad), net in pads.items():
        actual_nets[net].add(f"{aliases[ref]}.{pad}")
    oracle = {}
    for line in (FIXTURES / "netlisp-netlist.txt").read_text().splitlines():
        if line.startswith("#"):
            continue
        _, _, net, count, *members = line.split()
        assert int(count.removeprefix("pads=")) == len(members)
        oracle[net] = set(members)
    assert len(oracle) == 34 and dict(actual_nets) == oracle
    branches = root.findall(".//s:g[@data-net]", NS)
    folded = [p for p in branches if p.attrib["data-net"] != p.attrib["data-electrical-net"]]
    assert len(folded) == 12
    assert {p.attrib["data-electrical-net"] for p in folded} == {"V_3V3"}
    if output:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(result.stdout)
    changed = list(docs)
    changed_value = '470pF & <test> "quoted"\nline'
    changed[0] = changed[0].replace('"390pF"', json.dumps(changed_value)).replace('"LMX_CPOUT"', '"CP&<OUT>"')
    changed[0] = changed[0].replace('"SPI_SCK"', '"SPI_CLOCK"')
    changed[1] = changed[1].replace('"CPOUT"', '"CPOUT_ALT"')
    changed[2] = changed[2].replace('(signal SCK', '(signal CLOCK')
    updated = execute(runner, changed)
    assert updated.returncode == 0, updated.stderr.decode()
    changed_root, changed_parts, changed_pads, _, changed_ports = inspect_svg(updated.stdout)
    assert changed_parts["C_LF1"][1] == changed_value
    assert changed_ports["SPI_CLOCK"] == "in" and "SPI_SCK" not in changed_ports
    assert "CPOUT_ALT" in " ".join(changed_root.itertext())
    assert changed_pads[("U1", "12")] == "CP&<OUT>"
    assert sum(n == "CP&<OUT>" for n in changed_pads.values()) == 4
    assert b"&amp;" in updated.stdout and b"&lt;" in updated.stdout
    print("SVG: 30 components, 95 pads, 4 NC, 9 ports; all 34 nets match independent Netlisp dump; mutation updates output")
    cases = [
        (0, ")" + docs[0], 1),
        (0, docs[0][:-2], 4),
        (0, '(' * 129, 2),
        (0, '(note "unfinished', 3),
        (0, docs[0].replace('"390pF"', '"bad\\q"'), 6),
        (0, b'\xff', 8),
        (0, b'\x00', 8),
        (0, docs[0].replace('(pin 1 "LMX_CE")', '(pin 1 "LMX_CE") (pin 1 "other")'), 15),
        (0, docs[0].replace('(pin 1 "LMX_CE")', '(pin 99 "LMX_CE")'), 14),
        (0, docs[0].replace('(pin 1 "LMX_CE")', ''), 20),
        (0, docs[0].replace('(pin 2 "LMX_CE")', '(nc-ok 2 "unused")'), 13),
        (0, docs[0].replace('"C_VCCCP"', '"C_VCCDIG"'), 12),
        (0, docs[0].replace('(net-envelope', '(mystery-connect', 1), 17),
        (0, docs[0].replace('(id e7e79244)', '(wire hidden)'), 17),
        (0, docs[0].replace('straps-synth-lmx2595 ()', 'straps-synth-lmx2595 (parameter)'), 16),
        (0, docs[0].replace('(cap-0402 "390pF"', '(unknown-part "390pF"'), 19),
        (0, docs[0].replace('(port "REF_N"', '(port "REF_P"'), 22),
        (0, docs[0].replace('(port "REF_N"', '(port "DISCONNECTED"'), 23),
        (0, docs[0].replace('(rename MOSI', '(rename UNKNOWN'), 21),
        (0, docs[0].replace('(port-group "SPI" spi', '(port-group "SPI" unknown'), 21),
        (1, docs[1].replace('(pin 41 "EP_(GND)")', ''), 18),
        (1, docs[1].replace('(pin 41', '(pin 40'), 18),
        (1, docs[1].replace('"LMX2595RHAR"', '"UNRELATED"'), 19),
    ]
    def reject(case):
        index, data, code = case
        modified = list(docs)
        modified[index] = data
        failure = execute(runner, modified)
        assert failure.returncode != 0 and failure.stdout == b"", (code, failure.stderr)
        assert f"SCHEMATIC_{code}:".encode() in failure.stderr, (code, failure.stderr)
        assert re.search(rb"source\d.sexp:\d+:\d+:", failure.stderr), failure.stderr
    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(reject, cases))
    print(f"SVG: {len(cases)} malformed/unsupported/connectivity mutations rejected with located diagnostics and no partial SVG")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--runner", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    acceptance(args.runner.resolve(), args.output)


if __name__ == "__main__":
    main()
