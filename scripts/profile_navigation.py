#!/usr/bin/env python3
"""Measure exact navigation-index reuse on the generated larger project."""
import argparse
import hashlib
import json
from pathlib import Path
import tempfile
import time
from navigate import load
from profile_development import summary
from profile_large_project import generate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    cold, warm = [], []
    with tempfile.TemporaryDirectory(prefix='selka-navigation-profile-') as temporary:
        project = Path(temporary) / 'project'
        project.mkdir()
        generate(project, 96, 24)
        cache = Path(temporary) / 'cache'
        for _ in range(5):
            start = time.monotonic()
            index, reused = load(compiler, project / 'main.selka')
            cold.append((time.monotonic() - start) * 1000)
            assert not reused
        load(compiler, project / 'main.selka', cache)
        for _ in range(5):
            start = time.monotonic()
            _, reused = load(compiler, project / 'main.selka', cache)
            warm.append((time.monotonic() - start) * 1000)
            assert reused
        result = {'version': 'navigation-profile-v1', 'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
                  'modules': 97, 'functions': 2401, 'symbols': len(index['symbols']),
                  'references': len(index['references']), 'cold_ms': summary(cold), 'warm_ms': summary(warm),
                  'scope': 'Local sequential complete index generation versus validated disk-cache reuse; includes Python identity/JSON costs.'}
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
