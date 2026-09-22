#!/usr/bin/env python3
"""Independent correctness qualification for the full-SVG benchmark arms."""
from collections import defaultdict
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
WORK = ROOT / '.tmp/full-svg-benchmark-20260921'
ARTIFACTS = OUT / 'artifacts'
sys.path[:0] = [str(OUT), str(ROOT / 'tests')]

from measure import ARMS, CASES, NATIVE_ARMS, digest, invoke
from schematic_layout import geometry
from schematic_svg import fixture_model, inspect_svg

MYLANG = tuple(arm for arm in ARMS if arm.startswith('mylang'))
NETLISP = tuple(arm for arm in ARMS if arm.startswith('netlisp'))
# The native arms must reproduce the mylang guest's SVG bytes exactly; they are
# separately qualified by the same independent model and geometry oracle.
NATIVE = tuple(arm for arm in ARMS if arm in NATIVE_ARMS)


def class_has(element, name):
    return name in element.attrib.get('class', '').split()


def expected_model(case):
    source = (WORK / 'projects' / case / 'lib/modules/straps-synth-lmx2595.sexp').read_text()
    components, aliases, pads, nc = fixture_model(source)
    nets = defaultdict(set)
    for (reference, pin), net in pads.items():
        nets[net].add((aliases[reference], pin))
    return source, components, aliases, pads, nc, dict(nets)


def qualify_mylang(case, arm, svg, expected):
    source, components, _, pads, nc, nets = expected
    root, actual_components, actual_pads, actual_nc, ports = inspect_svg(svg)
    geometry(root)
    assert actual_components == components
    assert actual_pads == pads
    assert actual_nc == nc
    assert len(nets) == 34 and len(ports) == 9
    if case == 'changed-net':
        assert b'LMX_CE_BENCH' in svg and 'LMX_CE_BENCH' in source
    if case == 'changed-value':
        assert actual_components['C_LF1'][1] == '470pF' and b'470pF' in svg
    return {
        'svg_sha256': digest(svg), 'svg_bytes': len(svg), 'geometry': 'passed',
        'model': {'components': len(actual_components), 'connected_pins': len(actual_pads),
                  'nc_pins': len(actual_nc), 'nets': len(nets), 'ports': len(ports)},
    }


def read_netlisp_verification(arm, case):
    path = WORK / f'{arm}-{case}-verify.json'
    _, svg, _ = invoke(arm, case, extra=('--verify', str(path)))
    return svg, json.loads(path.read_text())


def qualify_netlisp(case, arm, svg, model, expected):
    source, components, aliases, pads, _, expected_nets = expected
    assert len(model['instances']) == len(components) == 30
    assert {item['ref'] for item in model['instances']} == set(aliases.values())
    actual_nets = {
        item['name']: {(pin['ref'], pin['pin']) for pin in item['pins']}
        for item in model['nets']
    }
    assert actual_nets == expected_nets
    assert sum(len(item['pins']) for item in model['nets']) == len(pads) == 95
    assert len(model['nets']) == 34 and len(model['ports']) == 9
    root = ET.fromstring(svg)
    visible_ic = [item for item in root.iter() if class_has(item, 'pin-stub') and item.attrib.get('data-ref') == 'U1']
    passives = [item for item in root.iter() if item.attrib.get('data-passive-count') == '1']
    assert len(visible_ic) == 37
    assert len(passives) == 29
    passive_refs = [item.attrib['data-ref'] for item in passives]
    assert len(set(passive_refs)) == 29
    assert set(passive_refs) == set(aliases.values()) - {'U1'}
    if case == 'changed-net':
        assert b'LMX_CE_BENCH' in svg and 'LMX_CE_BENCH' in actual_nets and 'LMX_CE_BENCH' in source
    if case == 'changed-value':
        assert b'470pF' in svg
    return {
        'svg_sha256': digest(svg), 'svg_bytes': len(svg),
        'model': {'components': len(model['instances']), 'connected_pins': len(pads),
                  'nets': len(model['nets']), 'ports': len(model['ports']),
                  'visible_ic_pins': len(visible_ic), 'passives': len(passives)},
    }


def compare_cross_engine(netlisp_svg, netlisp_model, mylang_svg):
    """Compare shared semantic and geometry facts despite different SVG markup."""
    net_root = ET.fromstring(netlisp_svg)
    my_root, _, _, _, my_ports = inspect_svg(mylang_svg)
    assert net_root.attrib['viewBox'] == my_root.attrib['viewBox']

    normalize_direction = {
        'in': 'input', 'input': 'input', 'out': 'output', 'output': 'output',
        'bidi': 'bidirectional', 'bidirectional': 'bidirectional',
    }
    net_ports = {
        port['name']: normalize_direction.get(port['direction'], port['direction'])
        for port in netlisp_model['ports']
    }
    assert net_ports == {
        name: normalize_direction.get(direction, direction)
        for name, direction in my_ports.items()
    }

    my_chip = next(item for item in my_root.iter() if item.attrib.get('data-ref') == 'U1')
    my_pins = {
        item.attrib['data-pin']: (float(item.attrib['data-x']), float(item.attrib['data-y']))
        for item in my_chip.iter()
        if item.attrib.get('data-pin') and 'data-nc' not in item.attrib
    }
    net_pins = {}
    for stub in net_root.iter():
        if not (class_has(stub, 'pin-stub') and stub.attrib.get('data-ref') == 'U1'):
            continue
        line = next(item for item in stub if item.tag.endswith('line'))
        endpoints = ((float(line.attrib['x1']), float(line.attrib['y1'])),
                     (float(line.attrib['x2']), float(line.attrib['y2'])))
        expected_x = my_pins[stub.attrib['data-pin']][0]
        candidates = [point for point in endpoints if point[0] == expected_x]
        assert len(candidates) == 1
        net_pins[stub.attrib['data-pin']] = candidates[0]
    assert len(net_pins) == len(my_pins) == 37 and set(net_pins) == set(my_pins)
    differences = {
        pin: {'netlisp': list(net_pins[pin]), 'mylang': list(my_pins[pin])}
        for pin in sorted(my_pins, key=int) if net_pins[pin] != my_pins[pin]
    }
    assert len(differences) == 6
    return {
        'viewBox': net_root.attrib['viewBox'], 'matched_connected_ic_pins': 31,
        'different_connected_ic_pins': differences,
        'pixel_identical': False,
    }


def main():
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    cases = {}
    outputs = {}
    netlisp_models = {}
    layout_comparison = {}
    for case in CASES:
        expected = expected_model(case)
        cases[case] = {}
        for arm in ARMS:
            if arm in NETLISP:
                svg, model = read_netlisp_verification(arm, case)
                facts = qualify_netlisp(case, arm, svg, model, expected)
                netlisp_models[case, arm] = model
                if arm == NETLISP[0]:
                    (ARTIFACTS / f'{case}-{arm}-model.json').write_text(
                        json.dumps(model, indent=2) + '\n')
            else:
                _, svg, _ = invoke(arm, case)
                facts = qualify_mylang(case, arm, svg, expected)
            if arm in (NETLISP[0], MYLANG[0]):
                (ARTIFACTS / f'{case}-{arm}.svg').write_bytes(svg)
            outputs[case, arm] = svg
            cases[case][arm] = facts
        assert len({digest(outputs[case, arm]) for arm in MYLANG}) == 1
        assert len({digest(outputs[case, arm]) for arm in NETLISP}) == 1
        assert len({digest(outputs[case, arm]) for arm in MYLANG + NATIVE}) == 1
        layout_comparison[case] = compare_cross_engine(
            outputs[case, NETLISP[0]], netlisp_models[case, NETLISP[0]],
            outputs[case, MYLANG[0]])

    for arms in (MYLANG, NETLISP, NATIVE):
        for arm in arms:
            assert outputs['fixture', arm] != outputs['changed-net', arm]
            assert outputs['fixture', arm] != outputs['changed-value', arm]

    gc_stress = {}
    for arm in MYLANG:
        _, stressed, _ = invoke(arm, 'fixture', extra=('--gc-stress',))
        assert stressed == outputs['fixture', arm]
        gc_stress[arm] = {'svg_sha256': digest(stressed), 'equals_normal': True}

    evidence = {
        'passed': True,
        'comparison': 'exact SVG equality within each implementation family; semantic model and independent renderer oracles across families',
        'cases': cases,
        'family_equality': {'mylang': list(MYLANG), 'netlisp_zig': list(NETLISP),
                            'mylang_identical_native_ports': list(NATIVE)},
        'layout_comparison': layout_comparison,
        'gc_stress': gc_stress,
    }
    (OUT / 'qualification.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps({'passed': True, 'hashes': {
        case: {arm: cases[case][arm]['svg_sha256'] for arm in ARMS} for case in CASES
    }}, indent=2))


if __name__ == '__main__':
    main()
