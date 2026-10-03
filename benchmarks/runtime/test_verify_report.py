"""Rejection checks for the independent baseline verifier."""
import copy
import unittest
from oracle import CASES, checksum
from verify_report import ARMS, REVISION, verify


def fixture():
    report = dict(schema='mylang-runtime-v1', status='complete', profile='baseline', coverage=list(CASES), rounds=2, warmup_rounds=1, plans=[], samples=[], warmups=[], memory=[], qualification=[], identity={'pinned_revision': REVISION}, binary_hashes={arm:'0'*64 for arm in ARMS})
    for case in CASES:
        for size in (64, 1024 if case.startswith('mutate') else 4096):
            plan = dict(case=case, size=size, profile='small' if size==64 else 'large', iterations=3, seed=42, expected=checksum(case,size,3,42))
            report['plans'].append(plan)
            for arm in ARMS:
                base = dict(plan, arm=arm, checksum=plan['expected'], kernel_ns=10, process_wall_ns=20, exit_status=0)
                report['samples'].extend(dict(base,round=r) for r in range(2))
                report['warmups'].append(dict(base,round=-1))
                report['memory'].append(dict(base,peak_rss_kib=100))
    for arm in ARMS:
        for case in CASES:
            for size,seed,count in ((2,1,1),(3,42,7),(17,999983,31)):
                report['qualification'].append(dict(arm=arm,case=case,size=size,seed=seed,iterations=count,checksum=checksum(case,size,count,seed),kernel_ns=10,exit_status=0))
    report['identity_after'] = copy.deepcopy(report['identity'])
    report['binary_hashes_after'] = copy.deepcopy(report['binary_hashes'])
    return report


class VerifierTests(unittest.TestCase):
    def test_complete_report(self):
        self.assertEqual(len(verify(fixture())),48)

    def test_summary(self):
        report = fixture()
        report['summary'] = [dict(arm=arm, case=plan['case'], size=plan['size'], profile=plan['profile'], iterations=3, median_ns_per_op=10/3, min_ns_per_op=10/3, max_ns_per_op=10/3, median_paired_ratio_to_go=1, paired_bootstrap_95_interval=[1,1]) for plan in report['plans'] for arm in ARMS]
        self.assertEqual(len(verify(report)), 48)
        report['summary'][0]['median_ns_per_op'] = 4
        with self.assertRaises(ValueError):
            verify(report)

    def test_rejections(self):
        baseline=fixture()
        mutations = (
            lambda r: r.update(status='smoke'),
            lambda r: r.pop('identity_after'),
            lambda r: r.pop('binary_hashes_after'),
            lambda r: r['samples'][0].pop('exit_status'),
            lambda r: r['samples'].pop(),
            lambda r: r['samples'].append(copy.deepcopy(r['samples'][0])),
            lambda r: r['samples'][0].update(checksum=-1),
            lambda r: r['samples'][0].update(kernel_ns=float('nan')),
            lambda r: r['samples'][0].update(iterations=4),
            lambda r: r['samples'][0].update(stderr='unexpected'),
            lambda r: r['samples'][0].update(exit_status=1),
            lambda r: r['warmups'].pop(),
            lambda r: r['memory'].pop(),
            lambda r: r['qualification'].pop(),
        )
        for mutate in mutations:
            report=copy.deepcopy(baseline)
            mutate(report)
            with self.subTest(mutation=mutate):
                with self.assertRaises(ValueError):
                    verify(report)


if __name__ == '__main__':
    unittest.main()
