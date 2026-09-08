"""Hand-derived independent boundary review; no participant solutions or frozen packs."""
import unittest

from experiments.development_velocity.corpus.oracles import expected


class CorpusReviewTests(unittest.TestCase):
    def test_rollup_full_signed_total_and_minimum_equality(self):
        for delta, total in ((1000000, 128000000), (-1000000, -128000000)):
            request = {'rows': [{'key': 'a', 'delta': delta}] * 128, 'minimum': total}
            self.assertEqual(expected('data-rollup', request), {'groups': [{'key': 'a', 'count': 128, 'total': total}]})
        self.assertEqual(expected('data-rollup', {'rows': [{'key': 'a', 'delta': 0}], 'minimum': 1}), {'groups': []})

    def test_ascii_escaping_spaces_and_zero_columns_are_data(self):
        self.assertEqual(expected('ascii-table', {'columns': 2, 'rows': [['"', '\\'], ['', ' x ']]}),
                         {'widths': [1, 3], 'lines': ['" | \\  ', '  |  x ']})
        self.assertEqual(expected('ascii-table', {'columns': 0, 'rows': [[], []]}), {'widths': [], 'lines': ['', '']})

    def test_lru_replacement_refreshes_without_eviction(self):
        ops = [{'op': 'put', 'key': key, 'value': value} for key, value in [('a', 1), ('b', 2), ('a', 3), ('c', 4)]]
        ops.append({'op': 'get', 'key': 'missing'})
        self.assertEqual(expected('lru-cache', {'capacity': 2, 'operations': ops}),
                         {'results': [{'evicted': None}] * 3 + [{'evicted': 'b'}, {'value': None}],
                          'entries': [{'key': 'a', 'value': 3}, {'key': 'c', 'value': 4}]})

    def test_ttl_zero_replacement_does_not_resurrect_older_value(self):
        request = {'operations': [
            {'op': 'put', 'at': 0, 'key': 'a', 'value': 1, 'ttl': 100},
            {'op': 'put', 'at': 1, 'key': 'a', 'value': 2, 'ttl': 0},
            {'op': 'get', 'at': 1, 'key': 'a'}, {'op': 'get', 'at': 2, 'key': 'a'}]}
        self.assertEqual(expected('ttl-boundary', request), {'results': [None] * 4, 'live': []})

    def test_mounts_component_boundary_root_and_overlength_output(self):
        self.assertEqual(expected('mount-routing', {'mounts': [{'prefix': '/a', 'target': '/'}], 'paths': ['/a', '/a/b', '/ab']}),
                         {'paths': ['/', '/b', None]})
        long = '/' + ('a' * 32 + '/') * 7 + 'b' * 24
        self.assertEqual(len(long), 256)
        self.assertEqual(expected('mount-routing', {'mounts': [{'prefix': '/', 'target': long}], 'paths': [long]}),
                         {'paths': [long + long]})
        self.assertEqual(expected('snapshot-diff', {'before': [{'path': '/', 'digest': 'a'}], 'after': [{'path': '/', 'digest': 'b'}]}),
                         {'added': [], 'removed': [], 'changed': ['/']})

    def test_inventory_precedence_release_reuse_and_conservation(self):
        request = {'stock': [{'id': 'a', 'quantity': 2}], 'operations': [
            {'op': 'reserve', 'token': 't', 'id': 'a', 'quantity': 2},
            {'op': 'reserve', 'token': 't', 'id': 'missing', 'quantity': 10},
            {'op': 'reserve', 'token': 'u', 'id': 'missing', 'quantity': 10},
            {'op': 'reserve', 'token': 'u', 'id': 'a', 'quantity': 1},
            {'op': 'release', 'token': 't'},
            {'op': 'reserve', 'token': 't', 'id': 'a', 'quantity': 1}]}
        self.assertEqual(expected('inventory-reservations', request),
                         {'results': ['reserved', 'duplicate-token', 'unknown-item', 'insufficient', 'released', 'reserved'],
                          'available': [{'id': 'a', 'quantity': 1}], 'active': ['t']})

    def test_transfer_unknown_account_precedence_rollback_and_later_batch(self):
        request = {'accounts': [{'id': 'a', 'balance': 1}, {'id': 'b', 'balance': 0}], 'batches': [
            [{'from': 'a', 'to': 'b', 'amount': 1}, {'from': 'a', 'to': 'missing', 'amount': 100}],
            [{'from': 'a', 'to': 'a', 'amount': 1}],
            [{'from': 'a', 'to': 'b', 'amount': 1}]]}
        self.assertEqual(expected('atomic-transfers', request),
                         {'results': ['unknown-account', 'committed', 'committed'],
                          'balances': [{'id': 'a', 'balance': 0}, {'id': 'b', 'balance': 1}]})
        request['batches'].append([{'from': 'a', 'to': 'b', 'amount': False}])
        self.assertEqual(expected('atomic-transfers', request), {'error': 'invalid-request'})

    def test_config_resets_all_fields_and_rejects_late_unknown_field(self):
        request = {'layers': [{'timeout': 0, 'retries': 0, 'enabled': False, 'label': 'x'},
                              {'timeout': None, 'retries': None, 'enabled': None, 'label': None}]}
        self.assertEqual(expected('config-layers', request),
                         {'config': {'timeout': 1000, 'retries': 3, 'enabled': True, 'label': 'default'}, 'changed': []})
        request['layers'].append({'unknown': None})
        self.assertEqual(expected('config-layers', request), {'error': 'invalid-request'})


if __name__ == '__main__':
    unittest.main()
