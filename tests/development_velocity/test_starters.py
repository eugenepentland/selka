"""Hand-authored starter checks, independent of corpus oracles/private packs."""
from copy import deepcopy
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "experiments/development_velocity"
STARTERS = PROJECT / "starters"
RECEIPT = PROJECT / "starter-mutations.json"


def invoke(task, requests, language, corrected=True):
    rules = json.loads(RECEIPT.read_text())["tasks"]
    with tempfile.TemporaryDirectory(prefix="velocity-starter-") as temporary:
        directory = Path(temporary)
        extension = "*.my" if language == "my" else "*.py"
        for source in (PROJECT / "runtime" / language, STARTERS / task / language):
            for path in source.glob(extension):
                shutil.copyfile(path, directory / path.name)
        if corrected:
            rule = rules[task][language]
            path = directory / rule["file"]
            source = path.read_text()
            # Also supports validating correct sources before the seeding step.
            if rule["seeded"] in source:
                if source.count(rule["seeded"]) != 1:
                    raise AssertionError("mutation must have one exact source site")
                source = source.replace(rule["seeded"], rule["correct"])
            elif source.count(rule["correct"]) != 1:
                raise AssertionError("neither corrected nor seeded source site")
            path.write_text(source)
        if language == "my":
            host = Path(os.environ.get("MYLANG_IO", ROOT / "zig-out/bin/mylang-io"))
            if not host.is_file():
                raise RuntimeError("Build/install mylang-io before preparation tests")
            command = [str(host.resolve()), "--project", str(directory)]
        else:
            command = [sys.executable, "-B", str(directory / "main.py")]
        raw = json.dumps({"requests": requests}, ensure_ascii=False, separators=(",", ":"))
        run = subprocess.run(command, input=raw, text=True, capture_output=True, timeout=60)
        if run.returncode:
            raise AssertionError((task, language, run.returncode, run.stderr))
        answer = json.loads(run.stdout)
        if set(answer) != {"results"} or len(answer["results"]) != len(requests):
            raise AssertionError(("response shape", answer))
        return answer["results"]


def account(name, balance):
    return {"id": name, "balance": balance}


def transfer(source, target, amount):
    return {"from": source, "to": target, "amount": amount}


class Starters(unittest.TestCase):
    def check_both(self, task, requests, expected, corrected=True):
        for language in ("my", "python"):
            with self.subTest(task=task, language=language):
                self.assertEqual(invoke(task, requests, language, corrected), expected)

    def test_corrected_quota(self):
        requests = [dict(limit=5, used=1, requests=[4, 0, 1]),
                    dict(limit=0, used=0, requests=[0, 1]),
                    dict(limit=10, used=2, requests=[3, 6, 1]),
                    dict(limit=1000000, used=0, requests=[1000000]),
                    dict(limit=4, used=0, requests=[]),
                    dict(limit=5, used=0, requests=[1000000, True])]
        expected = [dict(accepted=[True, True, False], used=5, remaining=0),
                    dict(accepted=[True, False], used=0, remaining=0),
                    dict(accepted=[True, False, True], used=6, remaining=4),
                    dict(accepted=[True], used=1000000, remaining=0),
                    dict(accepted=[], used=0, remaining=4), {"error": "invalid-request"}]
        self.check_both("quota-boundary", requests, expected)

    def test_corrected_codec(self):
        requests = [dict(hex="0102ff00", offsets=[0, 1, 2, 0]),
                    dict(hex="", offsets=[]), dict(hex="01", offsets=[0]),
                    dict(hex="00" * 512, offsets=[510]),
                    dict(hex="00" * 512, offsets=[511]),
                    dict(hex="FF00", offsets=[]), dict(hex="0", offsets=[]),
                    dict(hex="", offsets=[0, True]), dict(hex="0000", offsets=[0.0])]
        self.check_both("little-endian-read", requests,
                        [dict(values=[513, 65282, 255, 513]), dict(values=[]),
                         {"error": "out-of-bounds"}, dict(values=[0]),
                         {"error": "out-of-bounds"}] + [{"error": "invalid-request"}] * 4)

    def test_corrected_ttl(self):
        put = lambda at, key, value, ttl: dict(op="put", at=at, key=key, value=value, ttl=ttl)
        get = lambda at, key: dict(op="get", at=at, key=key)
        requests = [dict(operations=[]),
                    dict(operations=[put(0, "a", 7, 2), get(1, "a"), get(2, "a")]),
                    dict(operations=[put(0, "a", 7, 0)]),
                    dict(operations=[put(0, "a", 7, 0), get(0, "a")]),
                    dict(operations=[put(0, "z", -1, 10), put(1, "a", 2, 10), put(2, "z", 8, 1), get(4, "z")]),
                    dict(operations=[put(3, "a", 1, 8), get(2, "a")]),
                    dict(operations=[put(0, "a", True, 8)]),
                    dict(operations=[put(1000000, "a", 1000000, 1000000)])]
        expected = [dict(results=[], live=[]), dict(results=[None, 7, None], live=[]),
                    dict(results=[None], live=[]), dict(results=[None, None], live=[]),
                    dict(results=[None, None, None, None], live=["a"]),
                    {"error": "invalid-request"}, {"error": "invalid-request"},
                    dict(results=[None], live=["a"])]
        self.check_both("ttl-boundary", requests, expected)

    def test_corrected_atomic(self):
        base = dict(accounts=[account("b", 0), account("a", 10)], batches=[])
        requests = [dict(base, batches=[[transfer("a", "b", 4), transfer("a", "x", 1)],
                                       [transfer("a", "b", 8)]]),
                    dict(base, batches=[[transfer("a", "b", 4), transfer("a", "b", 7)], []]),
                    dict(base, batches=[[transfer("a", "a", 11)], [transfer("a", "a", 10)]]),
                    dict(accounts=[], batches=[[]]),
                    dict(base, batches=[[transfer("b", "missing", 1)]]),
                    dict(base, batches=[[transfer("missing", "a", 1)], [transfer("a", "b", True)]]),
                    dict(accounts=[account("a", 1), account("a", 2)], batches=[])]
        expected = [dict(results=["unknown-account", "committed"], balances=[account("a", 2), account("b", 8)]),
                    dict(results=["insufficient", "committed"], balances=[account("a", 10), account("b", 0)]),
                    dict(results=["insufficient", "committed"], balances=[account("a", 10), account("b", 0)]),
                    dict(results=["committed"], balances=[]),
                    dict(results=["unknown-account"], balances=[account("a", 10), account("b", 0)]),
                    {"error": "invalid-request"}, {"error": "invalid-request"}]
        self.check_both("atomic-transfers", requests, expected)

    def test_supported_collection_and_array_limits(self):
        names = ["k" + str(i).zfill(3) for i in range(128)]
        requests = [dict(operations=[dict(op="put", at=0, key=n, value=i, ttl=1) for i, n in enumerate(names)]),
                    dict(operations=[dict(op="get", at=0, key="a")] * 129)]
        self.check_both("ttl-boundary", requests,
                        [dict(results=[None] * 128, live=names), {"error": "invalid-request"}])
        self.check_both("quota-boundary", [dict(limit=1000000, used=0, requests=[0] * 128)],
                        [dict(accepted=[True] * 128, used=0, remaining=1000000)])
        self.check_both("little-endian-read", [dict(hex="ffff", offsets=[0] * 128)],
                        [dict(values=[65535] * 128)])
        accounts = [account(n, 1000000) for n in names[:32]]
        batches = [[transfer(names[0], names[1], 0)] * 32] * 32
        self.check_both("atomic-transfers", [dict(accounts=accounts, batches=batches)],
                        [dict(results=["committed"] * 32, balances=accounts)])

    def test_seeded_mutations_fail_target_and_preserve_nonboundary(self):
        targets = {
            "quota-boundary": (dict(limit=5, used=1, requests=[4]),
                               dict(accepted=[False], used=1, remaining=4)),
            "ttl-boundary": (dict(operations=[dict(op="put", at=0, key="a", value=7, ttl=1),
                                              dict(op="get", at=1, key="a")]),
                             dict(results=[None, 7], live=["a"])),
            "little-endian-read": (dict(hex="0102", offsets=[0]), dict(values=[258])),
            "atomic-transfers": (dict(accounts=[account("a", 10), account("b", 0)],
                                      batches=[[transfer("a", "b", 4), transfer("a", "x", 1)]]),
                                 dict(results=["unknown-account"], balances=[account("a", 6), account("b", 4)]))}
        unchanged = {
            "quota-boundary": dict(limit=10, used=0, requests=[1, 2]),
            "ttl-boundary": dict(operations=[dict(op="put", at=0, key="a", value=7, ttl=5), dict(op="get", at=1, key="a")]),
            "little-endian-read": dict(hex="ffff0000", offsets=[0, 2]),
            "atomic-transfers": dict(accounts=[account("a", 10), account("b", 0)], batches=[[transfer("a", "b", 4)]])}
        for task, (request, seeded_expected) in targets.items():
            self.check_both(task, [request], [seeded_expected], corrected=False)
            for language in ("my", "python"):
                with self.subTest(task=task, language=language):
                    self.assertNotEqual(invoke(task, [request], language, True), [seeded_expected])
                    self.assertEqual(invoke(task, [unchanged[task]], language, False),
                                     invoke(task, [unchanged[task]], language, True))

    def test_receipts_pin_exact_single_mutation_and_three_atomic_modules(self):
        receipt = json.loads(RECEIPT.read_text())
        for task, rules in receipt["tasks"].items():
            for language, rule in rules.items():
                path = STARTERS / task / language / rule["file"]
                source = path.read_text()
                self.assertEqual(source.count(rule["seeded"]), 1)
                self.assertEqual(source.count(rule["correct"]), 0)
                self.assertEqual(hashlib.sha256(source.encode()).hexdigest(), rule["seeded_sha256"])
                corrected = source.replace(rule["seeded"], rule["correct"])
                self.assertEqual(hashlib.sha256(corrected.encode()).hexdigest(), rule["corrected_sha256"])
        for language, extension in (("my", "my"), ("python", "py")):
            self.assertEqual({p.name for p in (STARTERS / "atomic-transfers" / language).glob("*." + extension)},
                             {"app." + extension, "ledger." + extension, "model." + extension})

    def test_inventory_feature_baseline_reports_stock_and_rejects_malformed_ops(self):
        stock = [{"id": "z", "quantity": 0}, {"id": "a", "quantity": 1000000}]
        reserve = {"op": "reserve", "token": "t", "id": "a", "quantity": 3}
        release = {"op": "release", "token": "t"}
        requests = [dict(stock=stock, operations=[]),
                    dict(stock=stock, operations=[reserve, release]),
                    dict(stock=stock, operations=[reserve] * 128),
                    dict(stock=stock, operations=[dict(reserve, quantity=0)]),
                    dict(stock=stock + [stock[0]], operations=[]),
                    dict(stock=stock, operations=[dict(release, extra=1)])]
        expected = [dict(results=[], available=stock[::-1], active=[]),
                    dict(results=["unsupported-operation"] * 2, available=stock[::-1], active=[]),
                    dict(results=["unsupported-operation"] * 128, available=stock[::-1], active=[])]
        self.check_both("inventory-reservations", requests,
                        expected + [{"error": "invalid-request"}] * 3, corrected=False)
        for language, extension in (("my", "my"), ("python", "py")):
            self.assertEqual({p.name for p in (STARTERS / "inventory-reservations" / language).glob("*." + extension)},
                             {"app." + extension, "ledger." + extension, "model." + extension})


if __name__ == "__main__":
    unittest.main()
