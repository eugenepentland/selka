#!/usr/bin/env python3
"""Independent drawn-wire geometry acceptance for the disk-loaded schematic renderer."""
import argparse
from collections import defaultdict
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'experiments/schematic/fixtures'
NAMESPACE = '{http://www.w3.org/2000/svg}'


def execute(runner, project, source):
    with tempfile.TemporaryDirectory(prefix='schematic-geometry-') as directory:
        document = Path(directory) / 'changed.sexp'
        document.write_text(source)
        result = subprocess.run([str(runner), '--project', str(project), str(document),
                                 str(FIXTURES / 'lmx2595rhar.sexp'), str(FIXTURES / 'spi.sexp')],
                                capture_output=True, timeout=180)
        assert result.returncode == 0, result.stderr.decode(errors='replace')
        return ET.fromstring(result.stdout)


def point_on_segment(point, segment):
    (x, y), ((x1, y1), (x2, y2)) = point, segment
    return min(x1, x2) <= x <= max(x1, x2) and min(y1, y2) <= y <= max(y1, y2)


def connected_segments(a, b):
    return any(point_on_segment(point, b) for point in a) or any(point_on_segment(point, a) for point in b)


def connected(points, segments):
    """A segment graph avoids assuming intermediate polyline bends are junction nodes."""
    if not points:
        return True
    reachable = {i for i, segment in enumerate(segments) if point_on_segment(points[0], segment)}
    while True:
        extra = {i for i, segment in enumerate(segments)
                 if any(connected_segments(segment, segments[j]) for j in reachable)}
        if extra <= reachable:
            break
        reachable |= extra
    return all(any(point_on_segment(point, segments[i]) for i in reachable) for point in points)


def geometry(svg):
    pins, nets, segments = {}, defaultdict(list), defaultdict(list)
    aliases, branches = {}, defaultdict(list)
    chips = []
    for component in svg.iter(NAMESPACE + 'g'):
        if 'data-ref' not in component.attrib:
            continue
        chip = component.find(NAMESPACE + "rect[@class='chip']")
        chip_pins = set()
        if chip is not None:
            box = tuple(int(chip.attrib[name]) for name in ('x', 'y', 'width', 'height'))
            chips.append((box, chip_pins))
        for pin in component.iter(NAMESPACE + 'g'):
            if 'data-pin' not in pin.attrib or 'data-nc' in pin.attrib:
                continue
            key = component.attrib['data-ref'], pin.attrib['data-pin']
            point = int(pin.attrib['data-x']), int(pin.attrib['data-y'])
            net = pin.attrib.get('data-electrical-net', pin.attrib['data-net'])
            aliases[pin.attrib['data-net']] = net
            branches[pin.attrib['data-net']].append(point)
            assert key not in pins, key
            pins[key] = net, point
            chip_pins.add((net, point))
            nets[net].append(point)
            for line in pin.findall(NAMESPACE + 'line'):
                a = int(line.attrib['x1']), int(line.attrib['y1'])
                b = int(line.attrib['x2']), int(line.attrib['y2'])
                assert a[0] == b[0] or a[1] == b[1]
                segments[net].append((a, b))
    for wire in svg.iter(NAMESPACE + 'g'):
        if 'wire' not in wire.attrib.get('class', '').split():
            continue
        net = aliases.get(wire.attrib['data-net'], wire.attrib['data-net'])
        for line in wire.findall(NAMESPACE + 'line'):
            a = int(line.attrib['x1']), int(line.attrib['y1'])
            b = int(line.attrib['x2']), int(line.attrib['y2'])
            assert a[0] == b[0] or a[1] == b[1], ('non-Manhattan wire', net, a, b)
            segments[net].append((a, b))
    assert len(pins) == 95 and segments, (len(pins), len(segments))
    x, y, width, height = map(float, svg.attrib['viewBox'].split())
    positions = {}
    for key, (net, point) in pins.items():
        assert x <= point[0] <= x + width and y <= point[1] <= y + height, ('clipped pad', key, point)
        assert point not in positions or positions[point] == net, ('different-net pads overlap', key, net, point, positions.get(point))
        positions[point] = net
    for net, points in nets.items():
        if net == 'GND' or net.startswith('V_') or len(points) < 2:
            continue
        assert connected(points, segments[net]), ('disconnected drawn net', net, points, segments[net])
    for raw, points in branches.items():
        if raw != aliases[raw] and len(points) > 1:
            assert connected(points, segments[aliases[raw]]), ('disconnected local rail branch', raw, points)
    for key, (net, point) in pins.items():
        for other, wires in segments.items():
            if other != net:
                assert not any(point_on_segment(point, wire) for wire in wires), (
                    'wire touches another net pad', key, net, point, other)
    for (left, top, width, height), chip_pins in chips:
        right, bottom = left + width, top + height
        for net, wires in segments.items():
            for (x1, y1), (x2, y2) in wires:
                if x1 == x2 and left <= x1 <= right:
                    assert max(min(y1, y2), top) >= min(max(y1, y2), bottom), ('wire hidden by chip', net, (x1, y1), (x2, y2))
                if y1 == y2 and top < y1 < bottom:
                    assert max(min(x1, x2), left) >= min(max(x1, x2), right), ('wire crosses chip body', net, (x1, y1), (x2, y2))
                    for edge in (left, right):
                        if min(x1, x2) <= edge <= max(x1, x2):
                            assert (net, (edge, y1)) in chip_pins, ('wire meets chip without matching pin', net, edge, y1)
    return pins, segments


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runner', type=Path, required=True)
    parser.add_argument('--project', type=Path, default=ROOT / 'src/schematic/guest')
    args = parser.parse_args()
    source = (FIXTURES / 'straps-synth-lmx2595.sexp').read_text()
    baseline = geometry(execute(args.runner.resolve(), args.project.resolve(), source))
    # Change one actual DSL endpoint, preserving the component/pad inventory.
    lines = source.splitlines(keepends=True)
    matches = [i for i, line in enumerate(lines) if '(instance "C_LF1"' in line]
    assert len(matches) == 1
    index = matches[0]
    assert '(pin 1 "LMX_CPOUT")' in lines[index]
    lines[index] = lines[index].replace('(pin 1 "LMX_CPOUT")', '(pin 1 "LMX_VTUNE")')
    changed = geometry(execute(args.runner.resolve(), args.project.resolve(), ''.join(lines)))
    key = 'C_LF1', '1'
    assert baseline[0][key][0] == 'LMX_CPOUT'
    assert changed[0][key][0] == 'LMX_VTUNE'
    assert baseline[0][key][1] != changed[0][key][1], 'rewired component did not move to its new anchor'
    assert baseline[1]['LMX_CPOUT'] != changed[1]['LMX_CPOUT']
    assert baseline[1]['LMX_VTUNE'] != changed[1]['LMX_VTUNE']
    # A real guest mutation removes route spans while preserving all pin metadata.
    # The independent oracle must reject it, proving metadata counts are insufficient.
    with tempfile.TemporaryDirectory(prefix='schematic-route-mutant-') as directory:
        mutant = Path(directory) / 'guest'
        shutil.copytree(args.project.resolve(), mutant)
        renderer = mutant / 'svg.my'
        changed_source, count = re.subn(
            r'd\.line\(item\.x1,\s*item\.y1,\s*item\.x2,\s*item\.y2\)',
            'd.line(item.x1, item.y1, item.x1, item.y1)', renderer.read_text())
        assert count == 1, 'route drawing mutation target changed; update the mutation deliberately'
        renderer.write_text(changed_source)
        broken = execute(args.runner.resolve(), mutant, source)
        try:
            geometry(broken)
        except AssertionError as failure:
            assert 'disconnected drawn net' in str(failure), failure
        else:
            raise AssertionError('oracle accepted guest renderer with all routed spans removed')
    print('Schematic geometry: Manhattan signal connectivity, no wrong-net pad touches, source-driven rewiring and rejected guest route mutation pass')


if __name__ == '__main__':
    main()
