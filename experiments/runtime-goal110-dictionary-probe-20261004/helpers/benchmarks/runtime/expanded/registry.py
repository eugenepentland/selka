"""Versioned case inventory shared by the runner and independent verifier."""
import importlib.util
from functools import lru_cache
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
GROUPS = ('legacy', 'compute', 'collections', 'text')
EDGE_PROBES = ((2, 1, 1), (3, 42, 7), (17, 999983, 31))


def module_at(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


@lru_cache(maxsize=1)
def modules():
    return {group: module_at('expanded_oracle_' + group,
                            HERE.parent / 'oracle.py' if group == 'legacy'
                            else HERE / group / 'oracle.py') for group in GROUPS}


@lru_cache(maxsize=1)
def inventory():
    result = {}
    for group, module in modules().items():
        for case in module.CASES:
            if group == 'legacy':
                family = {'record_reads': 'records_calls', 'tagged_stack': 'variants_errors',
                          'mutate_unique': 'ownership', 'mutate_shared': 'ownership'}[case]
                meta = {'family': family, 'level': 'micro',
                        'sizes': [64, 1024 if case.startswith('mutate') else 4096],
                        'unit': 'one contract operation', 'description': 'Original v1 contract: ' + case}
            else:
                meta = dict(module.CASES[case])
            if case in result:
                raise ValueError('duplicate case: ' + case)
            if meta['level'] not in ('micro', 'application'):
                raise ValueError('invalid level: ' + case)
            sizes = meta['sizes']
            if len(sizes) != 2 or any(type(n) is not int or n < 2 for n in sizes) or sizes[0] >= sizes[1]:
                raise ValueError('invalid small/large sizes: ' + case)
            if any(not isinstance(meta[key], str) or not meta[key] for key in ('family', 'unit', 'description')):
                raise ValueError('missing case documentation: ' + case)
            result[case] = {**meta, 'group': group}
    return result


@lru_cache(maxsize=2048)
def checksum(case, size, iterations, seed):
    if size < 2 or iterations < 1 or not 1 <= seed <= 1000000:
        raise ValueError('invalid fixture dimensions')
    answer = modules()[inventory()[case]['group']].checksum(case, size, iterations, seed)
    if type(answer) is not int or answer < 0:
        raise ValueError('oracle returned invalid checksum: ' + case)
    return answer


def plans_for(cases):
    return [{'case': case, 'size': size, 'profile': profile, 'seed': 42,
             'group': inventory()[case]['group'], 'family': inventory()[case]['family'],
             'level': inventory()[case]['level'], 'unit': inventory()[case]['unit']}
            for case in cases
            for profile, size in zip(('small', 'large'), inventory()[case]['sizes'])]
