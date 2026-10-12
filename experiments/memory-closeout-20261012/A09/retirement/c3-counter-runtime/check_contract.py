#!/usr/bin/env python3
"""Synthetic C3 parser controls using an unchanged historical JSON fixture.

This exercises schema classification only; the input was produced by C0 and is
never presented as execution of a retired runtime.
"""
import copy
import gzip
import hashlib
import json
from pathlib import Path
import tempfile

import contract


def main():
    fixture = contract.ROOT / 'experiments/memory-closeout-20261012/A09/raw/size-aligned-C0-native-replay/raw/array/array-counts.json.gz'
    original = gzip.decompress(fixture.read_bytes())
    data = json.loads(original)
    checks = []
    with tempfile.TemporaryDirectory(prefix='a09-counter-contract-') as temporary:
        path = Path(temporary) / 'counts.json'

        def parse(value, abi=contract.ABI):
            path.write_text(json.dumps(value))
            return contract.audit(path, guest_abi=abi)

        def rejected(label, mutate=lambda raw: None, abi=contract.ABI):
            raw = copy.deepcopy(data)
            mutate(raw)
            try:
                parse(raw, abi)
            except ValueError as error:
                checks.append({'case': label, 'passed': True, 'error': str(error)})
            else:
                raise AssertionError(label + ' was accepted')

        report = parse(data)
        assert report['direct_frees'] > 0
        assert 'observed_rc_free' not in report
        assert report['rc_compatibility_fields_zero'] is True
        checks.append({'case': 'explicit zeros and positive direct destruction accepted', 'passed': True})
        rejected('historical ABI rejected', abi='mylang-zero-rc-v2')
        rejected('missing runtime total', lambda raw: raw['totals'].pop('runtime_retains'))
        rejected('missing sharing bytes total', lambda raw: raw['totals'].pop('share_bytes'))
        rejected('missing function field', lambda raw: raw['functions'][0].pop('shared_retains'))
        rejected('missing kind', lambda raw: raw['kinds'].pop('retain'))
        rejected('missing kind bytes', lambda raw: raw['kinds']['retain'].pop('bytes'))
        rejected('missing kind extra', lambda raw: raw['kinds']['retain'].pop('extra'))
        rejected('nonzero reserved total', lambda raw: raw['totals'].__setitem__('share_bytes', 1))
        rejected('nonzero reserved function slot', lambda raw: raw['functions'][0].__setitem__('share_bytes', 1))
        rejected('nonzero reserved kind bytes', lambda raw: raw['kinds']['release'].__setitem__('bytes', 1))
        rejected('nonzero reserved kind extra', lambda raw: raw['kinds']['unique_test'].__setitem__('extra', 1))
        rejected('boolean zero rejected', lambda raw: raw['totals'].__setitem__('share_bytes', False))
        rejected('string zero rejected', lambda raw: raw['totals'].__setitem__('share_bytes', '0'))
        rejected('obsolete zero-valued RC site rejected', lambda raw: raw['sites'].append({'kind': 'retain', 'count': 0}))
        for label, structural in [('missing structural proof', {}),
                                  ('failed structural proof', {'guest_abi': contract.ABI, 'passed': False}),
                                  ('wrong structural ABI', {'guest_abi': 'mylang-zero-rc-v2', 'passed': True})]:
            assert not contract.qualified(report, structural)
            checks.append({'case': label, 'passed': True})
        structure = {'guest_abi': contract.ABI, 'passed': True}
        assert contract.qualified(report, structure)
        checks.append({'case': 'explicit structural proof and leak-free counters required together', 'passed': True})
        leaking = copy.deepcopy(report)
        leaking['managed_leak_free'] = False
        assert not contract.qualified(leaking, structure)
        checks.append({'case': 'managed leak blocks qualification', 'passed': True})
    result = {'scope': 'Synthetic parser controls, not retired-runtime execution evidence',
              'fixture': str(fixture.relative_to(contract.ROOT)),
              'fixture_raw_sha256': hashlib.sha256(original).hexdigest(),
              'contract_sha256': hashlib.sha256(Path(contract.__file__).read_bytes()).hexdigest(),
              'checks': checks}
    Path(__file__).with_name('parser-controls.json').write_text(json.dumps(result, indent=2) + '\n')
    print(f'{len(checks)} parser controls passed')


if __name__ == '__main__':
    main()
