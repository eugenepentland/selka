#!/usr/bin/env python3
"""Freeze deterministic application identities and independently computed answers."""
import hashlib
import gzip
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def digest(data):
    return hashlib.sha256(data).hexdigest()


def prime(n):
    return n >= 2 and all(n % d for d in range(2, int(n ** 0.5) + 1))


def main():
    report = {"base": "fbfcaa7a923186a8e773c3760f81c10aa345a432",
              "generator": "index i, value (17*i+11) mod 97; word index (17*i+11) mod 7",
              "cases": {}}
    for case in ("word_count", "nested_json", "file_processing", "parallel"):
        inputs = {}
        for size in ("small", "large"):
            if case == "word_count":
                n = 64 if size == "small" else 8192
                vocabulary = ("red", "blue", "green", "violet", "amber", "white", "black")
                words = [vocabulary[(i * 17 + 11) % 7] for i in range(n)]
                data = (" ".join(words) + " ").encode()
                answer = f"{n} {len(set(words))} {sum(map(len, words))}\n"
            elif case == "nested_json":
                n = 8 if size == "small" else 512
                records = [{"id": i, "meta": {"score": (17 * i + 11) % 97, "name": f"item-{i}"}} for i in range(n)]
                data = json.dumps({"records": records}, separators=(",", ":")).encode()
                answer = f"{n} {sum(row['meta']['score'] for row in records)}\n"
            elif case == "file_processing":
                n = 64 if size == "small" else 8192
                values = [(17 * i + 11) % 97 for i in range(n)]
                data = "".join(f"{n}\n" for n in values).encode()
                answer = f"{n} {sum(values)}\n"
            else:
                n = 4 if size == "small" else 256
                data = (" ".join(map(str, range(n))) + "\n").encode()
                answer = f"{n} {sum(prime(i) for i in range(n * 1024))}\n"
            path = HERE / "datasets" / (case + "-" + size + ".txt.gz")
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(gzip.compress(data, mtime=0))
            inputs[size] = {"args": [] if size == "small" else ["large"], "n": n,
                            "dataset_sha256": digest(data), "dataset_bytes": len(data),
                            "dataset_archive": str(path.relative_to(HERE)), "stdout": answer}
        sources = {str(p.relative_to(HERE)): digest(p.read_bytes()) for p in sorted((HERE / "programs" / case).glob("*.my"))}
        report["cases"][case] = {"sources": sources, "inputs": inputs}
    (HERE / "manifest.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
