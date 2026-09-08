"""Language-neutral tasks. Readiness is explicit, never implied by an oracle."""
VERSION = 'development-velocity-corpus-v1'
TASKS = [
    ('data-rollup', 'data-text', 'feature', 'small', ['std_hash_bytes', 'std_collections']),
    ('ascii-table', 'data-text', 'feature', 'small', ['std_bytes', 'std_format']),
    ('config-layers', 'configuration', 'feature', 'small', ['std_json_view', 'std_hash_bytes']),
    ('quota-boundary', 'configuration', 'bugfix', 'small', ['std_math']),
    ('lru-cache', 'stateful-collections', 'feature', 'medium', ['std_hash_bytes', 'std_collections']),
    ('ttl-boundary', 'stateful-collections', 'bugfix', 'medium', ['std_hash_bytes', 'std_collections']),
    ('record-frames', 'binary-codecs', 'feature', 'small', ['std_encoding', 'std_bytes']),
    ('little-endian-read', 'binary-codecs', 'bugfix', 'small', ['std_encoding']),
    ('snapshot-diff', 'filesystem-path', 'feature', 'medium', ['std_path', 'std_hash_bytes', 'std_collections']),
    ('mount-routing', 'filesystem-path', 'feature', 'medium', ['std_path', 'std_bytes']),
    ('inventory-reservations', 'multi-module-maintenance', 'feature', 'medium', ['std_hash_bytes', 'std_collections']),
    ('atomic-transfers', 'multi-module-maintenance', 'bugfix', 'medium', ['std_hash_bytes', 'std_collections']),
]
IDS = tuple(row[0] for row in TASKS)


def catalog():
    return {'version': VERSION, 'transport': 'bounded-json-batch-v1', 'tasks': [
        {'id': task, 'family': family, 'kind': kind, 'tier': tier,
         'brief': 'briefs/' + task + '.md', 'modules': 3 if family == 'multi-module-maintenance' else 2,
         'required_my_modules': ['std_json', 'std_json_view', 'std_text'] + modules,
         'readiness': 'blocked-preparation',
         'prerequisites': ['equivalent my/Python runtime scaffold and starter acceptance',
                           'task-scoped standard-library parity proof',
                           'independent generated-case review and private seed freeze']}
        for task, family, kind, tier, modules in TASKS]}

# These identify one semantic mutation in each otherwise-correct equivalent starter.
# Starter implementations are a separate untimed prerequisite, not oracle code.
MUTATIONS = {
    'quota-boundary': {'correct': 'used + amount <= limit', 'seeded': 'used + amount < limit',
                       'site': 'quota decision in app.my / app.py'},
    'ttl-boundary': {'correct': 'expires_at <= now', 'seeded': 'expires_at < now',
                     'site': 'expiry sweep in app.my / app.py'},
    'little-endian-read': {'correct': 'little-endian two-byte decode', 'seeded': 'big-endian two-byte decode',
                           'site': 'standard-library decode byte-order argument in app.my / app.py'},
    'atomic-transfers': {'correct': 'commit staged balances only if every transfer succeeds',
                         'seeded': 'commit staged balances even after a later transfer fails',
                         'site': 'transaction commit guard in ledger.my / ledger.py'},
}
