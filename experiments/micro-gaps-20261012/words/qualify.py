"""Qualify unchanged text workloads; elapsed protocol field is not timing evidence."""
import hashlib, json, os, pathlib, re, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/expanded'))
import registry

def main():
    binary = pathlib.Path(sys.argv[1]).resolve()
    output = pathlib.Path(sys.argv[2]).resolve()
    output.mkdir(parents=True, exist_ok=True)
    results = []
    for case, meta in registry.inventory().items():
        if meta['group'] != 'text':
            continue
        for size, seed, iterations in list(registry.EDGE_PROBES) + [(size, 42, 3) for size in meta['sizes']]:
            counter = output / f'{case}-{size}-{seed}-{iterations}.json'
            env = dict(os.environ, MYLANG_COUNTERS=str(counter), MYL_CORE_LEAKCHECK='1')
            command = [str(binary), case, str(size), str(iterations), str(seed)]
            ran = subprocess.run(command, text=True, capture_output=True, env=env, timeout=60)
            expected = registry.checksum(case, size, iterations, seed)
            parsed = re.fullmatch(r'(\d+) (\d+)\n', ran.stdout)
            data = json.loads(counter.read_text()) if counter.exists() else None
            clean = data is None or (data['totals']['live_bytes_at_exit'] == 0
                and all(data['totals'][name] == 0 for name in ('runtime_retains', 'runtime_releases', 'shared_retains', 'shared_releases', 'share_marks'))
                and all(data['kinds'][name]['count'] == 0 for name in ('retain', 'release', 'unique_test')))
            results.append(dict(case=case, size=size, seed=seed, iterations=iterations,
                command=command, stdout=ran.stdout, stderr=ran.stderr, status=ran.returncode,
                expected=expected, ok=bool(ran.returncode == 0 and parsed and int(parsed[1]) == expected and int(parsed[2]) > 0 and not ran.stderr and clean),
                counters=data))
    payload = dict(binary=str(binary), sha256=hashlib.sha256(binary.read_bytes()).hexdigest(), results=results,
                   all_ok=all(row['ok'] for row in results), note='Protocol validation only; no timing comparison.')
    (output / 'qualification.json').write_text(json.dumps(payload, indent=2) + '\n')
    print(json.dumps(dict(probes=len(results), all_ok=payload['all_ok'])))
    return 0 if payload['all_ok'] else 1

if __name__ == '__main__':
    sys.exit(main())
