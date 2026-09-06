"""Fresh post-submission behavioral cases, independent of either validator source."""
from copy import deepcopy
import importlib.util
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
_spec = importlib.util.spec_from_file_location('board_oracle', ROOT / 'experiments/board_trial/oracle.py')
oracle = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(oracle)
UNIT_DEVELOPMENT = [-1_000_000, -1001, -1, 0, 1, 37, 1001, 1_000_000]


def units(seed):
    rng = random.Random(seed)
    return [rng.randint(-1_000_000_000, 1_000_000_000) for _ in range(64)]


def boards(seed):
    rng = random.Random(seed)
    result = []
    for index in range(128):
        x, y = rng.randint(-10000, 10000), rng.randint(-10000, 10000)
        size = rng.randint(10, 500)
        component, net = rng.sample(range(1, 2**32), 2)
        if index % 11 == 0:
            net = component
        region = {'rect': [x, y, size, size], 'face': rng.choice(['top', 'bottom', 'both']),
                  'blocks': ['component', 'track', 'via'], 'allow_nets': []}
        feature_rect = [x, y, rng.randint(1, size), rng.randint(1, size)]
        feature = [
            {'kind': 'component', 'id': component, 'face': rng.choice(['top', 'bottom']), 'rect': feature_rect},
            {'kind': 'track', 'net': net, 'layer': rng.choice(['front', 'back', 'inner']), 'rect': feature_rect},
            {'kind': 'via', 'net': net, 'rect': feature_rect},
        ][index % 3]
        board = {'outline': [x, y, size, size], 'components': [component], 'nets': [net],
                 'regions': [region], 'features': [feature]}
        mode = index % 8
        if mode == 0:
            region['face'] = 'both'
            region['allow_nets'] = [net]
        elif mode == 1:
            feature_rect[0] -= 1
        elif mode == 2:
            feature_rect[0] += size
        elif mode == 3:
            board['regions'].append(deepcopy(region))
        elif mode == 4:
            board['components'].append(component)
        elif mode == 5:
            board['nets'] = []
        elif mode == 6:
            feature_rect[2] = 0
        unavailable = index % 17 == 0
        document = {'version': 1, 'board': board}
        result.append({'name': f'heldout_{index:03}', 'input': document, 'unavailable': unavailable,
                       'expected': oracle.evaluate(document, unavailable)})
    return result
